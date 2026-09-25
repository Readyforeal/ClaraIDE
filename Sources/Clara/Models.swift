import Foundation

struct Message: Codable, Identifiable {
    var id = UUID()
    var role: String
    var content: String
}
struct Conversation: Codable, Identifiable {
    var id = UUID()
    var title = "New conversation"
    var model = ""
    var messages: [Message] = []
}
struct Project: Codable, Identifiable {
    var id = UUID()
    var name: String
    var path: String
    var chats: [Conversation] = [Conversation()]
}
struct Workspace: Codable {
    var projects: [Project] = []
    var selectedProject: UUID?
    var selectedChat: UUID?
    var defaultModel = ""
    var generalChats: [Conversation] = []
    init() {}
    enum CodingKeys: String, CodingKey { case projects, selectedProject, selectedChat, defaultModel, generalChats }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        selectedProject = try c.decodeIfPresent(UUID.self, forKey: .selectedProject)
        selectedChat = try c.decodeIfPresent(UUID.self, forKey: .selectedChat)
        defaultModel = try c.decodeIfPresent(String.self, forKey: .defaultModel) ?? ""
        generalChats = try c.decodeIfPresent([Conversation].self, forKey: .generalChats) ?? []
    }
}
struct RouterModel: Codable, Identifiable {
    let id: String
    let name: String
}
struct FileEntry: Identifiable {
    var id: String { url.path }
    let url: URL
    let isDirectory: Bool
}

// All model file access resolves symlinks before checking the project boundary.
enum ProjectFiles {
    private static func canonical(_ url: URL, hops: Int = 0) throws -> URL {
        let normalized = url.standardizedFileURL
        guard hops < 40 else { throw AppError.message("Too many symbolic links in this path.") }
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: normalized.path) {
            let target = destination.hasPrefix("/") ? URL(fileURLWithPath: destination) : normalized.deletingLastPathComponent().appendingPathComponent(destination)
            return try canonical(target, hops: hops + 1)
        }
        if FileManager.default.fileExists(atPath: normalized.path) {
            return normalized.resolvingSymlinksInPath()
        }
        let parent = normalized.deletingLastPathComponent()
        guard parent.path != normalized.path else { return normalized }
        return try canonical(parent, hops: hops + 1).appendingPathComponent(normalized.lastPathComponent)
    }
    static func resolve(_ relative: String, root: String) throws -> URL {
        let base = try canonical(URL(fileURLWithPath: root))
        let url = try canonical(base.appendingPathComponent(relative))
        guard url.path == base.path || url.path.hasPrefix(base.path + "/") else {
            throw AppError.message("The requested file is outside this project.")
        }
        return url
    }
    static func entries(at url: URL) throws -> [FileEntry] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            .map { FileEntry(url: $0, isDirectory: (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) }
            .sorted { $0.isDirectory == $1.isDirectory ? $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending : $0.isDirectory }
    }
    static func read(_ url: URL) throws -> String {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= 1_000_000 else { throw AppError.message("Files larger than 1 MB cannot be opened in this editor.") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 1_000_000 else { throw AppError.message("Files larger than 1 MB cannot be opened in this editor.") }
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else { throw AppError.message("This file is not UTF-8 text.") }
        return text
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct TerminalActivity: Equatable {
    private(set) var running = false
    private(set) var completed = false
    mutating func update(running next: Bool, visible: Bool) {
        if next { completed = false }
        else if running && !visible { completed = true }
        running = next
        if visible { acknowledge() }
    }
    mutating func acknowledge() { completed = false }
}
