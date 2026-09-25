import AppKit
import Combine
import SwiftUI
import SwiftTerm

/// All coordinates are in AppKit's global, bottom-up screen coordinate space.
struct NotchGeometry {
    let collapsed: CGRect
    let expanded: CGRect
    let topInset: CGFloat
    init(screen: CGRect, left: CGRect?, right: CGRect?, safeTop: CGFloat) {
        let hasNotch = safeTop > 0 && left != nil && right != nil
        let notchLeft = hasNotch ? left!.maxX : screen.midX
        let notchRight = hasNotch ? right!.minX : screen.midX
        topInset = hasNotch ? safeTop : 28
        collapsed = CGRect(x: hasNotch ? notchLeft : screen.midX - 19, y: screen.maxY - topInset,
                           width: hasNotch ? notchRight - notchLeft : 38, height: topInset)
        let width = min(620, screen.width - 32)
        let height = min(520, screen.height - 60)
        expanded = CGRect(x: min(screen.maxX - width - 16, max(screen.minX + 16, (notchLeft + notchRight) / 2 - width / 2)),
                          y: screen.maxY - height, width: width, height: height)
    }
}

final class PeekPanel: NSPanel {
    var escape: (() -> Void)?
    // AppKit otherwise moves borderless windows below the menu bar/notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { escape?() }
}

/// Concave shoulders meet the bezel; the lower corners remain convex.
func peekOutline(in rect: CGRect, shoulder: CGFloat = 16) -> CGPath {
    let w = rect.width, h = rect.height
    let wing = min(shoulder, w / 8, h / 4), r = min(22, h / 3)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: h))
    p.addLine(to: CGPoint(x: w, y: h))
    p.addCurve(to: CGPoint(x: w - wing, y: h - wing), control1: CGPoint(x: w - wing * 0.5523, y: h), control2: CGPoint(x: w - wing, y: h - wing * 0.4477))
    p.addLine(to: CGPoint(x: w - wing, y: r))
    p.addQuadCurve(to: CGPoint(x: w - wing - r, y: 0), control: CGPoint(x: w - wing, y: 0))
    p.addLine(to: CGPoint(x: wing + r, y: 0))
    p.addQuadCurve(to: CGPoint(x: wing, y: r), control: CGPoint(x: wing, y: 0))
    p.addLine(to: CGPoint(x: wing, y: h - wing))
    p.addCurve(to: CGPoint(x: 0, y: h), control1: CGPoint(x: wing, y: h - wing * 0.4477), control2: CGPoint(x: wing * 0.5523, y: h))
    p.closeSubpath()
    return p
}

final class PeekSurface: NSView {
    var clicked: (() -> Void)?
    private let outline = CAShapeLayer()
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        outline.frame = bounds
        outline.path = peekOutline(in: bounds, shoulder: bounds.height > 60 ? 16 : 0)
        layer?.mask = outline
        CATransaction.commit()
    }
    override func mouseDown(with event: NSEvent) { clicked?() }
}

