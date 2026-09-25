# Clara

A chat-first native macOS coding workspace, built with SwiftUI, AppKit, and SwiftTerm.

## Run

Requires macOS 27 or later and Swift 6.0+ command line tools (or Xcode).

```sh
./scripts/build-app.sh
open build/Clara.app
```

The SwiftTerm source is vendored, so building does not require downloading packages. The build script creates a locally ad-hoc signed app, not a notarized distribution release. Open `Package.swift` in Xcode to work on the app there.

## Use

1. Open a project folder with the **+** beside Projects or ⇧⌘O.
2. Open Settings (⌘,) and enter your OpenRouter API key. Refresh the model catalog or enter any OpenRouter model ID. Save.
3. Start a conversation. ⌘Return sends; the stop button cancels streaming.
4. Enable **Project tools** for models supporting function calling. The model can list/read files and propose whole-file changes. Review the current/proposed contents and apply or reject each proposal. Disable tools for models without function calling.
5. Use ⇧⌘T for a native zsh terminal. Run `ssh user@host`, vim, and ordinary terminal programs here. Minimize with the minus button; sessions remain alive in the bottom tabs until closed or the app quits.
6. Use ⇧⌘E for the independent floating file navigator. Opening a file reveals a separate full-height editor alongside it. Minus minimizes that editor into a rounded file tile; opening another file preserves the earlier buffer. Click a tile to restore it, or close a file with × (unsaved changes prompt before closing). Save with ⌘S. **Add to chat** attaches the current text to the next message.

## Included

- Persistent local projects, conversations, selected model, and messages.
- Collapsible project sidebar with a text-only Clara header and outline icons. Opening a file automatically collapses Projects; the chat becomes a compact left column beside the navigator and editor. Toggle Projects beside the traffic lights or with ⌃⌘S.
- Chat width adapts to the navigator, keeping the conversation visible.
- Nearly black chat-first workspace with a wallpaper-blending glass sidebar, native Liquid Glass panels, spring docking animations, and Reduce Motion support.
- Borderless dock areas: full-height terminals shrink into floating bottom tabs; independent file editors shrink into a vertical dock beside the file navigator.
- Multiple unsaved file buffers remain available across minimizing, restoring, and project switching.
- OpenRouter streaming, cancellation, errors, live searchable model catalog, custom model IDs.
- API key stored in macOS Keychain; no intermediate backend.
- Project-scoped file tools, symlink/path traversal checks, up to 12 tool rounds per turn.
- Review before model file writes; conflict checks against external edits.
- Real native pseudo-terminal sessions, including SSH support, ANSI colors and terminal programs, powered by SwiftTerm.
- AppKit text editor with undo, simple syntax coloring, plain-text validation, and unsaved-change prompts.

## Current boundaries

This is a first usable implementation, not a complete Codex replacement. The assistant reads files and proposes edits but does not execute commands or run tests autonomously. Terminals are user controlled. There is no LSP, autocomplete, Git diff integration, cross-file search, multi-file editor tabs, image input, or remote project filesystem. File browsing omits hidden files. The text editor supports UTF-8 files up to 1 MB and uses lightweight highlighting rather than a language parser. Panels adapt to the chat viewport; the file navigator has a fixed width. Editor buffers and undo history last for the current app session. One generation can run at a time. Terminal sessions and unapplied proposals last for the current app session; saved chats/projects survive restarts.

Existing projects and chats migrate from the old Obsidian workspace on first launch. The legacy Keychain service identifier is retained to keep your saved API key.

Chats are saved in `~/Library/Application Support/Clara/workspace.json`. The app is intentionally not sandboxed so the shell can operate on your projects. Project tools send requested file contents to OpenRouter and its selected provider. API usage is billed to your OpenRouter account. The model catalog can include non-chat models; use a chat-completion compatible model. Tool support varies by model.

## Checks

```sh
./scripts/test.sh
```

Tests cover project path boundaries (including symlinks), binary/large-file rejection, persisted conversation state, and conflict-safe file writes. Live OpenRouter requests require your API key and are not part of automated tests.

The standalone check runner works with Apple's Command Line Tools. The equivalent XCTest suite in `Tests/ClaraTests` can be run with `swift test` when a full Xcode installation is selected.

## Source map

- `ClaraApp.swift`: native app lifecycle, menu shortcuts, visual palette.
- `WorkspaceView.swift`: sidebar, conversation, composer, overlay docks.
- `Store.swift`: workspace state, model tool loop, file operations, terminal lifetime.
- `OpenRouter.swift`: streaming API, tool-call assembly, model catalog, Keychain.
- `EditorView.swift`: native text editor, independent file navigator, terminal bridge, proposal review.
- `FloatingWorkspace.swift`: panel geometry, terminal tabs, file docks, spring transitions.
- `Glass.swift`: native Liquid Glass, wallpaper blur, full-window content configuration.
- `Models.swift`: persisted models and project file boundaries.

