import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var splitTerminal: Bool { store.showTerminal && store.terminalPlacement != .full }
    private var shortChat: Bool { store.showTerminal && store.terminalPlacement == .bottom }
    private var compactChat: Bool { store.expandedDocument != nil || splitTerminal }
    @State private var review: ProposedEdit?
    @State private var gitBranch: String?
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 244)
                .frame(width: store.sidebarCollapsed ? 0 : 244, alignment: .leading)
                .clipped().allowsHitTesting(!store.sidebarCollapsed).accessibilityHidden(store.sidebarCollapsed)
            VStack(spacing: 0) {
                header
                if store.showingIssues {
                    IssuesView()
                } else {
                GeometryReader { geometry in
                    let layout = WorkspaceLayout(width: geometry.size.width, navigatorOpen: store.showEditor, editorOpen: store.expandedDocument != nil, hasDockedFiles: store.projectDocuments.contains(where: \.minimized))
                    let terminalLayout = TerminalLayout(size: geometry.size, placement: store.terminalPlacement)
                    ZStack(alignment: .topLeading) {
                        chatView.padding(.bottom, splitTerminal ? terminalLayout.chatBottomPadding : WorkspaceLayout.bottomClearance)
                            .frame(width: splitTerminal ? terminalLayout.chat.width : layout.chatWidth,
                                   height: splitTerminal ? terminalLayout.chat.height : geometry.size.height)
                        FloatingWorkspace()
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                }
            }.background(WallpaperGlass().overlay(Color.black.opacity(0.70)))
        }
        .overlay(alignment: .topLeading) {
            DockIconButton(icon: "sidebar.left", help: store.sidebarCollapsed ? "Show projects" : "Hide projects", width: 30, height: 30) {
                store.toggleSidebar()
            }.padding(.leading, 104).padding(.top, 12)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: store.sidebarCollapsed)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: store.showEditor)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: store.terminalPlacement)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: store.showTerminal)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: store.projectDocuments.map { "\($0.id)-\($0.minimized)" })
        .background(Palette.background)
        .foregroundStyle(Color(white: 0.87))
        .sheet(isPresented: $store.showSettings) { SettingsView() }
        .sheet(item: $review) { edit in EditReview(edit: edit) }
        .alert("Something needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text("Clara").font(.system(size: 19, weight: .semibold, design: .rounded)).tracking(-0.6)
                Spacer()

            }.padding(.horizontal, 20).frame(height: 36).padding(.top, 56).padding(.bottom, 12)
            VStack(spacing: 2) {
                SidebarAction(title: "New conversation", icon: "square.and.pencil", shortcut: "⌘N", action: store.newChat)
                SidebarAction(title: "Issues", icon: "tray", selected: store.showingIssues) {
                    store.showingIssues = true
                }
            }.padding(.horizontal, 12)
            HStack { Text("PROJECTS").font(.system(size: 9, weight: .semibold)).tracking(1.6); Spacer(); IconButton(icon: "plus", help: "Open project folder", action: store.addProject) }
                .foregroundStyle(Palette.muted).padding(.leading, 20).padding(.trailing, 14).padding(.top, 26).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(store.workspace.projects) { project in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 0) {
                            Button { store.selectProject(project.id) } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "folder").foregroundStyle(project.id == store.project?.id ? Palette.icon : Palette.muted)
                                    Text(project.name).lineLimit(1).fontWeight(.medium)
                                    Spacer()
                                    Image(systemName: project.id == store.project?.id ? "chevron.down" : "chevron.right").font(.system(size: 8))
                                }.font(.system(size: 12)).padding(.horizontal, 8).padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { store.requestDeleteProject(project.id) } label: {
                                        Label("Delete Project…", systemImage: "trash")
                                    }
                                }
                            IconButton(icon: "square.and.pencil", help: "New chat in " + project.name) { store.newProjectChat(project.id) }
                            }
                            if project.id == store.project?.id {
                                ForEach(project.chats) { chat in
                                    ChatRow(chat: chat)
                                }
                            }
                        }
                    }
                    if !store.workspace.generalChats.isEmpty {
                        Text("CHATS").font(.system(size: 9, weight: .semibold)).tracking(1.6)
                            .foregroundStyle(Palette.muted).padding(.leading, 8).padding(.top, 18)
                        ForEach(store.workspace.generalChats) { chat in ChatRow(chat: chat) }
                    }
                    if store.workspace.projects.isEmpty && store.workspace.generalChats.isEmpty {
                        Text("Your projects live here.\nOpen a folder to get started.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(5).padding(12)
                    }
                }.padding(.horizontal, 12)
            }
            Spacer(minLength: 0)
            if store.deletedChat != nil {
                HStack { Text("Chat deleted").font(.system(size: 10)).foregroundStyle(Palette.muted); Spacer(); Button("Undo") { store.undoDeleteChat() }.buttonStyle(.plain).font(.system(size: 11)) }.padding(18)
            }
            HStack(spacing: 10) {
                Image(systemName: "circle.hexagongrid").font(.system(size: 18)).foregroundStyle(Palette.icon)
                VStack(alignment: .leading, spacing: 3) { Text("Your workspace").font(.system(size: 11, weight: .medium)); Text("Local files · OpenRouter AI").font(.system(size: 9)).foregroundStyle(Palette.muted) }
                Spacer()
                IconButton(icon: "gearshape", help: "Settings") { store.showSettings = true }
            }.padding(18).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }.background(WallpaperGlass().overlay(Color.black.opacity(0.22)))
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: store.showingIssues ? "tray" : "folder").foregroundStyle(Palette.muted)
            Text(store.showingIssues ? "Issues" : store.project?.name ?? "General").foregroundStyle(Palette.muted)
            Text("/").foregroundStyle(Color.white.opacity(0.2))
            Text(store.showingIssues ? "Inbox" : store.chat?.title ?? "Welcome").lineLimit(1)
            Spacer()
            Image(systemName: store.showingIssues ? "circle.dotted" : "arrow.triangle.branch").foregroundStyle(Palette.muted)
            Text(store.showingIssues ? "Tunnel not connected" : (store.project == nil ? "General chat" : gitBranch ?? "Not a Git repository"))
                .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                .help(gitBranch ?? (store.project == nil ? "General chat" : "Not a Git repository"))
        }.font(.system(size: 11)).padding(.trailing, 26).padding(.leading, store.sidebarCollapsed ? 154 : 26).frame(height: 54)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
            .task(id: store.project?.path) {
                gitBranch = nil
                guard let path = store.project?.path else { return }
                while !Task.isCancelled {
                    let branch = await Task.detached(priority: .utility) { GitRepository.branch(at: path) }.value
                    guard !Task.isCancelled else { return }
                    gitBranch = branch
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                }
            }
    }
    private var chatView: some View {
        VStack(spacing: 0) {
            if shortChat && store.chat?.messages.isEmpty != false {
                Spacer(minLength: 8)
                Text("What are we building?").font(.system(size: 22, weight: .medium))
                Spacer(minLength: 8)
            } else if store.chat?.messages.isEmpty != false {
                Spacer()
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 7) { Image(systemName: "sparkle").foregroundStyle(Palette.icon); Text("A LITTLE SPACE TO BUILD").tracking(2) }.font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.icon)
                    Text("What are we building?").font(.system(size: compactChat ? 25 : 38, weight: .medium)).tracking(-1.4)
                    Text("An idea, a tricky bug, a fresh start.\nYour conversation is the workspace.")
                        .font(.system(size: 14)).foregroundStyle(Palette.muted).lineSpacing(7)
                    let suggestionLayout = compactChat ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
                    suggestionLayout {
                        suggestion("Explore this project", icon: "square.stack", prompt: "Explore this project and explain its structure.")
                        suggestion("Build something", icon: "hammer", prompt: "Help me build ")
                        suggestion("Find a bug", icon: "ladybug", prompt: "Help me investigate a bug: ")
                    }.padding(.top, 12)
                }.frame(maxWidth: 660, alignment: .leading).padding(.horizontal, compactChat ? 16 : 32)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 30) {
                            ForEach(store.chat?.messages ?? []) { message in
                                MessageView(message: message).id(message.id)
                            }
                            if store.runningChat == store.chat?.id {
                                HStack(spacing: 8) { ProgressView().controlSize(.mini); Text(store.activity).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.frame(maxWidth: 740).padding(.horizontal, compactChat ? 16 : 40).padding(.vertical, 34).frame(maxWidth: .infinity)
                    }
                    .onChange(of: store.chat?.messages.last?.content) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: store.chat?.id) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            if !store.proposedEdits.filter({ $0.projectID == store.project?.id }).isEmpty {
                HStack {
                    Image(systemName: "doc.badge.gearshape").foregroundStyle(Palette.icon)
                    Text("Proposed file changes").font(.system(size: 11))
                    Spacer()
                    ForEach(store.proposedEdits.filter { $0.projectID == store.project?.id }) { edit in
                        Button(edit.path) { review = edit }.font(.system(size: 10)).lineLimit(1)
                    }
                }.padding(12).background(Palette.panel, in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)).frame(maxWidth: 740).padding(.horizontal, compactChat ? 16 : 32).padding(.bottom, 10)
            }
            composer.frame(maxWidth: 740)
                .padding(.leading, compactChat ? WorkspaceLayout.panelInset : 32)
                .padding(.trailing, shortChat ? WorkspaceLayout.panelInset : compactChat ? 0 : 32)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func suggestion(_ title: String, icon: String, prompt: String) -> some View {
        Button { if store.chat == nil { store.newChat() }; store.draft = prompt } label: {
            HStack(spacing: 7) { Image(systemName: icon).foregroundStyle(Palette.muted); Text(title) }
                .font(.system(size: 10)).padding(.horizontal, 12).padding(.vertical, 11)
                .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous).stroke(Palette.line))
        }.buttonStyle(.plain)
    }
    private var modelPicker: some View {
        Button { store.showSettings = true } label: {
            HStack(spacing: 5) {
                Text(store.model.isEmpty ? (compactChat ? "Model" : "Choose model") : store.model.components(separatedBy: "/").last!)
                    .lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 7)).foregroundStyle(Palette.icon)
            }.font(.system(size: 10)).padding(.horizontal, 14).frame(height: 30)
        }.buttonStyle(DockButtonStyle()).foregroundStyle(Palette.icon)
            .help(store.model.isEmpty ? "Choose a model" : store.model)
            .accessibilityLabel("Choose model")
            .frame(maxWidth: compactChat ? 104 : 234, alignment: .trailing)
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.attachedFile != nil {
                HStack { Label(store.fileURL?.lastPathComponent ?? "File", systemImage: "doc.text"); IconButton(icon: "xmark", help: "Remove file context") { store.attachedFile = nil } }.font(.system(size: 10)).foregroundStyle(Palette.icon)
            }
            ChatInput(text: $store.draft, enabled: store.chat != nil) { value in
                store.draft = value
                if store.runningChat == nil { store.send() }
            }.padding(.top, 3)
            HStack(spacing: compactChat ? 4 : 6) {
                IconButton(icon: "plus", help: "Attach open editor file") { store.attachedFile = store.fileText }.disabled(store.fileURL == nil)
                Button { store.allowTools.toggle() } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 13)).frame(width: 28, height: 28)
                        .foregroundStyle(store.allowTools ? Color.white : Palette.muted)
                        .background(store.allowTools ? Palette.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
                }.buttonStyle(DockButtonStyle())
                    .help(store.allowTools ? "Project tools enabled — click to disable" : "Project tools disabled — click to enable")
                    .accessibilityLabel("Project tools").accessibilityValue(store.allowTools ? "On" : "Off")
                    .accessibilityAddTraits(store.allowTools ? .isSelected : [])
                    .disabled(store.project == nil)
                Button { store.allowBrowserTools.toggle() } label: {
                    Image(systemName: "globe").font(.system(size: 13)).frame(width: 28, height: 28)
                        .foregroundStyle(store.allowBrowserTools ? Color.white : Palette.muted)
                        .background(store.allowBrowserTools ? Palette.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: Palette.cornerRadius))
                }.buttonStyle(DockButtonStyle()).help("Agent browser tools: " + (store.allowBrowserTools ? "On" : "Off") + ". Page content is sent to the selected AI model.")
                    .accessibilityLabel("Agent browser tools").accessibilityValue(store.allowBrowserTools ? "On" : "Off")
                    .disabled(store.project == nil)
                Spacer(minLength: 0)
                modelPicker
                if store.runningChat != nil {
                    Button(action: store.cancel) { Image(systemName: "stop").frame(width: 30, height: 30) }.buttonStyle(.plain).background(Palette.accentStrong, in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)).foregroundStyle(.white)
                } else {
                    Button(action: store.send) { Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold)).frame(width: 30, height: 30) }
                        .buttonStyle(.plain).background(Palette.accentStrong.opacity(store.draft.isEmpty ? 0.3 : 1), in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)).foregroundStyle(.white)
                        .keyboardShortcut(.return, modifiers: .command).disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.chat == nil)
                }
            }
        }.padding(compactChat ? 12 : 16)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
            .floatingGlass()
    }
}

struct MessageView: View {
    let message: Message
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: message.role == "user" ? "person.crop.circle" : "sparkle").foregroundStyle(Palette.icon)
                Text(message.role == "user" ? "You" : "Clara").font(.system(size: 11, weight: .semibold))
            }
            let blocks = message.content.components(separatedBy: "```")
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                if index % 2 == 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(block.components(separatedBy: "\n").first ?? "code").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            Spacer()
                            Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(block.components(separatedBy: "\n").dropFirst().joined(separator: "\n"), forType: .string) }.font(.system(size: 10)).buttonStyle(.plain)
                        }
                        ScrollView(.horizontal) { Text(block.components(separatedBy: "\n").dropFirst().joined(separator: "\n")).font(.system(size: 12, design: .monospaced)).textSelection(.enabled) }
                    }.padding(14).background(Palette.panel, in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
                } else if !block.isEmpty {
                    Text((try? AttributedString(markdown: block, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(block))
                        .font(.system(size: 13)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
