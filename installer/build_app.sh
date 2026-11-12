#!/bin/bash
# Build Trellis Reverse.app -> DMG + pkg, optionally install to /Applications.
# All system tools are called by absolute path: WorkBuddy proxies a set of basic
# commands to toybox, whose grep/sed/find behaviour differs from BSD.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/.dist"
APP="$DIST/Trellis Reverse.app"
CONTENTS="$APP/Contents"
RES="$CONTENTS/Resources"
STAGE="$DIST/dmg-stage"
VERSION="1.0.0"
DMG="$DIST/TrellisReverse-$VERSION.dmg"
PKG="$DIST/TrellisReverse-$VERSION.pkg"
SRCZIP_NAME="TrellisReverse-源码与证据.zip"
DOWNLOADS="$HOME/Downloads"

echo "==> 1/8  release build"
swift build --package-path "$ROOT/app" -c release --disable-sandbox
BIN="$ROOT/app/.build/release"
test -x "$BIN/TrellisStudio" || { echo "missing TrellisStudio binary"; exit 1; }
test -x "$BIN/trellis-probe" || { echo "missing trellis-probe binary"; exit 1; }

echo "==> 2/8  icon"
ICONSET="$DIST/AppIcon.iconset"
if [ -d "$ICONSET" ]; then /bin/rm -rf "$ICONSET"; fi
python3 "$ROOT/installer/make_icon.py" "$ICONSET"
/usr/bin/iconutil -c icns "$ICONSET" -o "$DIST/AppIcon.icns"

echo "==> 3/8  assemble .app"
if [ -d "$APP" ]; then /bin/rm -rf "$APP"; fi
/bin/mkdir -p "$CONTENTS/MacOS" "$RES/Simulator" "$RES/Source" "$RES/Docs"
/bin/cp "$BIN/TrellisStudio" "$CONTENTS/MacOS/TrellisStudio"
/bin/cp "$BIN/trellis-probe" "$CONTENTS/MacOS/trellis-probe"
/bin/cp "$ROOT/installer/Info.plist" "$CONTENTS/Info.plist"
/bin/cp "$DIST/AppIcon.icns" "$RES/AppIcon.icns"
/bin/cp "$ROOT/installer/INSTALL.md" "$RES/安装说明.md"
/bin/cp "$ROOT/sim/index.html" "$RES/Simulator/index.html"
/usr/bin/rsync -a --exclude '.build' --exclude '.git' --exclude '.dist' \
    "$ROOT/app/" "$RES/Source/app/"
for d in capture checks investigation.cany inbox; do
    /usr/bin/rsync -a "$ROOT/$d/" "$RES/Source/$d/"
done
/bin/cp "$ROOT/README.md" "$ROOT/NOTICE.md" "$ROOT/craft.json" "$RES/Source/"
/bin/cp "$ROOT/README.md" "$ROOT/NOTICE.md" "$RES/Docs/"
/usr/bin/plutil -lint "$CONTENTS/Info.plist"

echo "==> 4/8  ad-hoc sign + verify"
/usr/bin/codesign --force --deep --sign - --identifier app.trellisreverse.studio "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=1 "$APP" 2>&1

echo "==> 5/8  DMG stage"
if [ -d "$STAGE" ]; then /bin/rm -rf "$STAGE"; fi
/bin/mkdir -p "$STAGE"
/bin/cp -R "$APP" "$STAGE/"
/bin/ln -s /Applications "$STAGE/Applications"
/bin/cp "$ROOT/installer/INSTALL.md" "$STAGE/安装说明.txt"
(
    cd "$ROOT"
    if [ -f "$STAGE/$SRCZIP_NAME" ]; then /bin/rm -f "$STAGE/$SRCZIP_NAME"; fi
    # Explicit allow-list: guarantees .build / .git / .dist never leak in.
    /usr/bin/zip -q -r "$STAGE/$SRCZIP_NAME" \
        README.md NOTICE.md craft.json capture checks investigation.cany inbox \
        sim installer app/Package.swift app/Sources app/Tests
)
{
    echo "Trellis Reverse $VERSION — 组件 SHA-256"
    echo "生成时间: $(/bin/date '+%Y-%m-%d %H:%M:%S %z')"
    echo "主程序架构: $(/usr/bin/file -b "$CONTENTS/MacOS/TrellisStudio")"
    echo ""
    for f in "$CONTENTS/MacOS/TrellisStudio" "$CONTENTS/MacOS/trellis-probe" \
             "$RES/Simulator/index.html" "$STAGE/$SRCZIP_NAME"; do
        echo "$(/usr/bin/shasum -a 256 "$f" | /usr/bin/awk '{print $1}')  $(basename "$f")"
    done
    echo ""
    echo "DMG 自身的 SHA-256 见 ~/Downloads/TrellisReverse-$VERSION.dmg.sha256（DMG 生成后无法回写自身内容）。"
} > "$STAGE/校验信息.txt"

echo "==> 6/8  DMG + pkg"
if [ -f "$DMG" ]; then /bin/rm -f "$DMG"; fi
/usr/bin/hdiutil create -volname "Trellis Reverse" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG"
if [ -f "$PKG" ]; then /bin/rm -f "$PKG"; fi
/usr/bin/pkgbuild --component "$APP" --install-location /Applications \
    --identifier app.trellisreverse.studio.pkg --version "$VERSION" "$PKG"

echo "==> 7/8  copy to ~/Downloads"
/bin/cp "$DMG" "$DOWNLOADS/$(basename "$DMG")"
/bin/cp "$PKG" "$DOWNLOADS/$(basename "$PKG")"
/usr/bin/shasum -a 256 "$DMG" | /usr/bin/awk '{print $1"  '"$(basename "$DMG")"'"}' \
    > "$DOWNLOADS/TrellisReverse-$VERSION.dmg.sha256"
/bin/cp "$STAGE/校验信息.txt" "$DOWNLOADS/TrellisReverse-校验信息.txt"

echo "==> 8/8  install to /Applications (only with --install)"
if [ "${1:-}" = "--install" ]; then
    if [ -d "/Applications/Trellis Reverse.app" ]; then
        /bin/mv "/Applications/Trellis Reverse.app" \
            "/tmp/Trellis Reverse.app.bak.$(/bin/date +%s)"
    fi
    /bin/cp -R "$APP" "/Applications/Trellis Reverse.app"
    echo "installed: /Applications/Trellis Reverse.app"
else
    echo "skipped (pass --install to install)"
fi

echo ""
echo "DONE"
echo "  app : $APP"
echo "  dmg : $DOWNLOADS/$(basename "$DMG")  ($(/usr/bin/du -h "$DMG" | /usr/bin/awk '{print $1}'))"
echo "  pkg : $DOWNLOADS/$(basename "$PKG")  ($(/usr/bin/du -h "$PKG" | /usr/bin/awk '{print $1}'))"
/usr/bin/codesign -dv --verbose=2 "$APP" 2>&1 | /usr/bin/grep -E 'Identifier|Signature|TeamIdentifier' || true