OpenRouter API reference: https://openrouter.ai/docs/api/api-reference/chat/send-chat-completion-request

SwiftTerm is MIT licensed, vendored from tag `v1.10.1` (commit `5c83a9d214e7354697624c11deb4e488bdcfabad`). See `Vendor/SwiftTerm/LICENSE`. Its terminal library is compiled directly as a local target; the upstream example tools and their dependencies are not used.


## Browser and conversation controls

Hover a conversation to reveal Delete. Overflowing titles scroll slowly while hovered, with a fading edge. Undo the most recent deletion from the sidebar or Workspace menu; deletion undo lasts for the app session.

The globe dock at bottom-right opens a native WebKit browser (also ⇧⌘B). Each project has its own session-only website data; minimizing keeps the page alive. Enter an HTTP(S) URL, including `http://localhost:PORT` for local previews. Back, forward, reload, and minimize controls are included.

Enable the globe icon in the chat composer to give the selected model browser tools, independently of project file tools. The agent can navigate, read page text and indexed elements, and request clicks or field entry. Browser content is sent to your selected OpenRouter model. Clicks and text entry require an in-app approval showing the destination and target. Password/file inputs are excluded. Browser tools return text, not screenshots; cross-origin iframe automation, downloads, and persistent browser profiles are not implemented. Live model-driven browser use requires your OpenRouter key and a tool-capable model.

## Distribution and updates

See [release instructions](docs/RELEASING.md) for Developer ID signing, notarized DMGs, and GitHub releases. Clara → **Check for Updates…** checks published releases and opens the new installer; it does not pull or execute source changes. Current builds require Apple silicon and macOS 27+.

## Terminal snapping and chat input

New terminals open across the workspace. Drag the terminal title bar down at least 48 points to snap to the bottom half, or right to snap to the right half. Chat resizes into the space above or beside it. Drag up or left to return to full workspace, or use the terminal's layout menu. Each terminal remembers its position while minimized during the app session; terminals remain live when docked. One terminal is expanded at a time.

Terminal and editor content now share a continuous dark-tinted Liquid Glass surface with their controls, without an opaque inner panel. Programs that explicitly paint terminal background colors can still use those colors.

In the composer, **Enter** sends, **Shift+Enter** inserts a new line, and **Command+Enter** also sends. Sending does not require leaving the input first. Text composition through an input method is allowed to finish before Enter sends a message.

Terminal and editor slabs use translucent, dark-tinted glass with in-window backdrop blur. The native backdrop supplies the chat blur without a second full-chat blur pass. The file navigator and minimized file dock use the same dark backdrop material. The composer floats above the message scroll view, uses an 800-point maximum width beside the 740-point message lane, and masks message content to transparent at its bottom edge. Scroll padding tracks composer height so the latest message can still be read above it.

## Performance profiling

Run `./scripts/profile.sh` after building to exercise an isolated synthetic workspace without touching your chats or making API calls. See [the profiling report](docs/PERFORMANCE.md) for measurements, retained optimizations, and remaining bottlenecks.

Servo integration reads the live `Servo/sites.json` manifest, including `.test` names and HTTPS addresses, instead of guessing a URL from a port. Running-site records expire after 20 seconds without a heartbeat. Opening the browser refreshes discovery; `.test` names default to HTTP.

## Clara Peek

Clara includes its own notch companion—no separate app or installation. A small icon sits just left of the camera housing; hover briefly to expand a pure-black chat panel. It uses the same selected project, conversation, draft, and model as the main window. Pick another project/chat, send a message, or open the full workspace. Clicking into the composer/terminal pins the panel; Escape or the collapse button tucks it away. Project menus stay open while you choose an item.

The terminal button opens a separate temporary shell in the selected project folder. Each project's Peek shell survives collapse and project switches. Its close button ends that shell; quitting Clara ends all Peek shells. They are not saved between launches or added to the main terminal dock.

Use **Workspace → Enable Clara Peek** to turn it off/on, or **Show Clara Peek** (`⌥⌘P`, while Clara is active). Notched displays use the system-reported housing geometry; other displays get a centered top-edge tab. Display changes reposition the panel, and Reduce Motion is respected. Hover doesn't activate Clara or steal keyboard focus. Only the latest 30 messages are rendered in Peek; the full history remains in the main workspace. Peek stays available while Clara is running.
