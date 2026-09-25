import Foundation

/// Reads Servo’s live URL manifest; older Servo builds fall back to their port registry.
enum ServoIntegration {
    private struct Registry: Decodable {
        struct Site: Decodable { let path: String; let resolvedPath: String; let url: String; let running: Bool }
        let version: Int
        let updatedAt: Double
        let sites: [Site]
    }
    private struct Settings: Decodable {
        let rootPath: String
        let ports: [String: Int]
    }
    static var settingsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Servo/settings.json")
    }
    static func projectURL(for path: String, settingsURL: URL = settingsURL) -> URL? {
        let registryURL = settingsURL.deletingLastPathComponent().appendingPathComponent("sites.json")
        if FileManager.default.fileExists(atPath: registryURL.path) {
            guard let data = try? Data(contentsOf: registryURL),
                  let registry = try? JSONDecoder().decode(Registry.self, from: data), registry.version == 1,
                  (-5...20).contains(Date().timeIntervalSince1970 - registry.updatedAt) else { return nil }
            let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
            let match = registry.sites.filter { site in
                let root = URL(fileURLWithPath: site.resolvedPath).resolvingSymlinksInPath().standardizedFileURL.path
                return target == root || target.hasPrefix(root + "/")
            }.max { $0.resolvedPath.count < $1.resolvedPath.count }
            guard let match, match.running, let url = URL(string: match.url),
                  ["http", "https"].contains(url.scheme), url.host != nil, url.user == nil, url.password == nil else { return nil }
            return url
        }
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return nil }
        let root = URL(fileURLWithPath: settings.rootPath)
        let target = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        // Match only current immediate children, just as Servo discovers sites.
        guard let sites = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return nil }
        for site in sites.sorted(by: { $0.path < $1.path }) {
            let resolved = site.resolvingSymlinksInPath().standardizedFileURL
            let port = settings.ports[site.path] ?? settings.ports.first {
                URL(fileURLWithPath: $0.key).standardizedFileURL.path == site.standardizedFileURL.path
            }?.value
            guard (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  resolved.path == target.path,
                  let port, (1...65535).contains(port) else { continue }
            return URL(string: "http://127.0.0.1:\(port)")
        }
        return nil
    }
}
