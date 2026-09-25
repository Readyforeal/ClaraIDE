import AppKit
import Darwin
import Foundation

/// Opt-in, synthetic UI benchmark. Never opens the user's workspace or sends API requests.
@MainActor final class PerformanceRun {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["CLARA_PROFILE_DIRECTORY"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
    static var stateURL: URL? { directory?.appendingPathComponent("workspace.json") }
    static let shared = PerformanceRun()
    private var started = false
    private var intervals: [Double] = []
    private var previous = 0.0
    private var timer: Timer?
    private var results: [[String: Any]] = []

    func start(_ store: AppStore) {
        guard !started, let directory = Self.directory else { return }
        started = true
        Task { await run(store, directory: directory) }
    }
    private func cpu() -> Double {
        var value = rusage(); getrusage(RUSAGE_SELF, &value)
        return Double(value.ru_utime.tv_sec + value.ru_stime.tv_sec)
            + Double(value.ru_utime.tv_usec + value.ru_stime.tv_usec) / 1_000_000
    }
    private func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }
    private func phase(_ name: String, steps: Int = 60, action: (Int) -> Void = { _ in }) async {
        intervals = []; previous = ProcessInfo.processInfo.systemUptime
        let begin = previous; let cpuBegin = cpu()
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                self.intervals.append((now - self.previous) * 1000)
                self.previous = now
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
        for step in 0..<steps {
            action(step)
            try? await Task.sleep(for: .milliseconds(100))
        }
        timer?.invalidate(); timer = nil
        let elapsed = ProcessInfo.processInfo.systemUptime - begin
        let sorted = intervals.sorted()
        func percentile(_ p: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))] }
        results.append(["phase": name, "elapsed_s": elapsed, "cpu_s": cpu() - cpuBegin,
            "main_tick_p95_ms": percentile(0.95), "main_tick_max_ms": sorted.last ?? 0,
            "ticks_over_33ms": intervals.filter { $0 > 33.34 }.count,
            "tick_count": intervals.count, "resident_mb": residentMB(),
            "thermal_state": ProcessInfo.processInfo.thermalState.rawValue])
    }
    private func allViews(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(allViews) }
    private func run(_ store: AppStore, directory: URL) async {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("Example.swift")
            try String(repeating: "func example(value: Int) -> String { return \"hello\" } // fixture\n", count: 900)
                .write(to: file, atomically: true, encoding: .utf8)
            var project = Project(name: "Performance fixture", path: directory.path)
            project.chats[0].messages = (0..<100).map { index in
                Message(role: index % 2 == 0 ? "user" : "assistant",
                    content: "Message \(index)\n" + String(repeating: "A synthetic **markdown** response with `code` and a paragraph of text.\n", count: 8))
            }
            store.workspace = Workspace()
            store.workspace.projects = [project]
            store.workspace.selectedProject = project.id
            store.workspace.selectedChat = project.chats[0].id
            store.reloadFiles()
            for _ in 0..<3 { store.addTerminal() }
            store.showTerminal = false
            NSApp.windows.first?.setContentSize(NSSize(width: 1380, height: 880))
            try? await Task.sleep(for: .seconds(3))
            await phase("idle_three_terminals")
            await phase("panel_cycle") { step in
                if step % 6 == 0 { store.showTerminal.toggle() }
                if step % 18 == 6 { store.terminalPlacement = .right }
                if step % 18 == 12 { store.terminalPlacement = .bottom }
                if step % 18 == 0 { store.terminalPlacement = .full }
            }
            store.showTerminal = true; store.terminalPlacement = .full
            await phase("terminal_output") { step in
                store.projectSessions.last?.view.feed(text: String(repeating: "profile output \(step): compile fixture 0123456789\r\n", count: 30))
            }
            store.showTerminal = false
            store.openFile(FileEntry(url: file, isDirectory: false))
            try? await Task.sleep(for: .seconds(1))
            await phase("editor_typing") { _ in
                if let root = NSApp.windows.first?.contentView,
                   let editor = self.allViews(root).compactMap({ $0 as? NSTextView }).first(where: { !($0 is ComposerTextView) && $0.isEditable && !$0.isHidden }) {
                    editor.insertText("// typed fixture\n", replacementRange: NSRange(location: 0, length: 0))
                }
            }
            for index in store.documents.indices { store.documents[index].saved = store.documents[index].text }
            if let id = store.expandedDocument?.id { store.minimizeFile(id) }
            let chatID = project.chats[0].id
            await phase("streamed_markdown") { step in
                store.updateChat(chatID) { chat in chat.messages[chat.messages.count - 1].content += "\nStreamed **chunk \(step)** with `code`." }
            }
            await phase("chat_scroll") { step in
                guard let root = NSApp.windows.first?.contentView else { return }
                let scrolls = self.allViews(root).compactMap { $0 as? NSScrollView }.filter {
                    !($0.documentView is NSTextView) && ($0.documentView?.bounds.height ?? 0) > $0.bounds.height * 2
                }
                guard let scroll = scrolls.max(by: { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }) else { return }
                let height = max(0, (scroll.documentView?.bounds.height ?? 0) - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: height * CGFloat(step % 20) / 19))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            await phase("idle_after_work")
            let report: [String: Any] = ["metrics": results, "note": "Main-thread timer intervals measure responsiveness, NOT displayed FPS or GPU time."]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent("metrics.json"))
        } catch {
            try? error.localizedDescription.write(to: directory.appendingPathComponent("error.txt"), atomically: true, encoding: .utf8)
        }
        store.sessions.forEach { $0.stop() }
        NSApp.terminate(nil)
    }
}
