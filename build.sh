#!/usr/bin/env bash
# Builds Slicky.app.
#
#   ./build.sh              build, sign, done
#   ./build.sh --universal  build for Apple Silicon and Intel
#   ./build.sh --release    universal + notarise + staple + zip, ready to publish
#
# Signing picks the first "Developer ID Application" identity in your keychain,
# or $SLICKY_IDENTITY if you set one. With no such identity it falls back to an
# ad-hoc signature, which is fine for running locally and useless for handing to
# anyone else.
#
# Notarising needs a stored notarytool profile, once:
#
#   xcrun notarytool store-credentials "slicky-notary" \
#       --apple-id you@example.com --team-id ABCDE12345 \
#       --password <app-specific-password>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Slicky"
BUNDLE_ID="com.slicky.desktop"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
NOTARY_PROFILE="${SLICKY_NOTARY_PROFILE:-slicky-notary}"
# Releases must be signed by this team: the updater refuses any download whose
# team identifier doesn't match the installed copy's, so signing with the wrong
# certificate would cut every existing install off from updates. Forks set
# SLICKY_TEAM_ID to their own, or to "" to skip the check.
EXPECTED_TEAM="${SLICKY_TEAM_ID-DD562F3L99}"

# The version has to match the tag being released, or the updater will see the
# new tag, install it, still report the old version, and offer it again forever.
# Tag first, then build: `git tag v1.1 && ./build.sh --release`.
VERSION="${SLICKY_VERSION:-}"
VERSION_SOURCE="SLICKY_VERSION"
if [[ -z "$VERSION" ]]; then
    VERSION="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
    VERSION_SOURCE="git tag"
fi
if [[ -z "$VERSION" ]]; then
    VERSION="0.0-dev"
    VERSION_SOURCE="fallback (no tag found)"
fi

MODE="${1:-}"
BUILD_ARGS=(-c release)
RELEASE=no
case "$MODE" in
    --universal) BUILD_ARGS+=(--arch arm64 --arch x86_64) ;;
    --release)   BUILD_ARGS+=(--arch arm64 --arch x86_64); RELEASE=yes ;;
    "")          ;;
    *)           echo "unknown option: $MODE"; exit 2 ;;
esac

identity() {
    if [[ -n "${SLICKY_IDENTITY:-}" ]]; then
        echo "$SLICKY_IDENTITY"
        return
    fi
    # No match is a normal outcome, not a failure: swallow it so `set -e`
    # doesn't take the whole script down with it.
    security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" \
        | head -1 \
        | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+[A-F0-9]+[[:space:]]+"(.*)"$/\1/' \
        || true
}

IDENTITY="$(identity || true)"

if [[ "$RELEASE" == yes && "$VERSION_SOURCE" == fallback* ]]; then
    echo "✗ --release needs a real version number, and there's no tag to take one from."
    echo "  Tag the commit first:  git tag v1.1"
    echo "  Or state it outright:  SLICKY_VERSION=1.1 ./build.sh --release"
    exit 1
fi

if [[ "$RELEASE" == yes && -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]]; then
    echo "⚠ working tree has uncommitted changes — the release won't match the tag"
fi

if [[ "$RELEASE" == yes && -z "$IDENTITY" ]]; then
    echo "✗ --release needs a Developer ID Application certificate."
    echo "  Create one at developer.apple.com → Certificates → + → Developer ID Application,"
    echo "  download it, double-click to install, then run this again."
    exit 1
fi

echo "▸ Slicky $VERSION (from $VERSION_SOURCE)"
echo "▸ Compiling…"
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/$APP_NAME"

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Slicky</string>
</dict>
</plist>
PLIST

echo "▸ Rendering app icon…"
RAW="$(mktemp -d)/raw"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
if "$APP/Contents/MacOS/$APP_NAME" --export-icon "$RAW"; then
    cp "$RAW/icon_16.png"   "$ICONSET/icon_16x16.png"
    cp "$RAW/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
    cp "$RAW/icon_32.png"   "$ICONSET/icon_32x32.png"
    cp "$RAW/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
    cp "$RAW/icon_128.png"  "$ICONSET/icon_128x128.png"
    cp "$RAW/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
    cp "$RAW/icon_256.png"  "$ICONSET/icon_256x256.png"
    cp "$RAW/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
    cp "$RAW/icon_512.png"  "$ICONSET/icon_512x512.png"
    cp "$RAW/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
    echo "  (icon render skipped)"
fi

if [[ -n "$IDENTITY" ]]; then
    echo "▸ Signing as: $IDENTITY"
    # Hardened runtime is required for notarisation. Slicky needs no
    # entitlements: Accessibility and Downloads access are granted by the user
    # through TCC, not by the bundle.
    codesign --force --options runtime --timestamp \
             --sign "$IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /' || true
    TEAM="$(codesign -dvvv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p' || true)"
    echo "  team identifier: ${TEAM:-none}"

    if [[ -n "$EXPECTED_TEAM" && "$TEAM" != "$EXPECTED_TEAM" ]]; then
        echo "✗ signed by team '${TEAM:-none}', expected '$EXPECTED_TEAM'."
        echo "  That certificate would orphan every existing install: the updater"
        echo "  only accepts downloads signed by the same team it is running as."
        echo "  Use a Developer ID Application certificate for $EXPECTED_TEAM, or"
        echo "  set SLICKY_TEAM_ID to the team you mean to release under."
        [[ "$RELEASE" == yes ]] && exit 1
        echo "  (continuing — this is not a --release build)"
    fi
else
    echo "▸ Signing ad-hoc (no Developer ID certificate found)"
    codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
        || echo "  (codesign failed — the app still runs locally)"
fi

if [[ "$RELEASE" == yes ]]; then
    echo "▸ Notarising (this takes a few minutes)…"
    UPLOAD="$DIST/$APP_NAME-notarize.zip"
    rm -f "$UPLOAD"
    ditto -c -k --keepParent "$APP" "$UPLOAD"
    xcrun notarytool submit "$UPLOAD" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$UPLOAD"

    echo "▸ Stapling…"
    xcrun stapler staple "$APP"

    echo "▸ Zipping for release…"
    rm -f "$DIST/$APP_NAME.zip"
    ditto -c -k --keepParent "$APP" "$DIST/$APP_NAME.zip"

    echo "▸ Gatekeeper says:"
    spctl -a -vvv "$APP" 2>&1 | sed 's/^/  /' || true
    echo "✓ $DIST/$APP_NAME.zip is ready to attach to a release"
else
    # spctl prints the verdict first and the origin last; show the verdict and
    # the reason, or "rejected" alone reads as though signing failed.
    spctl -a -vv "$APP" 2>&1 | head -2 | sed 's/^/  gatekeeper: /' || true
    if [[ -n "$IDENTITY" ]]; then
        echo "  (unnotarized is expected here — ./build.sh --release notarises)"
    fi
fi

echo "✓ Built $APP"
