# Sourced by Clara's zsh build/test scripts. Never changes global xcode-select.
clara_toolchain_works() {
  local clara_candidate="$1" clara_sdk
  [[ -x "$clara_candidate/usr/bin/xcodebuild" ]] || return 1
  clara_sdk=$(DEVELOPER_DIR="$clara_candidate" /usr/bin/xcrun --sdk macosx --show-sdk-version 2>/dev/null) || return 1
  [[ "${clara_sdk%%.*}" == <-> ]] && (( ${clara_sdk%%.*} >= 27 ))
}

clara_select_toolchain() {
  local clara_candidate clara_selected="" clara_override="${CLARA_DEVELOPER_DIR:-${DEVELOPER_DIR:-}}"
  if [[ -n "$clara_override" ]]; then
    [[ "$clara_override" == *.app ]] && clara_override="$clara_override/Contents/Developer"
    if ! clara_toolchain_works "$clara_override"; then
      print -u2 "Clara requires full Xcode with the macOS 27 SDK or newer. The supplied developer directory is incompatible: $clara_override"
      print -u2 'Set CLARA_DEVELOPER_DIR to a compatible Xcode.app/Contents/Developer, or unset DEVELOPER_DIR to enable automatic discovery.'
      return 1
    fi
    clara_selected="$clara_override"
  else
    clara_candidate=$(/usr/bin/xcode-select -p 2>/dev/null) || clara_candidate=""
    if clara_toolchain_works "$clara_candidate"; then
      clara_selected="$clara_candidate"
    else
      for clara_candidate in /Applications/Xcode*.app/Contents/Developer(N) "$HOME"/Applications/Xcode*.app/Contents/Developer(N); do
        if clara_toolchain_works "$clara_candidate"; then clara_selected="$clara_candidate"; break; fi
      done
    fi
  fi
  if [[ -z "$clara_selected" ]]; then
    print -u2 'Clara requires full Xcode with the macOS 27 SDK or newer. Standalone Command Line Tools are insufficient.'
    print -u2 'Install compatible Xcode, launch it once to finish setup, then rerun this script. For a custom location, set CLARA_DEVELOPER_DIR.'
    return 1
  fi
  export DEVELOPER_DIR="$clara_selected"
  local clara_swift
  clara_swift=$(/usr/bin/xcrun --sdk macosx --find swift) || return 1
  export PATH="${clara_swift:h}:$PATH"
  export SDKROOT=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
  print -u2 "Using Xcode: $DEVELOPER_DIR (macOS SDK $(/usr/bin/xcrun --sdk macosx --show-sdk-version))"
}
clara_select_toolchain || return 1
