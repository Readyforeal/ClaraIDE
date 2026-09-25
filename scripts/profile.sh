#!/bin/zsh
# Repeatable synthetic UI workload; no real chats, API calls, or user terminal commands.
set -euo pipefail
cd "${0:A:h:h}"
APP="${1:-$PWD/build/Clara.app}"
[[ -x "$APP/Contents/MacOS/Clara" ]] || { echo "Build Clara first with scripts/build-app.sh" >&2; exit 1; }
mkdir -p .build/performance
RUN=$(mktemp -d "$PWD/.build/performance/run.XXXXXX")
ditto "$APP" "$RUN/Profile.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.local.clara.profiling' "$RUN/Profile.app/Contents/Info.plist"
codesign --force --deep --sign - "$RUN/Profile.app"
echo "Running isolated benchmark. Results: $RUN/metrics.json"
CLARA_PROFILE_DIRECTORY="$RUN" "$RUN/Profile.app/Contents/MacOS/Clara"
python3 - "$RUN/metrics.json" <<'PY'
import json,sys
for row in json.load(open(sys.argv[1]))['metrics']:
    print(f"{row['phase']:24s} CPU {row['cpu_s']:.3f}s  p95 main-loop interval {row['main_tick_p95_ms']:.1f}ms  >33ms {row['ticks_over_33ms']}  RSS {row['resident_mb']:.1f}MiB")
print('Timer intervals are responsiveness proxies, not displayed FPS or GPU time.')
PY
