#!/bin/zsh
# Builds DocMark.app into ./build. Usage: scripts/build-app.sh [debug|release] [--open|--install]
#   --install  copies the app to /Applications, where Finder's Open With finds it,
#              and links the dm command into ~/.local/bin
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/DocMark.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/DocMark"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DocMark"
[[ "$CONFIG" == release ]] && strip -x "$APP/Contents/MacOS/DocMark"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/dm "$APP/Contents/Resources/dm"

# Ad-hoc signature so macOS runs it locally without Gatekeeper prompts.
codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP ($(du -sh "$APP" | cut -f1))"

if [[ "${2:-}" == "--install" ]]; then
    # Quit normally so open documents can save, and stop if something keeps the app open.
    if pgrep -x DocMark >/dev/null; then
        osascript -e 'tell application "DocMark" to quit'
        sleep 1
        if pgrep -x DocMark >/dev/null; then
            echo "DocMark is still running, so it was not installed. Close it and run this again." >&2
            exit 1
        fi
    fi
    rm -rf /Applications/DocMark.app
    cp -R "$APP" /Applications/DocMark.app
    "$LSREGISTER" -f /Applications/DocMark.app
    mkdir -p ~/.local/bin
    ln -sf /Applications/DocMark.app/Contents/Resources/dm ~/.local/bin/dm
    echo "Installed /Applications/DocMark.app and ~/.local/bin/dm"
elif [[ "${2:-}" == "--open" ]]; then
    open "$APP"
fi
exit 0
