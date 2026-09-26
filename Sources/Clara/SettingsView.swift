import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var updateToken = ""
    @State private var modelID = ""
    @State private var search = ""
    @State private var failure: String?
    private var filtered: [RouterModel] { store.models.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { VStack(alignment: .leading, spacing: 6) { Text("Make it yours.").font(.system(size: 25, weight: .medium)); Text("One workspace. Your choice of intelligence.").font(.system(size: 12)).foregroundStyle(Palette.muted) }; Spacer(); IconButton(icon: "xmark", help: "Close settings") { dismiss() } }
            Divider().overlay(Palette.line)
            VStack(alignment: .leading, spacing: 9) {
                Text("OPENROUTER API KEY").font(.system(size: 10, weight: .medium)).tracking(1.3).foregroundStyle(Palette.muted)
                SecureField("sk-or-…", text: $key).textFieldStyle(.roundedBorder)
                Text("Stored in your macOS Keychain. Requests go directly to OpenRouter. Messages and files read by project tools are sent to the selected model provider.").font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(4)
                Link("Get an OpenRouter key ↗", destination: URL(string: "https://openrouter.ai/settings/keys")!).font(.system(size: 11)).foregroundStyle(Palette.accent)
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack { Text("MODEL").font(.system(size: 10, weight: .medium)).tracking(1.3).foregroundStyle(Palette.muted); Spacer(); Button { Task { await store.loadModels() } } label: { Text(store.loadingModels ? "Loading…" : "Refresh catalog") }.disabled(store.loadingModels).font(.system(size: 10)) }
                TextField("Enter any OpenRouter model ID", text: $modelID).textFieldStyle(.roundedBorder)
                TextField("Search models…", text: $search).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filtered) { model in
                            Button { modelID = model.id } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) { Text(model.name).font(.system(size: 11)); Text(model.id).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted) }
                                    Spacer()
                                    if modelID == model.id { Image(systemName: "checkmark").foregroundStyle(Palette.icon) }
                                }.padding(10).contentShape(Rectangle()).background(modelID == model.id ? Color.white.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                        if store.models.isEmpty { Text("Enter a model ID, or refresh the live catalog.").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(30) }
                    }
                }.frame(height: 220).background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
                Text("Project work requires a tool-capable model. Command approval can be granted once or for the project session.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("GITHUB UPDATES").font(.system(size: 10, weight: .medium)).tracking(1.3).foregroundStyle(Palette.muted)
                SecureField("Optional GitHub token for private releases", text: $updateToken).textFieldStyle(.roundedBorder)
                Text("For private repositories, use a fine-grained token with read-only Contents access. Stored in Keychain; sent only to GitHub’s API. Public releases need no token.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            if let failure { Text(failure).font(.system(size: 11)).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save settings") {
                do { try Keychain.save(key.trimmingCharacters(in: .whitespacesAndNewlines)); try Keychain.save(updateToken.trimmingCharacters(in: .whitespacesAndNewlines), service: UpdateChecker.tokenService); store.setModel(modelID.trimmingCharacters(in: .whitespacesAndNewlines)); dismiss() }
                catch { failure = error.localizedDescription }
            }.buttonStyle(.borderedProminent).tint(Palette.accentStrong).foregroundStyle(.white) }
        }.padding(28).frame(width: 560).background(Palette.background).tint(Palette.accent).focusEffectDisabled()
            .onAppear { key = Keychain.read(); updateToken = Keychain.read(service: UpdateChecker.tokenService); modelID = store.model }
    }
}
