import Foundation

/// Reads Servo's existing registry without changing its settings or starting servers.
enum ServoIntegration {
    private struct Settings: Decodable {
        let rootPath: String
        let ports: [String: Int]
    }
    static var settingsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Servo/settings.json")
    }
    static func projectURL(for path: String, settingsURL: URL = settingsURL) -> URL? {
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
