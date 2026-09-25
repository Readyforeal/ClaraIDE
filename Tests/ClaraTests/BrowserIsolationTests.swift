import AppKit
import WebKit
import XCTest
@testable import Clara

final class BrowserIsolationTests: XCTestCase {
    @MainActor func testProjectSwitchReplacesNativeViewAndRestoresItsOwnPage() async throws {
        let ahp = BrowserSession(), takeoff = BrowserSession()
        XCTAssertNotEqual(ahp.id, takeoff.id)
        XCTAssertFalse(ahp.webView.configuration.websiteDataStore === takeoff.webView.configuration.websiteDataStore)
        let host = BrowserContainer(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        host.mount(ahp.webView, active: true)
        ahp.webView.loadHTMLString("<html><body>AHP fixture</body></html>", baseURL: URL(string: "http://isolation.test"))
        try await ahp.waitForPage()
        host.mount(takeoff.webView, active: true)
        takeoff.webView.loadHTMLString("<html><body>Takeoff fixture</body></html>", baseURL: URL(string: "http://isolation.test"))
        try await takeoff.waitForPage()
        XCTAssertNil(ahp.webView.superview)
        XCTAssertTrue(host.mountedWebView === takeoff.webView)
        host.mount(ahp.webView, active: true)
        XCTAssertNil(takeoff.webView.superview)
        XCTAssertTrue(host.mountedWebView === ahp.webView)
        XCTAssertFalse(ahp.webView.isHidden)
        let ahpText = try await ahp.webView.evaluateJavaScript("document.body.innerText") as? String
        let takeoffText = try await takeoff.webView.evaluateJavaScript("document.body.innerText") as? String
        XCTAssertEqual(ahpText, "AHP fixture")
        XCTAssertEqual(takeoffText, "Takeoff fixture")
        host.unmount()
        XCTAssertNil(ahp.webView.superview)
    }

    @MainActor func testOptInLocalSitesRestoreMatchingOrigins() async throws {
        guard let input = ProcessInfo.processInfo.environment["CLARA_BROWSER_TEST_URLS"] else { throw XCTSkip("Set CLARA_BROWSER_TEST_URLS to two local fixture URLs") }
        let urls = input.split(separator: ",").compactMap { URL(string: String($0)) }
        XCTAssertEqual(urls.count, 2)
        guard urls.count == 2 else { return }
        let sessions = [BrowserSession(), BrowserSession()]
        let host = BrowserContainer(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        defer { host.unmount() }
        for (session, url) in zip(sessions, urls) {
            host.mount(session.webView, active: true)
            try session.open(url.absoluteString)
            try await session.waitForPage()
            XCTAssertTrue(session.hasVisiblePage)
            let origin = try await session.webView.evaluateJavaScript("location.hostname") as? String
            let textLength = try await session.webView.evaluateJavaScript("document.body.innerText.length") as? Int
            XCTAssertEqual(origin, url.host)
            XCTAssertGreaterThan(textLength ?? 0, 0, "Site returned an empty rendered document")
        }
        host.mount(sessions[0].webView, active: true)
        let restored = try await host.mountedWebView?.evaluateJavaScript("location.hostname") as? String
        XCTAssertEqual(restored, urls[0].host)
        XCTAssertNil(sessions[1].webView.superview)
    }

    @MainActor func testCookiesAreIsolatedEvenOnTheSameOrigin() async throws {
        let first = BrowserSession(), second = BrowserSession()
        let cookie = try XCTUnwrap(HTTPCookie(properties: [.domain: "isolation.test", .path: "/", .name: "session", .value: "first-project"]))
        await first.webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        let firstCookies = await first.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let secondCookies = await second.webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        XCTAssertTrue(firstCookies.contains { $0.name == "session" && $0.value == "first-project" })
        XCTAssertFalse(secondCookies.contains { $0.name == "session" })
    }

    @MainActor func testFailedNavigationHidesThePreviousPageAndBlocksAgentReads() async throws {
        let session = BrowserSession()
        session.webView.loadHTMLString("<html><body>Previous page</body></html>", baseURL: URL(string: "http://isolation.test"))
        try await session.waitForPage()
        XCTAssertTrue(session.hasVisiblePage)
        try session.open("http://127.0.0.1:1/unavailable")
        XCTAssertFalse(session.hasVisiblePage)
        do { try await session.waitForPage(); XCTFail("Expected blocked-port navigation to fail") } catch {}
        XCTAssertFalse(session.hasVisiblePage)
        XCTAssertNotNil(session.error)
        XCTAssertFalse(session.busy)
        do { _ = try await session.snapshot(); XCTFail("Stale page must not be readable by the agent") } catch {}
    }
}
