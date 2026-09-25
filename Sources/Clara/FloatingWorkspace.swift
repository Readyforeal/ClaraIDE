import SwiftUI

/// One coordinate space for panels and their dock destinations. The native editor
/// and terminal views stay mounted while their glass containers resize and move.
struct FloatingWorkspace: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filePage = 0
    @State private var presentedPanels: Set<UUID> = []
    private let dockButtonSize: CGFloat = 38
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86) }
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let terminalBounds = TerminalLayout(size: size, placement: store.terminalPlacement).terminal
            let inset = WorkspaceLayout.panelInset
            let panelHeight = max(200, size.height - inset - WorkspaceLayout.bottomClearance)
            let dockedFiles = store.projectDocuments.filter(\.minimized)
            let layout = WorkspaceLayout(width: size.width, navigatorOpen: store.showEditor, editorOpen: store.expandedDocument != nil, hasDockedFiles: !dockedFiles.isEmpty)
            let navWidth = layout.navigatorWidth
            let navX = layout.navigatorX
            let dockX = layout.dockX
            let editorX = layout.editorX
            let editorWidth = layout.editorWidth
            let collapsedDock = !store.showEditor
            let itemSize = WorkspaceLayout.dockItemSize
            let dockPadding = WorkspaceLayout.dockPadding
            let itemStride: CGFloat = itemSize + (collapsedDock ? dockPadding : 12)
            let dockHeader: CGFloat = collapsedDock ? itemSize + 3 * dockPadding + 1 : 0
            let slots = max(1, Int((panelHeight - dockHeader - 44) / itemStride))
            // Equal outer padding, item gaps, and spacing around the divider.
            let dockHeight = dockedFiles.isEmpty ? WorkspaceLayout.dockWidth : dockHeader + CGFloat(min(slots, dockedFiles.count)) * itemStride + (dockedFiles.count > slots ? 36 : 0)
            ZStack(alignment: .topLeading) {
                // A standalone navigator, never joined to the editor surface.
                ZStack(alignment: .top) {
                    if store.showEditor {
                        FileNavigator().frame(width: navWidth, height: panelHeight)
                    } else {
                        VStack(spacing: dockPadding) {
                            Button { store.showEditor = true } label: { Image(systemName: "folder").font(.system(size: 18)).frame(width: itemSize, height: itemSize) }
                                .buttonStyle(DockButtonStyle(radius: 8)).foregroundStyle(Palette.icon).help("Open file navigator")
                                .accessibilityLabel("Open file navigator")
                                .disabled(store.project == nil)
                            if !dockedFiles.isEmpty { Rectangle().fill(.white.opacity(0.13)).frame(width: 28, height: 1) }
                        }.padding(.top, dockPadding).frame(width: navWidth, height: dockHeight, alignment: .top)
                    }
                }
                .modifier(PanelShell(rect: CGRect(x: navX, y: inset, width: navWidth,
                    height: store.showEditor ? panelHeight : dockHeight), tinted: true))
                .opacity((store.showTerminal || store.showBrowser) ? 0 : 1)
                .allowsHitTesting(!store.showTerminal && !store.showBrowser).accessibilityHidden(store.showTerminal || store.showBrowser)
                .zIndex(3)

                ForEach(store.projectDocuments) { document in
                    let index = dockedFiles.firstIndex(where: { $0.id == document.id }) ?? 0
                    let expanded = !document.minimized && presentedPanels.contains(document.id)
                    let visible = expanded || (index >= filePage && index < filePage + slots)
                    let width: CGFloat = expanded ? editorWidth : itemSize
                    let height: CGFloat = expanded ? panelHeight : itemSize
                    ZStack(alignment: .topLeading) {
                        FileEditorPanel(documentID: document.id)
                            .frame(width: editorWidth, height: panelHeight)
                            .opacity(expanded ? 1 : 0)
                            .allowsHitTesting(expanded).accessibilityHidden(!expanded)
                        if !expanded {
                            Button { store.restoreFile(document.id) } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: "doc.text").font(.system(size: 16))
                                    Text(document.url.pathExtension.isEmpty ? "FILE" : String(document.url.pathExtension.uppercased().prefix(5))).font(.system(size: 7, weight: .semibold))
                                }.frame(width: itemSize, height: itemSize)
                                    .contentShape(RoundedRectangle(cornerRadius: collapsedDock ? 8 : Palette.cornerRadius))
                                    .background(document.dirty ? Color.red.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: collapsedDock ? 8 : Palette.cornerRadius))
                                    .overlay(RoundedRectangle(cornerRadius: collapsedDock ? 8 : Palette.cornerRadius).strokeBorder(document.dirty ? Color.red.opacity(0.5) : .clear, lineWidth: 1).allowsHitTesting(false))
                            }.buttonStyle(.plain).pointerStyle(.default).focusEffectDisabled().foregroundStyle(Palette.icon)
                                .help(document.url.lastPathComponent + (document.dirty ? " · Unsaved changes" : ""))
                                .accessibilityLabel("Restore " + document.url.lastPathComponent)
                                .contextMenu { Button("Close file") { store.closeFile(document.id) } }
                        }
                    }
                    .modifier(PanelShell(rect: CGRect(x: expanded ? editorX : dockX,
                        y: expanded ? inset : inset + dockHeader + CGFloat(index - filePage) * itemStride,
                        width: width, height: height), radius: !expanded && collapsedDock ? 8 : Palette.cornerRadius,
                        tinted: true, closeLabel: "Close " + document.url.lastPathComponent,
                        close: expanded ? nil : { store.closeFile(document.id) }))
                    .opacity(visible && !store.showTerminal && !store.showBrowser ? 1 : 0).allowsHitTesting(visible && !store.showTerminal && !store.showBrowser).accessibilityHidden(!visible || store.showTerminal || store.showBrowser)
                    .zIndex(expanded ? 2 : 4)
                    .onAppear {
                        DispatchQueue.main.async { withAnimation(motion) { _ = presentedPanels.insert(document.id) } }
                    }
                    .onDisappear { presentedPanels.remove(document.id) }
                    .transition(.opacity)
                }
                if dockedFiles.count > slots {
                    HStack(spacing: 0) {
                        DockIconButton(icon: "chevron.up", help: "Previous docked files", width: collapsedDock ? itemSize / 2 : 24, height: 28, radius: collapsedDock ? 8 : Palette.cornerRadius) { filePage = max(0, filePage - slots) }.disabled(filePage == 0)
                        DockIconButton(icon: "chevron.down", help: "Next docked files", width: collapsedDock ? itemSize / 2 : 24, height: 28, radius: collapsedDock ? 8 : Palette.cornerRadius) { filePage = min(max(0, dockedFiles.count - slots), filePage + slots) }.disabled(filePage + slots >= dockedFiles.count)
                    }.floatingGlass(enabled: !collapsedDock, tinted: true).offset(x: collapsedDock ? dockX : dockX - 3, y: collapsedDock ? inset + dockHeight - 36 : panelHeight - 24)
                        .opacity((store.showTerminal || store.showBrowser) ? 0 : 1).allowsHitTesting(!store.showTerminal && !store.showBrowser).accessibilityHidden(store.showTerminal || store.showBrowser).zIndex(5)
                }

                ForEach(Array(store.projectSessions.enumerated()), id: \.element.id) { index, session in
                    let expanded = store.showTerminal && store.selectedTerminal == session.id && presentedPanels.contains(session.id)
                    let tabWidth = min(146.0, max(90.0, (size.width - 132) / CGFloat(max(1, store.projectSessions.count)) - 8))
                    ZStack(alignment: .topLeading) {
                        TerminalPanel(session: session)
                            .frame(width: terminalBounds.width, height: terminalBounds.height)
                            .opacity(expanded ? 1 : 0)
                            .allowsHitTesting(expanded).accessibilityHidden(!expanded)
                        if !expanded {
                            Button {
                                session.activity.acknowledge()
                                store.selectedTerminal = session.id; store.showTerminal = true
                            } label: {
                                TerminalTabLabel(session: session).padding(.horizontal, 12)
                                    .frame(width: tabWidth, height: dockButtonSize)
                                    .contentShape(RoundedRectangle(cornerRadius: Palette.cornerRadius))
                            }.buttonStyle(.plain).pointerStyle(.default).focusEffectDisabled()
                                .help("Restore " + session.title)
                        }
                    }
                    .modifier(PanelShell(rect: expanded ? terminalBounds : CGRect(
                        x: inset + 46 + CGFloat(index) * (tabWidth + 8), y: size.height - 48,
                        width: tabWidth, height: dockButtonSize), tinted: true,
                        closeLabel: "Close " + session.title, close: expanded ? nil : { store.closeTerminal(session) }))
                    .contextMenu { Button("Rename terminal…") { session.rename() } }
                    .onAppear {
                        session.isPresented = expanded
                        DispatchQueue.main.async { withAnimation(motion) { _ = presentedPanels.insert(session.id) } }
                    }
                    .onDisappear { session.isPresented = false; presentedPanels.remove(session.id) }
                    .onChange(of: expanded) { _, value in session.isPresented = value }
                    .zIndex(expanded ? 10 : 6)
                    .transition(.opacity)
                }
                if let browser = store.browser {
                    ZStack(alignment: .topLeading) {
                        BrowserPanel(session: browser).id(browser.id).frame(width: size.width - 28, height: panelHeight)
                            .opacity(store.showBrowser ? 1 : 0).allowsHitTesting(store.showBrowser).accessibilityHidden(!store.showBrowser)
                        if !store.showBrowser {
                            DockIconButton(icon: "globe", help: "Open browser", width: dockButtonSize, height: dockButtonSize) { store.openBrowser() }
                        }
                    }.modifier(PanelShell(rect: store.showBrowser
                        ? CGRect(x: inset, y: inset, width: size.width - 28, height: panelHeight)
                        : CGRect(x: size.width - inset - dockButtonSize, y: size.height - 48,
                                 width: dockButtonSize, height: dockButtonSize)))
                        .zIndex(store.showBrowser ? 12 : 7)
                }
                DockIconButton(icon: "plus", help: "New terminal", width: dockButtonSize, height: dockButtonSize) { store.addTerminal() }
                    .frame(width: dockButtonSize, height: dockButtonSize).floatingGlass()
                    .offset(x: inset, y: size.height - 48)
                    .disabled(store.project == nil).zIndex(11)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .animation(motion, value: store.showEditor)
            .animation(motion, value: store.showTerminal)
            .animation(motion, value: store.terminalPlacement)
            .animation(motion, value: store.showBrowser)
            .animation(motion, value: store.selectedTerminal)
            .animation(motion, value: store.projectDocuments.map { "\($0.id)-\($0.minimized)" })
            .animation(motion, value: store.projectSessions.map(\.id))
            .animation(motion, value: filePage)
            .onChange(of: store.workspace.selectedProject) { _, _ in filePage = 0 }
            .onChange(of: dockedFiles.count) { _, count in filePage = min(filePage, max(0, count - slots)) }
        }
    }
}
struct TerminalPanel: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var session: TerminalSession
    @State private var snapPreview: TerminalPlacement?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                HStack(spacing: 9) {
                    Image(systemName: "terminal").foregroundStyle(Palette.icon)
                    Text(session.title).font(.system(size: 12, weight: .medium))
                        .onTapGesture(count: 2) { session.rename() }
                    TerminalActivityDot(activity: session.activity)
                    Spacer(minLength: 0)
                    if let snapPreview {
                        Text(snapPreview == .bottom ? "Bottom half" : snapPreview == .right ? "Right half" : "Full workspace")
                            .font(.system(size: 10)).foregroundStyle(Palette.icon)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 48).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in
                        snapPreview = TerminalPlacement.destination(for: value.translation, current: store.terminalPlacement)
                    }
                    .onEnded { value in
                        store.terminalPlacement = TerminalPlacement.destination(for: value.translation, current: store.terminalPlacement)
                        snapPreview = nil
                    })
                .help("Drag down for bottom half, right for right half, or up/left to expand")
                Menu {
                    Button("Full workspace") { store.terminalPlacement = .full }
                    Button("Bottom half") { store.terminalPlacement = .bottom }
                    Button("Right half") { store.terminalPlacement = .right }
                } label: {
                    Image(systemName: "rectangle.split.2x2").foregroundStyle(Palette.icon).frame(width: 24, height: 28)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Terminal layout")
                IconButton(icon: "plus", help: "New terminal", action: store.addTerminal)
                IconButton(icon: "minus", help: "Minimize terminal") { store.showTerminal = false }
                IconButton(icon: "xmark", help: "Close terminal") { store.closeTerminal(session) }
            }.padding(.horizontal, 16)
            TerminalHost(session: session, isActive: store.showTerminal && store.selectedTerminal == session.id)
                .padding(.horizontal, 16).padding(.bottom, 14)

        }
    }
}

private struct TerminalTabLabel: View {
    @ObservedObject var session: TerminalSession
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "terminal").foregroundStyle(Palette.icon)
            TerminalActivityDot(activity: session.activity)
            Text(session.title).lineLimit(1).font(.system(size: 10, weight: .medium))
        }
    }
}
private struct TerminalActivityDot: View {
    let activity: TerminalActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if activity.running || activity.completed {
                Circle().fill(.green).frame(width: 6, height: 6)
                    .overlay {
                        if activity.completed && !reduceMotion {
                            Circle().stroke(.green.opacity(0.7), lineWidth: 1)
                                .phaseAnimator([false, true]) { ring, expanded in
                                    ring.scaleEffect(expanded ? 2.8 : 1).opacity(expanded ? 0 : 1)
                                } animation: { _ in .easeOut(duration: 1.1) }
                        }
                    }
                    .accessibilityLabel(activity.running ? "Command running" : "Command finished")
                    .transition(.scale.combined(with: .opacity))
            }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: activity)
    }
}
