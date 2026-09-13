#!/usr/bin/env bash
#
# Builds LidFold and packages it into a distributable .dmg, for attaching
# to a GitHub Release.
#
#   Scripts/package-dmg.sh              builds first, then packages
#   Scripts/package-dmg.sh --no-build   packages the existing build/LidFold.app
#
# Output: dist/LidFold.dmg
#
# The filename is deliberately version-less: the README's download button
# links straight to
#   .../releases/latest/download/LidFold.dmg
# which only keeps working if every release attaches an asset with this
# exact name. After running this, create a release on GitHub (Releases ->
# Draft a new release), tag it e.g. v1.0.0, and attach dist/LidFold.dmg.

set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE="build/LidFold.app"
DO_BUILD=true

for argument in "$@"; do
  case "$argument" in
    --no-build) DO_BUILD=false ;;
    *) echo "Unknown argument: $argument" >&2; exit 1 ;;
  esac
done

if $DO_BUILD; then
  Scripts/build.sh
fi

[ -d "$BUNDLE" ] || { echo "error: $BUNDLE not found; run Scripts/build.sh first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$BUNDLE/Contents/Info.plist")"
DIST_DIR="dist"
STAGING="$DIST_DIR/staging"
DMG_PATH="$DIST_DIR/LidFold.dmg"

rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "LidFold" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING"

echo "packaged $DMG_PATH (from version $VERSION)"
echo "next: create a GitHub release tagged v${VERSION} and attach dist/LidFold.dmg"
