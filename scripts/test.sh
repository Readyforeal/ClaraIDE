#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build --cache-path "$PWD/.build/cache" --disable-sandbox
BIN=$(swift build --show-bin-path --cache-path "$PWD/.build/cache" --disable-sandbox)
# Swift Build (Xcode 27) emits an aggregate object and modules beside the executable.
if [[ -f "$BIN/SwiftTerm.o" ]]; then
  MODULES="$BIN"
  TERMINAL_OBJECTS=("$BIN/SwiftTerm.o")
else
  MODULES="$BIN/Modules"
  TERMINAL_OBJECTS=("$BIN"/SwiftTerm.build/*.o)
fi
swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx27.0 \
  -I "$MODULES" \
  Sources/Clara/Updates.swift Sources/Clara/Models.swift Sources/Clara/GitRepository.swift Sources/Clara/ServoIntegration.swift Sources/Clara/WorkspaceLayout.swift Sources/Clara/AgentTools.swift Sources/Clara/OpenRouter.swift Sources/Clara/Store.swift Sources/Clara/BrowserService.swift \
  Tests/WorkspaceChecks.swift "${TERMINAL_OBJECTS[@]}" -o "$BIN/WorkspaceChecks"
"$BIN/WorkspaceChecks"
