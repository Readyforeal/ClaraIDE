import XCTest
@testable import Clara

final class WorkspaceTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testPathTraversalAndSymlinkEscapeAreRejected() throws {
        XCTAssertThrowsError(try ProjectFiles.resolve("../secret", root: root.path))
        let link = root.appendingPathComponent("outside")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.deletingLastPathComponent())
        XCTAssertThrowsError(try ProjectFiles.resolve("outside/secret", root: root.path))
        XCTAssertEqual(try ProjectFiles.resolve("src/../file.swift", root: root.path).lastPathComponent, "file.swift")
    }
    func testRejectsBinaryAndOversizedFiles() throws {
        let url = root.appendingPathComponent("data")
        try Data([0, 1, 2]).write(to: url)
        XCTAssertThrowsError(try ProjectFiles.read(url))
        try Data(repeating: 65, count: 1_000_001).write(to: url)
        XCTAssertThrowsError(try ProjectFiles.read(url))
    }
    @MainActor func testWorkspaceRoundTripPreservesChatAndModel() throws {
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
        XCTAssertEqual(restored.model, "provider/model")
        XCTAssertEqual(restored.chat?.messages.first?.content, "Hello")
        XCTAssertEqual(restored.project?.path, root.path)
    }
    @MainActor func testSaveRefusesToOverwriteExternalChanges() throws {
        let url = root.appendingPathComponent("code.swift")
        try "original".write(to: url, atomically: true, encoding: .utf8)
        let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
        store.openFile(FileEntry(url: url, isDirectory: false))
        store.fileText = "editor changes"
        try "external changes".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertFalse(store.saveFile())
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "external changes")
    }
    @MainActor func testProposalsApplyOnlyAgainstOriginalContent() throws {
        let url = root.appendingPathComponent("code.swift")
        try "original".write(to: url, atomically: true, encoding: .utf8)
        let store = AppStore(stateURL: root.appendingPathComponent("state.json"))
        let proposal = ProposedEdit(projectID: UUID(), root: root.path, path: "code.swift", original: "original", content: "new")
        store.apply(proposal)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new")
        store.apply(proposal)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new")
    }
}
