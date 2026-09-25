import AppKit
import XCTest
@testable import Clara

final class TerminalLayoutTests: XCTestCase {
    func testDirectionalSnappingAndSmallDrags() {
        XCTAssertEqual(TerminalPlacement.destination(for: CGSize(width: 4, height: 30), current: .full), .full)
        XCTAssertEqual(TerminalPlacement.destination(for: CGSize(width: 15, height: 80), current: .full), .bottom)
        XCTAssertEqual(TerminalPlacement.destination(for: CGSize(width: 80, height: 15), current: .bottom), .right)
        XCTAssertEqual(TerminalPlacement.destination(for: CGSize(width: -80, height: 5), current: .right), .full)
        XCTAssertEqual(TerminalPlacement.destination(for: CGSize(width: 0, height: -80), current: .bottom), .full)
    }
    func testSplitChatAndTerminalStayInsideViewportWithoutOverlap() {
        for width in [CGFloat(656), 1000, 1800] {
            for height in [CGFloat(500), 750, 1100] {
                let size = CGSize(width: width, height: height)
                for placement in [TerminalPlacement.bottom, .right] {
                    let layout = TerminalLayout(size: size, placement: placement)
                    XCTAssertFalse(layout.chat.intersects(layout.terminal))
                    XCTAssertEqual(layout.terminal.maxY, height - WorkspaceLayout.bottomClearance)
                    XCTAssertEqual(layout.terminal.maxX, width - WorkspaceLayout.panelInset)
                    XCTAssertGreaterThan(layout.terminal.width, 0)
                    XCTAssertGreaterThan(layout.terminal.height, 0)
                    if placement == .bottom {
                        XCTAssertEqual(layout.terminal.minY - layout.chat.maxY, WorkspaceLayout.panelGap)
                    } else {
                        XCTAssertEqual(layout.terminal.minX - layout.chat.maxX, WorkspaceLayout.panelGap)
                    }
                }
            }
        }
    }
    @MainActor func testReturnSendsCurrentTextAndShiftReturnInsertsNewline() throws {
        _ = NSApplication.shared
        let view = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        view.isRichText = false
        view.isEditable = true
        var submissions: [String] = []
        view.submit = { submissions.append($0) }
        func key(_ flags: NSEvent.ModifierFlags, code: UInt16 = 36) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: code))
        }
        view.string = "First line"
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        view.keyDown(with: try key(.shift))
        XCTAssertEqual(view.string, "First line\n")
        XCTAssertTrue(submissions.isEmpty)
        view.insertText("Second line", replacementRange: view.selectedRange())
        view.keyDown(with: try key([]))
        XCTAssertEqual(submissions, ["First line\nSecond line"])
        view.keyDown(with: try key(.command))
        XCTAssertEqual(submissions.count, 2)
        view.keyDown(with: try key([], code: 76))
        XCTAssertEqual(submissions.count, 3)
    }
}
