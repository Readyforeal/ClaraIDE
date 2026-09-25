import SwiftUI
import AppKit
import SwiftTerm

struct TerminalHost: NSViewRepresentable {
    let session: TerminalSession
    var isActive: Bool
    final class Coordinator { var wasActive = false }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> LocalProcessTerminalView { session.view }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        nsView.isHidden = !isActive
        if context.coordinator.wasActive != isActive { nsView.window?.invalidateCursorRects(for: nsView) }
        if isActive && !context.coordinator.wasActive {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        } else if !isActive && context.coordinator.wasActive && nsView.window?.firstResponder === nsView {
            nsView.window?.makeFirstResponder(nil)
        }
        context.coordinator.wasActive = isActive
    }
}
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var editable = true
    var isActive = true
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        let view = NSTextView(frame: .zero)
        view.focusRingType = .none; scroll.focusRingType = .none
        view.isRichText = false; view.isEditable = editable; view.isSelectable = true; view.allowsUndo = true
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textColor = NSColor(calibratedWhite: 0.85, alpha: 1)
        view.backgroundColor = NSColor(calibratedWhite: 0.045, alpha: 1)
        view.insertionPointColor = NSColor.systemBlue
        view.textContainerInset = NSSize(width: 16, height: 16)
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isVerticallyResizable = true; view.isHorizontallyResizable = true
        view.minSize = NSSize(width: 0, height: 0); view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.autoresizingMask = [.width]
        view.string = text; view.delegate = context.coordinator
        scroll.documentView = view; scroll.isHidden = !isActive; context.coordinator.highlight(view)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if scroll.isHidden == isActive {
            scroll.isHidden = !isActive
            if let document = scroll.documentView { scroll.window?.invalidateCursorRects(for: document) }
        }
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text; view.undoManager?.removeAllActions(); context.coordinator.highlight(view) }
        view.isEditable = editable
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string; highlight(view)
        }
        func highlight(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            // Keep highlighting lightweight for larger files.
            let text = view.string as NSString
            let range = NSRange(location: 0, length: text.length)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor(calibratedWhite: 0.85, alpha: 1), range: range)
            if text.length < 120_000 {
                let rules: [(String, NSColor)] = [
                    (#"\b(import|struct|class|enum|func|let|var|if|else|return|guard|async|await|throw|throws|try|private|public|static|const|function|def|for|in|while|export|from|true|false|nil|null)\b"#, .init(calibratedRed: 0.71, green: 0.61, blue: 0.87, alpha: 1)),
                    (#"\b[0-9]+(\.[0-9]+)?\b"#, .init(calibratedRed: 0.85, green: 0.70, blue: 0.48, alpha: 1)),
                    (#"\"(?:[^\"\\]|\\.)*\""#, .init(calibratedRed: 0.66, green: 0.78, blue: 0.58, alpha: 1)),
                    (#"(?m)//.*$|^\s*# .*$"#, .init(calibratedWhite: 0.43, alpha: 1))
                ]
                for (pattern, color) in rules {
                    if let expression = try? NSRegularExpression(pattern: pattern) {
                        for match in expression.matches(in: view.string, range: range) { storage.addAttribute(.foregroundColor, value: color, range: match.range) }
                    }
                }
            }
            storage.endEditing()
        }
    }
}
struct FileNavigator: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "folder").foregroundStyle(Palette.icon)
                Text("Files").font(.system(size: 12, weight: .semibold))
                Spacer()
                IconButton(icon: "minus", help: "Minimize file navigator") { store.showEditor = false }
            }.padding(.horizontal, 16).frame(height: 48)
            HStack {
                if store.directory?.path != store.project?.path {
                    IconButton(icon: "arrow.up", help: "Parent folder") { if let directory = store.directory { store.reloadFiles(directory.deletingLastPathComponent()) } }
                }
                Text(store.directory?.lastPathComponent ?? "Files").font(.system(size: 10, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                IconButton(icon: "arrow.clockwise", help: "Refresh files") { store.reloadFiles() }
            }.foregroundStyle(Palette.muted).padding(.horizontal, 12).padding(.bottom, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(store.entries) { entry in
                        Button { store.openFile(entry) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: entry.isDirectory ? "folder" : "doc.text").foregroundStyle(Palette.icon).frame(width: 16)
                                Text(entry.url.lastPathComponent).lineLimit(1)
                                Spacer(minLength: 0)
                                if entry.isDirectory { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Palette.muted) }
                            }.font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 10).contentShape(Rectangle())
                                .background(entry.url == store.fileURL ? Color.white.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 8)
            }
            Text("\(store.entries.count) items").font(.system(size: 9)).foregroundStyle(Palette.muted).padding(16)
        }
    }
}
struct FileEditorPanel: View {
    @EnvironmentObject var store: AppStore
    let documentID: UUID
    var document: EditorDocument? { store.documents.first { $0.id == documentID } }
    var body: some View {
        if let doc = document {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").foregroundStyle(Palette.icon)
                    Text(doc.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if doc.dirty {
                        HStack(spacing: 5) {
                            Circle().fill(.red).frame(width: 5, height: 5)
                            Text("Unsaved changes").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }
                    }
                    Spacer()
                    Button("Add to chat") { store.selectedFileID = doc.id; store.attachedFile = doc.text; store.minimizeFile(doc.id); store.showEditor = false }.font(.system(size: 10)).buttonStyle(.plain)
                    Button("Save") { store.saveDocument(doc.id) }.font(.system(size: 10)).buttonStyle(.plain).disabled(!doc.dirty)
                    IconButton(icon: "minus", help: "Minimize \(doc.url.lastPathComponent)") { store.minimizeFile(doc.id) }
                    IconButton(icon: "xmark", help: "Close \(doc.url.lastPathComponent)") { store.closeFile(doc.id) }
                }.padding(.horizontal, 16).frame(height: 48)
                CodeEditor(text: Binding(get: { document?.text ?? "" }, set: { text in
                    if let i = store.documents.firstIndex(where: { $0.id == documentID }) { store.documents[i].text = text }
                }), isActive: !doc.minimized && !store.showTerminal && !store.showBrowser).clipShape(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)).padding(.horizontal, 8)
                HStack {
                    Text("\(doc.text.components(separatedBy: "\n").count) lines")
                    Spacer(); Text("UTF-8"); Text(doc.url.pathExtension.uppercased())
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted).padding(.horizontal, 18).frame(height: 32)
            }
        }
    }
}
struct EditReview: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let edit: ProposedEdit
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { VStack(alignment: .leading, spacing: 5) { Text("Review proposed change").font(.system(size: 20, weight: .medium)); Text(edit.path).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted) }; Spacer(); Button("Close") { dismiss() } }
            HStack(spacing: 12) {
                VStack(alignment: .leading) { Text("CURRENT").font(.system(size: 10)).foregroundStyle(Palette.muted); CodeEditor(text: .constant(edit.original ?? "(new file)"), editable: false) }
                VStack(alignment: .leading) { Text("PROPOSED").font(.system(size: 10)).foregroundStyle(Palette.accent); CodeEditor(text: .constant(edit.content), editable: false) }
            }
            HStack {
                Text("Apply writes this file to your project folder.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Reject") { store.proposedEdits.removeAll { $0.id == edit.id }; dismiss() }
                Button("Apply change") { store.apply(edit); dismiss() }.buttonStyle(.borderedProminent).tint(Palette.accentStrong).foregroundStyle(.white)
            }
        }.padding(24).frame(width: 1000, height: 650).background(Palette.background).tint(Palette.accent).focusEffectDisabled()
    }
}
