import Foundation

@main struct WorkspaceChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
            guard try condition() else { throw AppError.message("FAIL: \(name)") }
            print("PASS: \(name)")
        }
        func rejects(_ name: String, _ action: () throws -> Void) throws {
            do { try action() } catch { print("PASS: \(name)"); return }
            throw AppError.message("FAIL: \(name)")
        }
        try rejects("path traversal") { _ = try ProjectFiles.resolve("../secret", root: root.path) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside"), withDestinationURL: root.deletingLastPathComponent())
        try rejects("symlink escape") { _ = try ProjectFiles.resolve("outside/secret", root: root.path) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("dangling"), withDestinationURL: root.deletingLastPathComponent().appendingPathComponent("missing-\(UUID().uuidString)"))
        try rejects("dangling symlink escape") { _ = try ProjectFiles.resolve("dangling", root: root.path) }
        try check(ProjectFiles.resolve("src/../file.swift", root: root.path).lastPathComponent == "file.swift", "valid relative path")
        let url = root.appendingPathComponent("code.swift")
        try Data([0, 1, 2]).write(to: url)
        try rejects("binary file rejection") { _ = try ProjectFiles.read(url) }
        try Data(repeating: 65, count: 1_000_001).write(to: url)
        try rejects("large file rejection") { _ = try ProjectFiles.read(url) }
        let state = root.appendingPathComponent("state.json")
        let store = AppStore(stateURL: state)
        let project = Project(name: "Test", path: root.path)
        store.workspace.projects = [project]
        store.workspace.selectedProject = project.id
        store.workspace.selectedChat = project.chats[0].id
        store.setModel("provider/model")
        store.updateChat(project.chats[0].id) { $0.messages.append(Message(role: "user", content: "Hello")) }
        store.persist()
        let restored = AppStore(stateURL: state)
        try check(restored.model == "provider/model" && restored.chat?.messages.first?.content == "Hello" && restored.project?.path == root.path, "workspace persistence")
        try "original".write(to: url, atomically: true, encoding: .utf8)
        store.openFile(FileEntry(url: url, isDirectory: false))
        store.fileText = "editor changes"
        try "external".write(to: url, atomically: true, encoding: .utf8)
        try check(!store.saveFile(), "external editor conflict detected")
        try check(String(contentsOf: url, encoding: .utf8) == "external", "external change preserved")
        store.fileText = store.savedText
        let proposal = ProposedEdit(projectID: project.id, root: root.path, path: "code.swift", original: "external", content: "new")
        store.error = nil; store.apply(proposal)
        try check(String(contentsOf: url, encoding: .utf8) == "new", "proposal applied")
        store.apply(proposal)
        try check(store.error != nil, "stale proposal rejected")
        let second = root.appendingPathComponent("second.swift")
        try "second".write(to: second, atomically: true, encoding: .utf8)
        let firstID = store.selectedFileID!
        store.fileText = "unsaved first"
        store.minimizeFile(firstID)
        try check(!store.showEditor, "minimizing active file also collapses navigator")
        store.openFile(FileEntry(url: second, isDirectory: false))
        let secondID = store.selectedFileID!
        store.fileText = "unsaved second"
        try check(store.documents.count == 2 && store.documents.first?.text == "unsaved first", "opening another file preserves unsaved buffer")
        store.restoreFile(firstID)
        try check(store.fileText == "unsaved first" && store.documents.first(where: { $0.id == secondID })?.minimized == true, "restoring a file minimizes the previous editor")
        store.minimizeFile(firstID)
        try check(store.expandedDocument == nil && store.documents.allSatisfy(\.minimized), "all files can dock independently")
        try check(store.saveDocument(secondID), "saving a docked document")
        try check(String(contentsOf: second, encoding: .utf8) == "unsaved second", "docked save writes the correct file")
        let other = Project(name: "Other", path: root.path)
        store.workspace.projects.append(other)
        store.selectProject(other.id)
        try check(store.projectDocuments.isEmpty, "file docks are project scoped")
        store.selectProject(project.id)
        try check(store.documents.first(where: { $0.id == firstID })?.text == "unsaved first", "project switch preserves unsaved buffers")
        store.closeFile(secondID)
        try check(store.documents.count == 1 && store.documents[0].id == firstID, "closing one editor preserves other files")
        try check(!store.sidebarCollapsed, "minimizing auto-collapsed editor restores sidebar")
        store.restoreFile(firstID)
        try check(store.sidebarCollapsed, "restoring file auto-collapses sidebar")
        store.openFile(FileEntry(url: second, isDirectory: false))
        let reopenedID = store.selectedFileID!
        store.closeFile(reopenedID)
        try check(!store.sidebarCollapsed, "closing active file restores automatically collapsed sidebar across file switches")
        store.toggleSidebar()
        store.restoreFile(firstID)
        store.minimizeFile(firstID)
        try check(store.sidebarCollapsed, "manually collapsed sidebar stays collapsed")
        store.toggleSidebar()
        store.restoreFile(firstID)
        store.toggleSidebar()
        store.toggleSidebar()
        store.minimizeFile(firstID)
        try check(store.sidebarCollapsed, "manual toggle cancels automatic restoration")
        store.toggleSidebar()
        store.restoreFile(firstID)
        store.openFile(FileEntry(url: second, isDirectory: false))
        store.minimizeFile(firstID)
        try check(store.sidebarCollapsed, "minimizing an already docked file does not restore sidebar while another editor is open")
        try check(store.showEditor, "minimizing an inactive file preserves navigator for the open editor")
        store.closeFile(store.selectedFileID!)
        try check(!store.sidebarCollapsed, "closing remaining editor restores sidebar")
        for width: CGFloat in [856, 1100, 1380, 1800] {
            for navigator in [false, true] {
                for editor in [false, true] {
                    for docked in [false, true] {
                        let layout = WorkspaceLayout(width: width, navigatorOpen: navigator, editorOpen: editor, hasDockedFiles: docked)
                        try check(layout.chatWidth <= layout.navigatorX, "chat avoids navigator at \(width)")
                        if editor {
                            try check(layout.editorX >= (navigator ? layout.navigatorX + layout.navigatorWidth + 12 : layout.chatWidth + 12) && layout.editorX + layout.editorWidth <= (docked ? layout.dockX - 12 : width - 14), "editor fits beside chat and navigator at \(width)")
                        }
                    }
                }
            }
        }
        let chatID = store.chat!.id
        let chatCount = store.project!.chats.count
        store.deleteChat(chatID)
        try check(store.chat?.id != chatID && store.project!.chats.count >= 1, "deleting selected chat selects a valid replacement")
        store.undoDeleteChat()
        try check(store.chat?.id == chatID && store.project!.chats.count == chatCount, "undo restores chat and removes unused replacement")
        try check(BrowserSession.validatedURL("localhost:3000").absoluteString == "http://localhost:3000", "browser address normalization")
        try check(BrowserSession.validatedURL("http://localhost:3000").scheme == "http", "local HTTP preview support")
        try rejects("browser file URL rejected") { _ = try BrowserSession.validatedURL("file:///etc/passwd") }
        try rejects("browser embedded credentials rejected") { _ = try BrowserSession.validatedURL("https://user:pass@example.com") }
        try rejects("browser javascript URL rejected") { _ = try BrowserSession.validatedURL("javascript:alert(1)") }
        try check(store.saveDocument(firstID), "save remaining buffer before project deletion")
        store.deleteProject(other.id)
        try check(store.project?.id == project.id && store.documents.count == 1, "deleting inactive project preserves active workspace")
        store.deleteChat(store.chat!.id)
        store.deleteProject(project.id)
        try check(store.workspace.projects.isEmpty && store.chat == nil && store.project == nil, "deleting last project clears selection")
        try check(store.documents.isEmpty && store.selectedFileID == nil && store.entries.isEmpty, "project deletion clears editor and navigator state")
        try check(store.deletedChat == nil, "project deletion clears stale chat undo")
        try check(FileManager.default.fileExists(atPath: url.path), "project deletion preserves files on disk")
        let afterDeletion = AppStore(stateURL: state)
        try check(afterDeletion.workspace.projects.isEmpty, "project deletion persists")
        store.workspace.projects = [project, other]
        store.selectProject(project.id)
        let originalProjectChatCount = store.project!.chats.count
        store.newChat()
        let generalID = store.chat!.id
        try check(store.project == nil && store.workspace.generalChats.count == 1, "top new chat creates an unassociated conversation")
        store.updateChat(generalID) { $0.messages.append(Message(role: "user", content: "General question")) }
        store.setModel("general/model")
        let generalRestored = AppStore(stateURL: state)
        try check(generalRestored.project == nil && generalRestored.chat?.id == generalID && generalRestored.chat?.messages.count == 1, "general chat history and selection survive relaunch")
        store.newProjectChat(other.id)
        try check(store.project?.id == other.id && store.project?.chats.count == other.chats.count + 1, "project new chat targets that project")
        try check(store.workspace.projects[0].chats.count == originalProjectChatCount, "project new chat leaves other project unchanged")
        store.selectChat(generalID)
        try check(store.project == nil && store.model == "general/model" && store.entries.isEmpty, "selecting general chat clears project context")
        store.deleteChat(generalID)
        try check(store.workspace.generalChats.isEmpty, "general chat deletion")
        store.undoDeleteChat()
        try check(store.chat?.id == generalID && store.project == nil, "general chat undo restores correct scope")
        let legacy = try JSONDecoder().decode(Workspace.self, from: Data("{\"projects\":[],\"defaultModel\":\"legacy\"}".utf8))
        try check(legacy.generalChats.isEmpty && legacy.defaultModel == "legacy", "older workspace data remains readable")
        var terminalActivity = TerminalActivity()
        terminalActivity.update(running: false, visible: false)
        try check(!terminalActivity.running && !terminalActivity.completed, "idle shell has no terminal dot")
        terminalActivity.update(running: true, visible: false)
        try check(terminalActivity.running && !terminalActivity.completed, "running command shows activity")
        terminalActivity.update(running: false, visible: false)
        try check(terminalActivity.completed, "docked command completion stays pending")
        terminalActivity.update(running: false, visible: false)
        try check(terminalActivity.completed, "completion survives subsequent idle samples")
        terminalActivity.acknowledge()
        try check(!terminalActivity.completed, "opening terminal clears completion")
        terminalActivity.update(running: true, visible: true)
        terminalActivity.update(running: false, visible: true)
        try check(!terminalActivity.completed, "visible completion does not leave an unread indicator")
        let repository = root.appendingPathComponent("git-project")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        func git(_ args: [String]) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", repository.path] + args
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            try check(process.terminationStatus == 0, "Git fixture: " + args[0])
        }
        try check(GitRepository.branch(at: repository.path) == nil, "non-repository has no branch")
        try git(["init", "-b", "main"])
        try check(GitRepository.branch(at: repository.path) == "main", "unborn branch is visible")
        try git(["-c", "user.name=Clara Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-m", "fixture"])
        try git(["checkout", "-b", "feature/header"])
        try check(GitRepository.branch(at: repository.path) == "feature/header", "branch changes are detected")
        try git(["checkout", "--detach"])
        try check(GitRepository.branch(at: repository.path)?.hasPrefix("Detached · ") == true, "detached HEAD displays commit")
        let worktree = root.appendingPathComponent("linked-worktree")
        try git(["worktree", "add", worktree.path, "main"])
        try check(GitRepository.branch(at: worktree.path) == "main", "linked worktree branch detection")
        try check(BrowserSession.validatedURL("http://example.com").scheme == "http", "explicit remote HTTP remains HTTP")
        try check(BrowserSession.validatedURL("127.0.0.1:8080").scheme == "http", "loopback previews default to HTTP")
        try check(BrowserSession.validatedURL("example.com").scheme == "https", "public addresses default to HTTPS")
        let servoRoot = root.appendingPathComponent("Servo")
        let servoSettings = root.appendingPathComponent("servo-settings.json")
        try FileManager.default.createDirectory(at: servoRoot, withIntermediateDirectories: true)
        let linkedSite = servoRoot.appendingPathComponent("linked-project")
        try FileManager.default.createSymbolicLink(at: linkedSite, withDestinationURL: repository)
        let registry: [String: Any] = ["rootPath": servoRoot.path, "ports": [linkedSite.path: 8123]]
        try JSONSerialization.data(withJSONObject: registry).write(to: servoSettings)
        try check(ServoIntegration.projectURL(for: repository.path, settingsURL: servoSettings)?.absoluteString == "http://127.0.0.1:8123", "Servo resolves symlinked projects to their registered port")
        try check(ServoIntegration.projectURL(for: linkedSite.path, settingsURL: servoSettings)?.port == 8123, "Servo accepts project opened through its link")
        try check(ServoIntegration.projectURL(for: root.path, settingsURL: servoSettings) == nil, "unregistered project has no Servo URL")
        try FileManager.default.removeItem(at: linkedSite)
        try check(ServoIntegration.projectURL(for: repository.path, settingsURL: servoSettings) == nil, "stale Servo port entries are ignored")
        try Data("invalid".utf8).write(to: servoSettings)
        try check(ServoIntegration.projectURL(for: repository.path, settingsURL: servoSettings) == nil, "invalid Servo settings fail gracefully")
        try check(BrowserSession.validatedURL("shop.test").scheme == "http", ".test previews default to HTTP")
        let manifestURL = servoSettings.deletingLastPathComponent().appendingPathComponent("sites.json")
        func manifest(running: Bool = true, age: Double = 0, address: String = "http://shop.test") throws {
            try JSONSerialization.data(withJSONObject: ["version": 1, "updatedAt": Date().timeIntervalSince1970 - age,
                "sites": [["path": linkedSite.path, "resolvedPath": repository.path, "url": address, "running": running]]]).write(to: manifestURL)
        }
        try manifest()
        try check(ServoIntegration.projectURL(for: repository.path, settingsURL: servoSettings)?.absoluteString == "http://shop.test", "live Servo URL overrides legacy settings")
        try check(ServoIntegration.projectURL(for: repository.appendingPathComponent("public").path, settingsURL: servoSettings)?.host == "shop.test", "nested project folder matches site root")
        try check(ServoIntegration.projectURL(for: repository.path + "-other", settingsURL: servoSettings) == nil, "sibling path is not matched by prefix")
        try manifest(running: false)
        try check(ServoIntegration.projectURL(for: repository.path, settingsURL: servoSettings) == nil, "stopped sites do not advertise a URL")
        try manifest(age: 60)
        try check(ServoIntegration.projectURL(for: repository.path, settingsURL: servoSettings) == nil, "expired manifests do not fall back to stale ports")
        try manifest(address: "https://192.168.1.10:28001")
        try check(ServoIntegration.projectURL(for: repository.path, settingsURL: servoSettings)?.scheme == "https", "actual HTTPS address is preserved")
        try manifest(address: "file:///etc/hosts")
        try check(ServoIntegration.projectURL(for: repository.path, settingsURL: servoSettings) == nil, "non-web manifest URLs are rejected")
        try check(ReleaseVersion("v0.10.0")! > ReleaseVersion("0.9.9")!, "update versions compare numerically")
        try check(ReleaseVersion("0.3.0-beta") == nil && ReleaseVersion("../bad") == nil, "unsupported release versions are rejected")
        let update = GitHubRelease(tag_name: "v0.3.0", html_url: URL(string: "https://github.com/Readyforeal/ClaraIDE/releases")!, draft: false, prerelease: false,
            assets: [.init(name: "Clara-0.3.0-arm64.dmg", browser_download_url: URL(string: "https://github.com/Readyforeal/ClaraIDE/releases/download/v0.3.0/Clara-0.3.0-arm64.dmg")!)])
        try check(update.installer(repository: "Readyforeal/ClaraIDE") != nil, "matching DMG is selected")
        try check(update.installer(repository: "another/repo") == nil, "installer must belong to configured repository")
        print("All workspace, browser URL, and responsive layout checks passed.")
    }
}
