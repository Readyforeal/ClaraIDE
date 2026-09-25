import SwiftUI
import WebKit

/// SwiftUI can reuse an NSViewRepresentable across projects. Explicitly replace
/// its child instead of assuming makeNSView will run for every new session.
final class BrowserContainer: NSView {
    private(set) var mountedWebView: WKWebView?
    private var visibility = PanelVisibility()
    func mount(_ webView: WKWebView, active: Bool) {
        if mountedWebView !== webView {
            if let old = mountedWebView, let responder = window?.firstResponder as? NSView,
               responder === old || responder.isDescendant(of: old) { window?.makeFirstResponder(nil) }
            mountedWebView?.removeFromSuperview()
            visibility = PanelVisibility()
            mountedWebView = webView
            webView.frame = bounds
            webView.autoresizingMask = [.width, .height]
            addSubview(webView)
        }
        visibility.update(webView, active: active)
    }
    func unmount() {
        visibility = PanelVisibility()
        mountedWebView?.removeFromSuperview(); mountedWebView = nil
    }
}
struct BrowserHost: NSViewRepresentable {
    let session: BrowserSession
    let active: Bool
    func makeNSView(context: Context) -> BrowserContainer { BrowserContainer() }
    func updateNSView(_ view: BrowserContainer, context: Context) { view.mount(session.webView, active: active) }
    static func dismantleNSView(_ view: BrowserContainer, coordinator: ()) { view.unmount() }
}
struct BrowserPanel: View {
    @ObservedObject var session: BrowserSession
    @EnvironmentObject var store: AppStore
    @State private var location = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                IconButton(icon: "chevron.left", help: "Back") { session.webView.goBack() }
                IconButton(icon: "chevron.right", help: "Forward") { session.webView.goForward() }
                IconButton(icon: session.busy ? "xmark" : "arrow.clockwise", help: session.busy ? "Stop loading" : "Reload") { if session.busy { session.stop() } else { session.reload() } }
                if let url = session.servoURL {
                    IconButton(icon: "house", help: "Open Servo project · " + url.absoluteString) { store.openServoProject() }
                }
                TextField("URL or localhost address", text: $location).textFieldStyle(.plain).font(.system(size: 11)).onSubmit {
                    do { try session.open(location) } catch { session.error = error.localizedDescription }
                }
                IconButton(icon: "minus", help: "Minimize browser") { store.showBrowser = false }
            }.padding(.horizontal, 14).frame(height: 48)
            ZStack {
                BrowserHost(session: session, active: store.showBrowser)
                    .opacity(session.hasVisiblePage ? 1 : 0)
                    .allowsHitTesting(session.hasVisiblePage && !session.busy)
                if let error = session.error {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 26))
                        Text("Couldn’t load this page").font(.system(size: 18, weight: .medium))
                        Text(session.address).font(.system(size: 11)).textSelection(.enabled)
                        Text(error).font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                        Button("Try again") { session.reload() }
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.background)
                } else if session.busy && !session.hasVisiblePage {
                    VStack(spacing: 12) { ProgressView(); Text(session.activity).font(.system(size: 12)).foregroundStyle(Palette.muted) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.background)
                } else if session.address.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "globe").font(.system(size: 32, weight: .light))
                        Text("A window into your work").font(.system(size: 20, weight: .medium))
                        Text("Open a website or local preview above.\nEnable browser tools in chat to let the agent browse here.").font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.background)
                }
            }.clipShape(RoundedRectangle(cornerRadius: Palette.cornerRadius)).padding(.horizontal, 8)
            HStack { Text(session.activity).lineLimit(1); Spacer(); Text(session.servoURL == nil ? "Project browser · Session-only storage" : "Servo preview · Session-only storage") }.font(.system(size: 9)).foregroundStyle(Palette.muted).padding(10)
        }.onAppear { location = session.address }.onChange(of: session.address) { _, value in location = value }.onChange(of: session.id) { _, _ in location = session.address }
    }
}
