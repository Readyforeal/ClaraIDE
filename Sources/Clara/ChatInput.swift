import AppKit
import SwiftUI

/// A real multiline editor, with Return handled before AppKit's field-editor commands.
struct ChatInput: View {
    @Binding var text: String
    var enabled: Bool
    var submit: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Ask anything, or describe what you'd like to build…")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.top, 2).allowsHitTesting(false)
            }
            ComposerEditor(text: $text, enabled: enabled, submit: submit)
                .frame(minHeight: 54)
        }
    }
}

struct ComposerEditor: NSViewRepresentable {
    @Binding var text: String
    var enabled: Bool
    var submit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let view = ComposerTextView(frame: .zero)
        view.isRichText = false
        view.drawsBackground = false
        view.focusRingType = .none
        view.font = .systemFont(ofSize: 13)
        view.textColor = NSColor(calibratedWhite: 0.87, alpha: 1)
        view.insertionPointColor = .controlAccentColor
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.allowsUndo = true
        view.delegate = context.coordinator
        view.string = text
        view.setAccessibilityLabel("Chat message")
        scroll.documentView = view
        updateNSView(scroll, context: context)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? ComposerTextView else { return }
        view.isEditable = enabled
        view.isSelectable = enabled
        view.submit = submit
        if view.string != text {
            view.string = text
            view.undoManager?.removeAllActions()
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0,
              let view = scroll.documentView as? NSTextView,
              let container = view.textContainer, let manager = view.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return CGSize(width: width, height: min(136, max(54, manager.usedRect(for: container).height + 8)))
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerEditor
        init(_ parent: ComposerEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

final class ComposerTextView: NSTextView {
    var submit: ((String) -> Void)?
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText(), isEditable {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.shift) || flags.contains(.option) {
                insertText("\n", replacementRange: selectedRange())
            } else if !flags.contains(.control) {
                submit?(string)
            } else {
                super.keyDown(with: event)
            }
            return
        }
        super.keyDown(with: event)
    }
}
