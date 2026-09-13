#!/usr/bin/env bash
#
# Builds "LidFold.app" from the Swift package.
#
#   Scripts/build.sh                 release build, signed
#   Scripts/build.sh --run           ...and launch it
#   Scripts/build.sh --universal     Apple silicon + Intel
#   Scripts/build.sh --debug         debug configuration
#
# Environment:
#   SIGN_IDENTITY   codesign identity (default "-", ad-hoc). macOS ties
#                   TCC grants (Screen Recording) to the signer's Team ID,
#                   and ad-hoc signatures have none, so every rebuild
#                   looks like a brand new app and loses the grant. If
#                   that gets old, sign with a real local identity
#                   instead: run `security find-identity -v -p codesigning`
#                   to see what's in your keychain, then either export
#                   SIGN_IDENTITY once in your shell profile or pass it
#                   inline, e.g. SIGN_IDENTITY="Apple Development: You (TEAMID)" Scripts/build.sh
#   APP_VERSION     override CFBundleShortVersionString
#   BUILD_NUMBER    override CFBundleVersion

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="LidFold"
BUNDLE="build/${APP_NAME}.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
CONFIG=release
RUN=false
BUILD_ARGS=()

for argument in "$@"; do
  case "$argument" in
    --universal) BUILD_ARGS+=(--arch arm64 --arch x86_64) ;;
    --run) RUN=true ;;
    --debug) CONFIG=debug ;;
    *) echo "Unknown argument: $argument" >&2; exit 1 ;;
  esac
done
BUILD_ARGS+=(-c "$CONFIG")

swift build "${BUILD_ARGS[@]}" --product LidFold
BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_PATH/LidFold" "$BUNDLE/Contents/MacOS/LidFold"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
echo -n "APPL????" > "$BUNDLE/Contents/PkgInfo"

if [ -n "${APP_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$BUNDLE/Contents/Info.plist"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$BUNDLE/Contents/Info.plist"
fi

TIMESTAMP=(--timestamp=none)
if [[ "$SIGN_IDENTITY" == "Developer ID"* ]]; then TIMESTAMP=(--timestamp); fi
codesign --force --options runtime "${TIMESTAMP[@]}" \
  --entitlements Resources/LidFold.entitlements \
  --sign "$SIGN_IDENTITY" "$BUNDLE"
codesign --verify --strict --verbose=1 "$BUNDLE"
echo "built $BUNDLE"

if $RUN; then
  pkill -x LidFold 2>/dev/null || true
  sleep 0.4
  open "$BUNDLE"
  echo "launched"
fi
