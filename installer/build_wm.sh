#!/bin/bash
# Build Trellis WM.app (menu-bar tiling agent), optionally install to /Applications.
# All system tools are called by absolute path: WorkBuddy proxies a set of basic
# commands to toybox, whose grep/sed/find behaviour differs from BSD.
# bash 3.2 compatible: no associative arrays.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/.dist/wm"
APP="$DIST/Trellis WM.app"
CONTENTS="$APP/Contents"
RES="$CONTENTS/Resources"
VERSION="0.1.0"
INSTALL_PATH="/Applications/Trellis WM.app"

echo "==> 1/5  release build"
swift build --package-path "$ROOT/app" -c release --product TrellisWM --disable-sandbox
BIN="$ROOT/app/.build/release"
test -x "$BIN/TrellisWM" || { echo "missing TrellisWM binary"; exit 1; }

echo "==> 2/5  icon"
ICONSET="$DIST/AppIcon.iconset"
/bin/mkdir -p "$DIST"
if [ -d "$ICONSET" ]; then /bin/rm -rf "$ICONSET"; fi
python3 "$ROOT/installer/make_icon.py" --style wm "$ICONSET"
/usr/bin/iconutil -c icns "$ICONSET" -o "$DIST/AppIcon.icns"

echo "==> 3/5  assemble .app"
if [ -d "$APP" ]; then /bin/rm -rf "$APP"; fi
/bin/mkdir -p "$CONTENTS/MacOS" "$RES/Docs"
/bin/cp "$BIN/TrellisWM" "$CONTENTS/MacOS/TrellisWM"
/bin/cp "$ROOT/installer/Info-WM.plist" "$CONTENTS/Info.plist"
/bin/cp "$DIST/AppIcon.icns" "$RES/AppIcon.icns"
/bin/cp "$ROOT/installer/INSTALL-WM.md" "$RES/Docs/INSTALL.md"
/bin/cp "$ROOT/README.md" "$ROOT/NOTICE.md" "$RES/Docs/"
/usr/bin/plutil -lint "$CONTENTS/Info.plist"

echo "==> 4/5  ad-hoc sign + verify"
/usr/bin/codesign --force --deep --sign - --identifier app.trellisreverse.wm "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=1 "$APP" 2>&1

echo "==> 5/5  install to /Applications (only with --install)"
if [ "${1:-}" = "--install" ]; then
    if [ -d "$INSTALL_PATH" ]; then
        BACKUP="$HOME/Trellis WM.app.bak.$(/bin/date +%s)"
        /bin/mv "$INSTALL_PATH" "$BACKUP"
        echo "backed up previous app to $BACKUP"
    fi
    /bin/cp -R "$APP" "$INSTALL_PATH"
    echo "installed: $INSTALL_PATH"
else
    echo "skipped (pass --install to install)"
fi

echo ""
echo "DONE"
echo "  app : $APP"
/usr/bin/codesign -dv --verbose=2 "$APP" 2>&1 | /usr/bin/grep -E 'Identifier|Signature|TeamIdentifier' || true
echo "  Info.plist:"
/usr/bin/plutil -p "$CONTENTS/Info.plist" | /usr/bin/grep -E 'CFBundleIdentifier|CFBundleName|CFBundleExecutable|CFBundleDisplayName|LSUIElement|CFBundleShortVersionString' || true
