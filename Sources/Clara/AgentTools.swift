import Foundation
import Darwin

/// Bounded, paginated model access; independent of the editor's size limit.
enum AgentFiles {
    static func text(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) <= 20_000_000 else {
            throw AppError.message("Not a regular text file, or larger than 20 MB. Use run_command for targeted inspection.")
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 20_000_000, !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw AppError.message("Not UTF-8 text.")
        }
        return text
    }
    static func read(path: String, root: String, start: Int = 1, count: Int = 200) throws -> String {
        let lines = try text(ProjectFiles.resolve(path, root: root)).components(separatedBy: "\n")
        let first = max(1, start)
        guard first <= lines.count else { return "EOF: \(lines.count) total lines." }
        let last = min(lines.count, first + min(400, max(1, count)) - 1)
        var output = "File: \(path), total lines: \(lines.count)\n", next = first
        for n in first...last {
            let line = lines[n - 1]
            let rendered = "\(n): \(line.prefix(2000))\(line.count > 2000 ? " [long line clipped; use run_command to inspect this line]" : "")\n"
            if output.utf8.count + rendered.utf8.count > 24_000 { break }
            output += rendered; next = n + 1
        }
        return output + (next <= lines.count ? "\nMore content: call read_file with start_line=\(next)." : "\nEOF")
    }
    static func list(path: String, root: String, offset: Int = 0) throws -> String {
        let entries = try ProjectFiles.entries(at: ProjectFiles.resolve(path, root: root))
        let start = min(entries.count, max(0, offset)), end = min(entries.count, start + 200)
        let rows = entries[start..<end].map { ($0.isDirectory ? "directory " : "file ") + $0.url.lastPathComponent }
        return rows.joined(separator: "\n") + "\n\(end)/\(entries.count) entries." + (end < entries.count ? " Continue with offset=\(end)." : "")
    }
    static func search(path: String, root: String, query: String, offset: Int = 0) throws -> String {
        guard !query.isEmpty else { throw AppError.message("Search query must not be empty.") }
        let canonicalRoot = try ProjectFiles.resolve(".", root: root)
        let base = try ProjectFiles.resolve(path, root: root)
        guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { throw AppError.message("Cannot search this directory.") }
        var hits: [String] = [], examined = 0, matched = 0, skipped = 0, limited = false
        let excluded: Set<String> = [".git", "node_modules", ".build", "build", "dist", "vendor"]
        for case let url as URL in files {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { files.skipDescendants(); continue }
            if values.isDirectory == true {
                if excluded.contains(url.lastPathComponent) { files.skipDescendants() }
                continue
            }
            examined += 1
            if examined > 5000 { limited = true; break }
            let normalized = url.resolvingSymlinksInPath().standardizedFileURL
            let rootPrefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
            guard normalized.path.hasPrefix(rootPrefix) else { skipped += 1; continue }
            let relative = String(normalized.path.dropFirst(rootPrefix.count))
            guard let content = try? text(ProjectFiles.resolve(relative, root: root)) else { skipped += 1; continue }
            for (index, line) in content.components(separatedBy: "\n").enumerated() where line.localizedCaseInsensitiveContains(query) || (index == 0 && relative.localizedCaseInsensitiveContains(query)) {
                matched += 1
                if matched <= max(0, offset) { continue }
                hits.append("\(relative):\(index + 1): \(line.prefix(300))")
                if hits.count == 80 { break }
            }
            if hits.count == 80 { break }
        }
        return hits.joined(separator: "\n") + "\nSearched \(min(examined, 5000)) files; skipped \(skipped) non-text/oversized files and generated/dependency directories."
            + (hits.count == 80 ? " More matches may exist; use offset=\(matched)." : "")
            + (limited ? " Search scan limit reached; narrow path or use run_command." : "")
    }
}

struct CommandResult {
    let output: String
    let status: Int32
    let timedOut: Bool
}

enum AgentCommand {
    private final class Processes: @unchecked Sendable {
        private let lock = NSLock()
        private var active: Set<pid_t> = []
        func add(_ pid: pid_t) { lock.lock(); defer { lock.unlock() }; active.insert(pid) }
        func finish(_ pid: pid_t) {
            lock.lock(); defer { lock.unlock() }
            kill(-pid, SIGKILL); active.remove(pid)
        }
        func stopAll() {
            lock.lock(); defer { lock.unlock() }
            for pid in active { kill(-pid, SIGKILL) }
        }
    }
    private static let processes = Processes()
    static func stopAll() { processes.stopAll() }

    /// A dedicated process group lets Stop/timeout terminate ordinary child processes too.
    static func run(_ command: String, directory: String, timeout: Double = 120) async throws -> CommandResult {
        try Task.checkCancellation()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clara-command-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let outputURL = folder.appendingPathComponent("output")
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_addchdir(&actions, directory)
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, outputURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attributes, 0)
        let args = ["/bin/zsh", "-l", "-c", command].map { strdup($0) }
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"; environment["CLICOLOR"] = "0"
        let env = environment.map { strdup("\($0.key)=\($0.value)") }
        defer { args.forEach { free($0) }; env.forEach { free($0) } }
        var pid: pid_t = 0
        let result = (args + [nil]).withUnsafeBufferPointer { argv in
            (env + [nil]).withUnsafeBufferPointer { envp in
                posix_spawn(&pid, "/bin/zsh", &actions, &attributes, argv.baseAddress!, envp.baseAddress!)
            }
        }
        guard result == 0 else { throw AppError.message("Could not launch command: \(String(cString: strerror(result)))") }
        processes.add(pid)
        var status: Int32 = 0, reaped = false
        defer {
            // Also clean up background children left behind by a finished shell.
            processes.finish(pid)
            if !reaped { while waitpid(pid, &status, 0) == -1 && errno == EINTR {} }
        }
        let deadline = Date().addingTimeInterval(min(300, max(0.1, timeout)))
        var timedOut = false, outputLimited = false
        while true {
            try Task.checkCancellation()
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid { reaped = true; break }
            if waited == -1 && errno != EINTR { throw AppError.message("Could not collect command exit status.") }
            let size = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            timedOut = Date() >= deadline; outputLimited = size > 10_000_000
            if timedOut || outputLimited { break }
            try await Task.sleep(for: .milliseconds(80))
        }
        if !reaped { kill(-pid, SIGKILL); while waitpid(pid, &status, 0) == -1 && errno == EINTR {}; reaped = true }
        let handle = try FileHandle(forReadingFrom: outputURL); defer { try? handle.close() }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let head = try handle.read(upToCount: 16_000) ?? Data()
        var output = String(decoding: head, as: UTF8.self)
        if size > 24_000 {
            try handle.seek(toOffset: size - 8000)
            output += "\n[Output clipped: showing first 16 KB and last 8 KB. Narrow or redirect output for more.]\n" + String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self)
        } else { output += String(decoding: try handle.readToEnd() ?? Data(), as: UTF8.self) }
        if outputLimited { output += "\nCommand stopped after exceeding 10 MB of output." }
        let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        return CommandResult(output: output, status: code, timedOut: timedOut)
    }
}