@MainActor final class NotchPeekController: NSObject, ObservableObject {
    @Published private(set) var expanded = false
    @Published var pinned = false
    @Published var terminalMode = false
    @Published private(set) var terminals: [UUID: TerminalSession] = [:]
    @Published private(set) var topInset: CGFloat = 32
    @Published private(set) var notchWidth: CGFloat = 212
    @Published private(set) var width: CGFloat = 620
    @Published private(set) var height: CGFloat = 520
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "claraNotchEnabled")
            if enabled { position(); startPointerTracking() } else { stopPointerTracking(); collapse(); panel?.orderOut(nil) }
        }
    }
    let store: AppStore
    weak var workspaceWindow: NSWindow?
    private(set) var panel: PeekPanel?
    private var geometry: NotchGeometry?
    private var pointerTimer: Timer?
    private var pointerInside = false
    private var opening = false
    private let pointerLocation: () -> NSPoint
    private var hoverTask: DispatchWorkItem?
    private var exitTask: DispatchWorkItem?
    private var transition = 0
    private var menuTracking = false
    private var observers: [NSObjectProtocol] = []
    private var clickMonitor: Any?
    private var projectSubscription: AnyCancellable?

    init(store: AppStore, pointerLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.store = store
        self.pointerLocation = pointerLocation
        enabled = UserDefaults.standard.object(forKey: "claraNotchEnabled") as? Bool ?? true
        super.init()
    }
    func start(workspace: NSWindow?) {
        guard panel == nil else { return }
        workspaceWindow = workspace
        let panel = PeekPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true; panel.becomesKeyOnlyIfNeeded = false
        // Setting isFloatingPanel resets the level, so assign our level afterwards.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.escape = { [weak self] in self?.collapse() }
        let surface = PeekSurface()
        surface.wantsLayer = true; surface.layer?.backgroundColor = NSColor.clear.cgColor
        surface.layer?.masksToBounds = true
        // The camera housing may not deliver NSView tracking events. Sample the
        // pointer's screen coordinates instead; no Accessibility permission needed.
        surface.clicked = { [weak self] in self?.engage() }
        let host = NSHostingView(rootView: PeekShell(controller: self))
        host.frame = surface.bounds; host.autoresizingMask = [.width, .height]
        surface.addSubview(host); panel.contentView = surface
        self.panel = panel
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.collapse(); self?.position() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuTracking = true; self?.exitTask?.cancel() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.menuTracking = false
                if !self.pointerInside { self.hoverExited() }
            }
        })
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.window === self.panel {
                    if event.type == .keyDown && event.keyCode == 53 { self.collapse(); return true }
                    if event.type == .keyDown { self.pinned = true }
                    if event.type == .leftMouseDown, let surface = self.panel?.contentView {
                        var hit = surface.hitTest(surface.convert(event.locationInWindow, from: nil))
                        while let view = hit {
                            if view is NSTextView || view is LocalProcessTerminalView { self.engage(); break }
                            hit = view.superview
                        }
                    }
                }
                return false
            }
            return consumed ? nil : event
        }
        projectSubscription = store.$workspace.map { Set($0.projects.map(\.id)) }.removeDuplicates().sink { [weak self] ids in
            guard let self else { return }
            for id in Array(self.terminals.keys) where !ids.contains(id) { self.terminals.removeValue(forKey: id)?.stop() }
        }
        if enabled { position(); startPointerTracking() }
    }
    private func startPointerTracking() {
        guard panel != nil, pointerTimer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.samplePointer() }
        }
        timer.tolerance = 0.02
        pointerTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func stopPointerTracking() {
        pointerTimer?.invalidate(); pointerTimer = nil; pointerInside = false
    }
    private func samplePointer() {
        guard enabled, let geometry, panel?.isVisible == true else { return }
        let region = expanded || opening ? geometry.expanded : geometry.collapsed
        let inside = region.contains(pointerLocation())
        guard inside != pointerInside else { return }
        pointerInside = inside
        if inside { hoverEntered() } else { hoverExited() }
    }
    private func position() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let layout = NotchGeometry(screen: screen.frame, left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea, safeTop: screen.safeAreaInsets.top)
        notchWidth = screen.safeAreaInsets.top > 0 ? layout.collapsed.width : 0
        geometry = layout; topInset = layout.topInset; width = layout.expanded.width; height = layout.expanded.height
        panel?.setFrame(expanded ? layout.expanded : layout.collapsed, display: true)
        if enabled { panel?.orderFrontRegardless() }
    }
    func hoverEntered() {
        exitTask?.cancel()
        guard !expanded, !opening else { return }
        hoverTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.expand() }
        hoverTask = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: task)
    }
    func hoverExited() {
        hoverTask?.cancel(); exitTask?.cancel()
        guard !pinned, !menuTracking else { return }
        let task = DispatchWorkItem { [weak self] in if self?.pinned == false { self?.collapse() } }
        exitTask = task; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: task)
    }
    func expand() {
        guard enabled, let panel, let geometry else { return }
        hoverTask?.cancel(); exitTask?.cancel()
        guard !expanded, !opening else { return }
        opening = true
        transition += 1; let token = transition
        // Animate only the black shell; mount the chat once it has room to lay out.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.34
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.76, 0, 0.16, 1)
            panel.animator().setFrame(geometry.expanded, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transition == token else { return }
                self.opening = false
                self.expanded = true
                self.panel?.hasShadow = true
                self.panel?.invalidateShadow()
            }
        }
    }
    func engage() { exitTask?.cancel(); pinned = true; expand(); panel?.makeKey() }
    func collapse() {
        hoverTask?.cancel(); exitTask?.cancel(); transition += 1
        expanded = false; opening = false; pinned = false
        panel?.hasShadow = false
        terminals.values.forEach { $0.isPresented = false }
        panel?.makeFirstResponder(nil); panel?.resignKey()
        guard let geometry, let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.76, 0, 0.16, 1)
            panel.animator().setFrame(geometry.collapsed, display: true)
        }
    }
    func quickTerminal() {
        guard let project = store.project else { return }
        if terminals[project.id] == nil { terminals[project.id] = TerminalSession(project: project, number: 1) }
        terminalMode = true; engage()
    }
    func closeTerminal() {
        guard let id = store.project?.id else { return }
        terminals.removeValue(forKey: id)?.stop(); terminalMode = false
    }
    func openWorkspace() {
        collapse(); NSApp.activate(ignoringOtherApps: true)
        let workspace = workspaceWindow ?? NSApp.windows.first(where: { $0 !== panel && $0.styleMask.contains(.titled) })
        workspace?.deminiaturize(nil); workspace?.makeKeyAndOrderFront(nil)
    }
    func send(_ text: String) {
        if store.chat == nil {
            if let project = store.project { store.newProjectChat(project.id) } else { store.newChat() }
        }
        store.draft = text; store.send()
        if store.showSettings { openWorkspace() }
    }
    func shutdown() {
        stopPointerTracking()
        hoverTask?.cancel(); exitTask?.cancel(); transition += 1
        terminals.values.forEach { $0.stop() }; terminals.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }; clickMonitor = nil
        projectSubscription?.cancel(); panel?.orderOut(nil); panel?.contentView = nil; panel?.close(); panel = nil
    }
}

