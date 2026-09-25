import AppKit
import SwiftUI
import XCTest
@testable import Clara

final class EditorPerformanceTests: XCTestCase {
    @MainActor func testLocalHighlightMatchesFullHighlightAfterUnicodeEdit() {
        let initial = "let café = 42\n// comment\nlet message = \"hello\"\n"
        let coordinator = CodeEditor.Coordinator(CodeEditor(text: .constant(initial)))
        let view = NSTextView()
        view.isRichText = false
        view.string = initial
        coordinator.highlight(view)
        let range = (initial as NSString).range(of: "42")
        view.textStorage?.replaceCharacters(in: range, with: "108")
        coordinator.highlight(view, editedRange: NSRange(location: range.location, length: 3))
        let full = NSTextView()
        full.string = view.string
        coordinator.highlight(full)
        for index in 0..<(view.string as NSString).length {
            XCTAssertEqual(view.textStorage?.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor,
                           full.textStorage?.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor)
        }
    }
    @MainActor func testTypingDoesNotRepaintUnchangedLines() {
        let text = "let value = 1\nlet untouched = 2\n"
        let coordinator = CodeEditor.Coordinator(CodeEditor(text: .constant(text)))
        let view = NSTextView()
        view.string = text
        coordinator.highlight(view)
        let untouched = (text as NSString).range(of: "untouched")
        view.textStorage?.addAttribute(.foregroundColor, value: NSColor.magenta, range: untouched)
        coordinator.highlight(view, editedRange: NSRange(location: 0, length: 3))
        XCTAssertEqual(view.textStorage?.attribute(.foregroundColor, at: untouched.location, effectiveRange: nil) as? NSColor, .magenta)
        XCTAssertEqual(view.string, text)
    }
    @MainActor func testJoinedLinesAreRecoloredAfterDeletion() {
        let view = NSTextView()
        view.string = "// comment\nlet value = 1\n"
        let coordinator = CodeEditor.Coordinator(CodeEditor(text: .constant(view.string)))
        coordinator.highlight(view)
        let newline = (view.string as NSString).range(of: "\n")
        view.textStorage?.replaceCharacters(in: newline, with: "")
        coordinator.highlight(view, editedRange: NSRange(location: newline.location, length: 0))
        let full = NSTextView(); full.string = view.string
        coordinator.highlight(full)
        let keyword = (view.string as NSString).range(of: "let")
        XCTAssertEqual(view.textStorage?.attribute(.foregroundColor, at: keyword.location, effectiveRange: nil) as? NSColor,
                       full.textStorage?.attribute(.foregroundColor, at: keyword.location, effectiveRange: nil) as? NSColor)
    }
}
