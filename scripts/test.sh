#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swift build --cache-path "$PWD/.build/cache" --disable-sandbox
BIN=$(swift build --show-bin-path --cache-path "$PWD/.build/cache" --disable-sandbox)
swiftc -parse-as-library -swift-version 5 -target arm64-apple-macosx27.0 \
  -I "$BIN/Modules" \
  Sources/Clara/Updates.swift Sources/Clara/Models.swift Sources/Clara/GitRepository.swift Sources/Clara/ServoIntegration.swift Sources/Clara/WorkspaceLayout.swift Sources/Clara/OpenRouter.swift Sources/Clara/Store.swift Sources/Clara/BrowserService.swift \
  Tests/WorkspaceChecks.swift "$BIN"/SwiftTerm.build/*.o -o "$BIN/WorkspaceChecks"
"$BIN/WorkspaceChecks"
