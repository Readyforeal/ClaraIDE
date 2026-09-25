import AppKit
import XCTest
@testable import Clara

final class NotchPeekTests: XCTestCase {
    func testNotchGeometryUsesActualHousingAndKeepsExpandedPanelOnScreen() {
        let screen = CGRect(x: -1512, y: 160, width: 1512, height: 982)
        let layout = NotchGeometry(screen: screen,
            left: CGRect(x: -1512, y: 1110, width: 650, height: 32),
            right: CGRect(x: -650, y: 1110, width: 650, height: 32), safeTop: 32)
        XCTAssertEqual(layout.collapsed.minX, -900)
        XCTAssertEqual(layout.collapsed.maxX, -650)
        XCTAssertEqual(layout.collapsed.maxY, screen.maxY)
        XCTAssertEqual(layout.expanded.maxY, screen.maxY)
        XCTAssertTrue(screen.contains(layout.expanded))
        XCTAssertEqual(layout.topInset, 32)
    }
    @MainActor func testPanelCanOccupyMenuBarAndNotchArea() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let panel = PeekPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer { panel.close() }
        panel.isReleasedWhenClosed = false
        let target = CGRect(x: screen.frame.midX - 120, y: screen.frame.maxY - 32, width: 240, height: 32)
        XCTAssertEqual(panel.constrainFrameRect(target, to: screen), target)
        panel.setFrame(target, display: true)
        panel.orderFrontRegardless()
        XCTAssertEqual(panel.frame.maxY, screen.frame.maxY, accuracy: 0.5)
    }
    func testExternalDisplayFallbackIsCenteredAndFitsSmallScreen() {
        let screen = CGRect(x: 1600, y: -400, width: 800, height: 600)
        let layout = NotchGeometry(screen: screen, left: nil, right: nil, safeTop: 0)
        XCTAssertEqual(layout.collapsed.midX, screen.midX)
        XCTAssertEqual(layout.collapsed.width, 38)
        XCTAssertTrue(screen.contains(layout.expanded))
    }
    @MainActor func testTemporaryTerminalsStaySeparateAndSurviveCollapse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = ProcessInfo.processInfo.environment["CLARA_PROFILE_DIRECTORY"]
        setenv("CLARA_PROFILE_DIRECTORY", root.path, 1)
        defer { if let previous { setenv("CLARA_PROFILE_DIRECTORY", previous, 1) } else { unsetenv("CLARA_PROFILE_DIRECTORY") } }
        let store = AppStore(stateURL: root.appendingPathComponent("workspace.json"))
        let first = Project(name: "First", path: root.path), second = Project(name: "Second", path: root.path)
        store.workspace.projects = [first, second]; store.selectProject(first.id)
        let peek = NotchPeekController(store: store)
        defer { peek.shutdown() }
        peek.quickTerminal()
        let original = try XCTUnwrap(peek.terminals[first.id])
        peek.collapse()
        XCTAssertTrue(original.view.process.running)
        store.selectProject(second.id); peek.quickTerminal()
        XCTAssertNotEqual(original.id, peek.terminals[second.id]?.id)
        XCTAssertTrue(original.view.process.running)
        peek.closeTerminal()
        XCTAssertNil(peek.terminals[second.id])
        XCTAssertNotNil(peek.terminals[first.id])
        XCTAssertTrue(store.sessions.isEmpty, "Peek shells must not appear in the main terminal dock")
    }

    @MainActor func testPeekUsesSharedConversationAndCollapsesWithoutChangingIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AppStore(stateURL: root.appendingPathComponent("workspace.json"))
        var project = Project(name: "Peek fixture", path: root.path)
        project.chats[0].messages = [Message(role: "user", content: "Can we fix the browser layout?"), Message(role: "assistant", content: "The project now keeps its own browser session. The change is ready to review.")]
        store.workspace.projects = [project]; store.selectProject(project.id)
        store.draft = "One shared draft"
        let peek = NotchPeekController(store: store)
        peek.start(workspace: nil)
        defer { peek.shutdown() }
        peek.enabled = true
        peek.expand()
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertTrue(peek.expanded)
        XCTAssertFalse(peek.pinned)
        XCTAssertFalse(peek.panel?.isKeyWindow ?? true, "Hover expansion must not take keyboard focus")
        XCTAssertTrue(peek.store === store)
        if let view = peek.panel?.contentView, let output = ProcessInfo.processInfo.environment["CLARA_PEEK_RENDER"] {
            view.layoutSubtreeIfNeeded()
            // Let SwiftUI commit the newly mounted content before capturing its native view.
            try await Task.sleep(for: .milliseconds(250))
            view.displayIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext {
                    view.layer?.render(in: context)
                }
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
            }
        }
        peek.collapse()
        XCTAssertFalse(peek.expanded)
        XCTAssertEqual(store.draft, "One shared draft")
        XCTAssertEqual(store.chat?.id, project.chats[0].id)
    }
}
