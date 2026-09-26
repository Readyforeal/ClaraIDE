import XCTest
@testable import Clara

final class AgentToolsTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testPagedReadAndHiddenSearch() throws {
        let content = (1...600).map { "line \($0)" }.joined(separator: "\n")
        try content.write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        let first = try AgentFiles.read(path: ".env", root: root.path, count: 200)
        XCTAssertTrue(first.contains("start_line=201"))
        XCTAssertFalse(first.contains("201: line"))
        let next = try AgentFiles.read(path: ".env", root: root.path, start: 201)
        XCTAssertTrue(next.contains("201: line 201"))
        XCTAssertTrue(try AgentFiles.list(path: ".", root: root.path).contains(".env"))
        let search = try AgentFiles.search(path: ".", root: root.path, query: "line 599")
        XCTAssertTrue(search.contains(".env:599"), search)
        XCTAssertThrowsError(try AgentFiles.read(path: "../secret", root: root.path))
    }
    func testReadBeyondEditorLimitAndListingPagination() throws {
        try String(repeating: "some content\n", count: 100_000).write(to: root.appendingPathComponent("large.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(try AgentFiles.read(path: "large.txt", root: root.path, start: 90000, count: 2).contains("90000: some content"))
        for n in 0..<210 { FileManager.default.createFile(atPath: root.appendingPathComponent("f\(n)").path, contents: Data()) }
        XCTAssertTrue(try AgentFiles.list(path: ".", root: root.path).contains("offset=200"))
        XCTAssertTrue(try AgentFiles.list(path: ".", root: root.path, offset: 200).contains("211/211"))
    }
    func testCommandWorkingDirectoryOutputAndExitStatus() async throws {
        let result = try await AgentCommand.run("pwd; echo stdout; echo stderr >&2; exit 7", directory: root.path)
        XCTAssertTrue(result.output.contains(root.lastPathComponent))
        XCTAssertTrue(result.output.contains("stdout")); XCTAssertTrue(result.output.contains("stderr"))
        XCTAssertEqual(result.status, 7); XCTAssertFalse(result.timedOut)
    }
    func testTimeoutKillsChildrenAndCancellationStopsCommand() async throws {
        let result = try await AgentCommand.run("(sleep 1; touch should-not-exist) & wait", directory: root.path, timeout: 0.2)
        XCTAssertTrue(result.timedOut)
        let task = Task { try await AgentCommand.run("(sleep 1; touch cancelled-child) & wait", directory: root.path) }
        try await Task.sleep(for: .milliseconds(200)); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("should-not-exist").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("cancelled-child").path))
    }
    func testAppShutdownStopsActiveCommands() async throws {
        let task = Task { try await AgentCommand.run("touch started; sleep 10; touch orphan", directory: root.path) }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("started").path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("started").path))
        AgentCommand.stopAll()
        let result = try await task.value
        XCTAssertNotEqual(result.status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("orphan").path))
    }
    func testCommandOutputClipping() async throws {
        let result = try await AgentCommand.run("head -c 30000 /dev/zero | tr '\\0' a; echo END", directory: root.path)
        XCTAssertTrue(result.output.contains("Output clipped")); XCTAssertTrue(result.output.contains("END"))
        XCTAssertLessThan(result.output.utf8.count, 25_000)
    }
    func testFragmentedToolsAndReasoningRoundTrip() throws {
        var parser = RouterStreamAccumulator()
        try parser.consume(["choices": [["delta": ["tool_calls": [["index": 0, "id": "call_1", "function": ["name": "read_file", "arguments": "{\"path\":" ]]], "reasoning_details": [["index": 0, "type": "reasoning.text", "text": "first "]]]]]])
        try parser.consume(["choices": [["delta": ["tool_calls": [["index": 0, "function": ["arguments": "\".env\"}"]]], "reasoning_details": [["index": 0, "text": "second"]]], "finish_reason": "tool_calls"]]])
        let result = try parser.result()
        XCTAssertEqual(result.calls.first?.function.arguments, "{\"path\":\".env\"}")
        let message = APIMessage(role: "assistant", content: result.text, tool_calls: result.calls, reasoning_details: result.reasoningDetails)
        XCTAssertTrue(String(decoding: try JSONEncoder().encode(message), as: UTF8.self).contains("first second"))
    }
    func testIncompleteStreamAndTruncatedToolAreDistinguished() throws {
        var parser = RouterStreamAccumulator()
        let fragment: [String: Any] = ["index": 0, "id": "call_1", "function": ["name": "run_command", "arguments": "{\"command\":"]]
        try parser.consume(["choices": [["delta": ["tool_calls": [fragment]]]]])
        XCTAssertThrowsError(try parser.result())
        try parser.consume(["choices": [["finish_reason": "length"]]])
        XCTAssertEqual(try parser.result().finishReason, "length")
        try parser.consume(["choices": [["finish_reason": "tool_calls"]]])
        XCTAssertThrowsError(try parser.result())
    }
    func testModelOutputBudgetUsesCatalogLimits() throws {
        let model = try JSONDecoder().decode(RouterModel.self, from: Data(#"{"id":"test/model","name":"Test","context_length":32768,"supported_parameters":["tools"],"top_provider":{"max_completion_tokens":4096}}"#.utf8))
        XCTAssertEqual(model.outputBudget, 4096)
        XCTAssertEqual(model.supported_parameters, ["tools"])
    }
    func testToolHistorySurvivesWorkspacePersistence() throws {
        var chat = Conversation()
        chat.toolHistory = [APIMessage(role: "assistant", content: "", tool_calls: [ToolCall(id: "one", function: .init(name: "read_file", arguments: "{}"))]), APIMessage(role: "tool", content: "file contents", tool_call_id: "one")]
        let restored = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(chat))
        XCTAssertEqual(restored.toolHistory?.last?.tool_call_id, "one")
        XCTAssertNil(try JSONDecoder().decode(Conversation.self, from: Data("{\"id\":\"\(UUID())\",\"title\":\"Old\",\"model\":\"\",\"messages\":[]}".utf8)).toolHistory)
    }
}
