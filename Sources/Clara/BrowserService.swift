import SwiftUI
import WebKit

@MainActor final class BrowserSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var address = ""
    @Published var servoURL: URL?
    @Published var error: String?
    @Published var activity = "Ready"
    @Published var busy = false
    override init() {
        let config = WKWebViewConfiguration()
        config.upgradeKnownHostsToHTTPS = false
        config.defaultWebpagePreferences.preferredHTTPSNavigationPolicy = .keepAsRequested
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.underPageBackgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1)
    }
    static func validatedURL(_ value: String) throws -> URL {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = URL(string: "http://" + input)?.host?.lowercased() ?? ""
        let local = host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".test") || host == "127.0.0.1" || host == "[::1]" || host == "::1"
        let normalized = input.contains("://") ? input : (local ? "http://" : "https://") + input
        guard let url = URL(string: normalized), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
              url.user == nil, url.password == nil else { throw AppError.message("Enter an HTTP or HTTPS address without embedded credentials.") }
        return url
    }
    func open(_ value: String) throws {
        let url = try Self.validatedURL(value)
        error = nil; address = url.absoluteString; busy = true; activity = "Opening \(url.host ?? "page")"
        webView.load(URLRequest(url: url, timeoutInterval: 25))
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { busy = true; error = nil }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { busy = false; address = webView.url?.absoluteString ?? address; activity = webView.title ?? "Ready" }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func fail(_ failure: Error) { busy = false; error = failure.localizedDescription; activity = "Navigation failed" }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, ["http", "https", "about"].contains(url.scheme ?? "") else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme ?? "") { webView.load(navigationAction.request) }
        return nil
    }
    func waitForPage() async throws {
        do {
            try await Task.sleep(for: .milliseconds(200))
            for _ in 0..<120 {
                try Task.checkCancellation()
                if !webView.isLoading && !busy { if let error { throw AppError.message(error) }; return }
                try await Task.sleep(for: .milliseconds(200))
            }
            webView.stopLoading(); busy = false
            throw AppError.message("Page load timed out. Try reading the current page again.")
        } catch { if Task.isCancelled { webView.stopLoading(); busy = false }; throw error }
    }
    func snapshot() async throws -> String {
        guard webView.url != nil else { throw AppError.message("Open a page first.") }
        let script = #"""
        (() => {
          const visible = e => !!(e.getClientRects().length) && getComputedStyle(e).visibility !== 'hidden';
          const elements = Array.from(document.querySelectorAll('a,button,input,textarea,select,[role="button"]')).filter(visible).slice(0,100);
          window.__claraElements = elements;
          return JSON.stringify({url:location.href,title:document.title,text:(document.body?.innerText || '').slice(0,18000),elements:elements.map((e,id)=>({id,tag:e.tagName.toLowerCase(),type:e.type||'',label:(e.getAttribute('aria-label')||e.innerText||e.getAttribute('placeholder')||'').slice(0,180),href:e.tagName==='A'?e.href:undefined}))});
        })()
        """#
        return (try await webView.evaluateJavaScript(script)) as? String ?? "No readable page content."
    }
    func interact(id: Int, text: String?) async throws -> String {
        guard (0..<100).contains(id) else { throw AppError.message("Invalid element ID. Read the page again.") }
        let originalURL = webView.url
        let label = try await webView.evaluateJavaScript("(() => { const e=window.__claraElements?.[\(id)]; if(!e || !e.isConnected) throw new Error('Stale element; read page again'); return (e.getAttribute('aria-label') || e.innerText || e.getAttribute('placeholder') || e.tagName).slice(0,180); })()") as? String ?? "Element \(id)"
        let alert = NSAlert()
        alert.messageText = text == nil ? "Allow agent to click a browser element?" : "Allow agent to fill a browser field?"
        alert.informativeText = "Page: \(webView.url?.host ?? "unknown")\nElement: \(label) (#\(id))\n" + (text.map { "Text: \($0.prefix(500))\n" } ?? "") + "This can submit information or change the website. Allow only if this matches your task."
        alert.addButton(withTitle: "Allow"); alert.addButton(withTitle: "Deny")
        guard alert.runModal() == .alertFirstButtonReturn else { return "User denied the action. Do not retry it without new user instructions." }
        try Task.checkCancellation()
        guard webView.url == originalURL else { throw AppError.message("The page changed during approval. Read it again.") }
        let encoded = String(data: try JSONSerialization.data(withJSONObject: ["text": text ?? ""]), encoding: .utf8)!
        let action = text == nil ? "e.click();" : "if (!['INPUT','TEXTAREA'].includes(e.tagName) || ['password','file','hidden'].includes(e.type)) throw new Error('Unsupported field'); const p=e.tagName==='INPUT'?HTMLInputElement.prototype:HTMLTextAreaElement.prototype; Object.getOwnPropertyDescriptor(p,'value').set.call(e, payload.text); e.dispatchEvent(new Event('input',{bubbles:true})); e.dispatchEvent(new Event('change',{bubbles:true}));"
        _ = try await webView.evaluateJavaScript("(() => { const payload=\(encoded); const e=window.__claraElements?.[\(id)]; if(!e || !e.isConnected) throw new Error('Stale element; read page again'); \(action) return true; })()")
        try await waitForPage()
        return try await snapshot()
    }
}
