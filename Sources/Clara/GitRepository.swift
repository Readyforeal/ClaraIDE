import Foundation

/// Read-only Git queries also handle linked worktrees and folders inside repositories.
enum GitRepository {
    static func branch(at path: String) -> String? {
        if let name = output(["symbolic-ref", "--quiet", "--short", "HEAD"], at: path) { return name }
        if let commit = output(["rev-parse", "--short", "HEAD"], at: path) { return "Detached · " + commit }
        return nil
    }
    private static func output(_ arguments: [String], at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "-C", path] + arguments
        var environment = ProcessInfo.processInfo.environment
        // Resolve this project's repository, never an inherited terminal Git context.
        for key in environment.keys where key.hasPrefix("GIT_") { environment.removeValue(forKey: key) }
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
