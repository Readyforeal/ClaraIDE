import SwiftUI
import WebKit

struct BrowserHost: NSViewRepresentable {
    let session: BrowserSession
    let active: Bool
    func makeCoordinator() -> PanelVisibility { PanelVisibility() }
    func makeNSView(context: Context) -> WKWebView { session.webView }
    func updateNSView(_ view: WKWebView, context: Context) { context.coordinator.update(view, active: active) }
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
                IconButton(icon: session.busy ? "xmark" : "arrow.clockwise", help: session.busy ? "Stop loading" : "Reload") { if session.busy { session.webView.stopLoading(); session.busy = false } else { session.webView.reload() } }
                if let url = session.servoURL {
                    IconButton(icon: "house", help: "Open Servo project · " + url.absoluteString) { store.openServoProject() }
                }
                TextField("URL or localhost address", text: $location).textFieldStyle(.plain).font(.system(size: 11)).onSubmit {
                    do { try session.open(location) } catch { session.error = error.localizedDescription }
                }
                IconButton(icon: "minus", help: "Minimize browser") { store.showBrowser = false }
            }.padding(.horizontal, 14).frame(height: 48)
            if let error = session.error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.accent).padding(8) }
            ZStack {
                BrowserHost(session: session, active: store.showBrowser)
                if session.address.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "globe").font(.system(size: 32, weight: .light))
                        Text("A window into your work").font(.system(size: 20, weight: .medium))
                        Text("Open a website or local preview above.\nEnable browser tools in chat to let the agent browse here.").font(.system(size: 12)).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.background)
                }
            }.clipShape(RoundedRectangle(cornerRadius: Palette.cornerRadius)).padding(.horizontal, 8)
            HStack { Text(session.activity).lineLimit(1); Spacer(); Text(session.servoURL == nil ? "Project browser · Session-only storage" : "Servo preview · Session-only storage") }.font(.system(size: 9)).foregroundStyle(Palette.muted).padding(10)
        }.onAppear { location = session.address }.onChange(of: session.address) { _, value in location = value }
    }
}