private struct PeekShell: View {
    @ObservedObject var controller: NotchPeekController
    var body: some View {
        Group {
            if controller.expanded {
                PeekContent(controller: controller).environmentObject(controller.store)
                    .frame(width: controller.width, height: controller.height)
            } else {
                Color.clear
                    .contentShape(Rectangle()).onTapGesture { controller.engage() }
                    .accessibilityLabel("Clara notch quick access")
                    .accessibilityAddTraits(.isButton).accessibilityAction { controller.engage() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if controller.expanded {
                WallpaperGlass()
                    .overlay(LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.15),
                        .init(color: .black.opacity(0.65), location: 0.55),
                        .init(color: .black.opacity(0.30), location: 1)
                    ], startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false)
            } else { Color.black }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark).tint(Palette.accent).foregroundStyle(.white.opacity(0.88)).focusEffectDisabled()
    }
}

private struct PeekContent: View {
    @ObservedObject var controller: NotchPeekController
    @EnvironmentObject var store: AppStore
    @State private var revealed = false
    private var chats: [Conversation] { store.project?.chats ?? store.workspace.generalChats }
    var body: some View {
        ZStack(alignment: .top) {
            if controller.terminalMode {
                Group {
                    if let project = store.project, let session = controller.terminals[project.id] {
                        PeekTerminal(session: session, close: controller.closeTerminal).id(session.id)
                    } else {
                        VStack {
                            Spacer()
                            Button("Start quick terminal") { controller.quickTerminal() }.disabled(store.project == nil)
                            Text("Select a project for its own temporary shell.").font(.caption).foregroundStyle(Palette.muted)
                            Spacer()
                        }
                    }
                }.padding(.horizontal, 34).padding(.bottom, 18).padding(.top, controller.topInset + 56)
                    .modifier(PeekReveal(visible: revealed, delay: 0.10))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if store.chat?.messages.isEmpty != false {
                                Text("What are we building?").font(.system(size: 23, weight: .medium)).padding(.top, 20)
                                Text("Your current Clara conversation, right here.").foregroundStyle(Palette.muted)
                            }
                            ForEach(Array((store.chat?.messages ?? []).suffix(30))) { message in MessageView(message: message).id(message.id) }
                            if let running = store.runningChat, running == store.chat?.id { Text(store.activity).font(.caption).foregroundStyle(Palette.muted) }
                            Color.clear.frame(height: 132).id("peek-bottom")
                        }.padding(.horizontal, 38).padding(.top, controller.topInset + 64)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.78), .init(color: .clear, location: 0.97)], startPoint: .top, endPoint: .bottom))
                    .onAppear { proxy.scrollTo("peek-bottom", anchor: .bottom) }
                    .onChange(of: store.chat?.messages.last?.content) { _, _ in proxy.scrollTo("peek-bottom", anchor: .bottom) }
                    .onChange(of: store.chat?.id) { _, _ in proxy.scrollTo("peek-bottom", anchor: .bottom) }
                }
                .modifier(PeekReveal(visible: revealed, delay: 0.10))
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
                    composer
                }.padding(.horizontal, 34).padding(.bottom, 18)
                    .modifier(PeekReveal(visible: revealed, delay: 0.18))
            }
            header
                .padding(.horizontal, 34).padding(.bottom, 24)
                .background(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.65), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        }.onAppear { revealed = true }
    }
    private var header: some View {
            VStack(spacing: 8) {
            HStack(spacing: 0) {
                Menu {
                    Button("General chats") {
                        if let chat = store.workspace.generalChats.first { store.selectChat(chat.id) } else { store.newChat() }
                    }
                    Divider()
                    ForEach(store.workspace.projects) { project in Button(project.name) { store.selectProject(project.id) } }
                } label: { Label(store.project?.name ?? "General", systemImage: "folder").lineLimit(1) }
                .menuStyle(.borderlessButton).tint(Palette.icon).foregroundStyle(Palette.icon).frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0).frame(width: controller.notchWidth)
                Menu {
                    ForEach(chats) { chat in Button(chat.title) { store.selectChat(chat.id) } }
                    Divider()
                    Button("New conversation") {
                        if let project = store.project { store.newProjectChat(project.id) } else { store.newChat() }
                    }
                } label: { Text(store.chat?.title ?? "New conversation").lineLimit(1) }
                .menuStyle(.borderlessButton).tint(Palette.icon).foregroundStyle(Palette.icon).frame(maxWidth: .infinity, alignment: .trailing)
            }.frame(height: controller.topInset)
                .modifier(PeekReveal(visible: revealed, delay: 0))
            HStack(spacing: 8) {
                Spacer()
                IconButton(icon: controller.terminalMode ? "text.bubble" : "terminal", help: controller.terminalMode ? "Show chat" : "Quick terminal") {
                    if controller.terminalMode { controller.terminalMode = false } else { controller.quickTerminal() }
                }.disabled(store.project == nil && !controller.terminalMode)
                IconButton(icon: controller.pinned ? "pin.slash" : "pin", help: controller.pinned ? "Unpin" : "Pin open") { controller.pinned.toggle() }
                IconButton(icon: "arrow.up.right.square", help: "Open in Clara") { controller.openWorkspace() }
                IconButton(icon: "chevron.up", help: "Collapse") { controller.collapse() }
            }.modifier(PeekReveal(visible: revealed, delay: 0.05))
        }.font(.system(size: 11))
    }
    private var composer: some View {
        VStack(spacing: 6) {
                    ChatInput(text: $store.draft, enabled: store.runningChat == nil, submit: controller.send).frame(height: 64)
                    HStack {
                        Button(store.model.isEmpty ? "Choose model" : String(store.model.split(separator: "/").last ?? "Model")) {
                            store.showSettings = true; controller.openWorkspace()
                        }.lineLimit(1).font(.system(size: 10)).buttonStyle(.plain).foregroundStyle(Palette.muted)
                        Spacer()
                        if store.runningChat != nil {
                            IconButton(icon: "stop", help: "Stop response") { store.cancel() }
                        } else {
                            IconButton(icon: "arrow.up", help: "Send message") { controller.send(store.draft) }
                                .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }.padding(12).floatingGlass(tinted: true, radius: 16)
    }
}

private struct PeekReveal: ViewModifier {
    let visible: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.24).delay(delay), value: visible)
    }
}

private struct PeekTerminal: View {
    @ObservedObject var session: TerminalSession
    let close: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if session.activity.running { Circle().fill(.green).frame(width: 5, height: 5) }
                Text("Temporary terminal").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                IconButton(icon: "xmark", help: "End terminal session") { close() }
            }
            TerminalHost(session: session, isActive: true)
                .onAppear { session.isPresented = true }.onDisappear { session.isPresented = false }
        }
    }
}
