import SwiftUI
import AppKit

@main struct ClaraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = AppStore()
    @StateObject private var updates = UpdateChecker()
    var body: some Scene {
        Window("Clara", id: "workspace") {
            WorkspaceView().environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Palette.accent)
                .focusEffectDisabled()
                .containerBackground(.clear, for: .window)
                .background(WindowChrome())
                .ignoresSafeArea(.container, edges: .top)
                .frame(minWidth: 1100, minHeight: 660)
                .onAppear { delegate.store = store; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1380, height: 880)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(updates.checking ? "Checking for Updates…" : "Check for Updates…") {
                    Task { await updates.check() }
                }.disabled(updates.checking)
                Divider()
            }
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") { store.newChat() }.keyboardShortcut("n")
                Button("Open Project…") { store.addProject() }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) { Button("Settings…") { store.showSettings = true }.keyboardShortcut(",") }
            CommandGroup(replacing: .saveItem) { Button("Save File") { store.saveFile() }.keyboardShortcut("s").disabled(store.fileURL == nil) }
            CommandMenu("Workspace") {
                Button("Open Browser") { store.openBrowser() }.keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Undo Delete Conversation") { store.undoDeleteChat() }.disabled(store.deletedChat == nil)
                Button("Toggle Project Sidebar") { store.toggleSidebar() }.keyboardShortcut("s", modifiers: [.command, .control])
                Button("Toggle Files & Editor") { store.showEditor.toggle() }.keyboardShortcut("e", modifiers: [.command, .shift])
                Button("New Terminal") { store.addTerminal() }.keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Toggle Terminal") {
                    if store.projectSessions.isEmpty { store.addTerminal() } else { store.showTerminal.toggle() }
                }.keyboardShortcut("`")
            }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    var store: AppStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Also set the running Dock icon when launching a local unsigned/development bundle.
        // Native layered builds let macOS resolve their asset-catalog icon instead.
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") == nil,
           let url = Bundle.main.url(forResource: "Clara", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        NotificationCenter.default.addObserver(self, selector: #selector(suppressFocusRings(_:)), name: NSWindow.didUpdateNotification, object: nil)
    }
    @objc private func suppressFocusRings(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        func suppress(_ view: NSView) {
            if view.focusRingType != .none { view.focusRingType = .none }
            view.subviews.forEach(suppress)
        }
        if let content = window.contentView { suppress(content) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store?.confirmDiscard() != false else { return .terminateCancel }
        store?.persist(); store?.sessions.forEach { $0.stop() }; return .terminateNow
    }
}
enum Palette {
    static let cornerRadius: CGFloat = 14
    static let icon = Color(white: 0.72)
    static let background = Color(red: 0.035, green: 0.038, blue: 0.043)
    static let sidebar = Color(red: 0.052, green: 0.056, blue: 0.063)
    static let panel = Color(red: 0.075, green: 0.08, blue: 0.09)
    static let line = Color.white.opacity(0.075)
    static let muted = Color(red: 0.48, green: 0.50, blue: 0.55)
    // Classic macOS blue, with adaptive system appearance.
    static let accent = Color(nsColor: .systemBlue)
    static let accentStrong = Color(nsColor: .systemBlue)
}
struct IconButton: View {
    let icon: String
    let help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 13)).frame(width: 28, height: 28).contentShape(Rectangle()) }
            .buttonStyle(DockButtonStyle()).focusEffectDisabled().foregroundStyle(Palette.muted).help(help).accessibilityLabel(help)
    }
}
