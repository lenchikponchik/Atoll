#!/bin/zsh
# Builds a personal Atoll release for friends: a DMG with the app and install
# notes, plus a source archive of the current branch (required by GPL v3).
#
# The app copy gets its own bundle id and version and has Sparkle's feed
# removed, so it never "updates" itself to the official Atoll and does not
# clash with an official install. It is signed with the Apple Development
# identity (not notarized): friends allow it once in Privacy & Security.
#
# Usage: scripts/build-friends-release.sh [build-number]   (default: 1)

set -euo pipefail

BUILD_NUMBER="${1:-1}"
SIGN_IDENTITY="Apple Development: leosplin@mail.ru (WQ6XBMB29B)"
TEAM_ID="97XD7LKWUR"
BUNDLE_ID="com.leosp.Atoll"
BASE_VERSION="$(tr -d '[:space:]' < VERSION)"
VERSION="${BASE_VERSION}-leosp.${BUILD_NUMBER}"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Build and stage outside ~/Desktop: Finder metadata there breaks codesign
WORK_DIR="$HOME/Library/Developer/Xcode/DerivedData/Atoll-local"
STAGE_DIR="$WORK_DIR/friends-release"
OUT_DIR="$REPO_DIR/../release"

cd "$REPO_DIR"

echo "==> Building Release"
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Release \
    -derivedDataPath "$WORK_DIR" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" PROVISIONING_PROFILE_SPECIFIER="" \
    build | grep -E 'error:|BUILD (SUCCEEDED|FAILED)'

echo "==> Preparing app copy ($BUNDLE_ID $VERSION)"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/dmg"
APP="$STAGE_DIR/dmg/Atoll.app"
ditto "$WORK_DIR/Build/Products/Release/Atoll.app" "$APP"

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$PLIST"
/usr/libexec/PlistBuddy -c "Delete :SUEnableAutomaticChecks" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool false" "$PLIST"

echo "==> Re-signing"
ENTITLEMENTS="$STAGE_DIR/entitlements.plist"
codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS"
xattr -cr "$APP"
# Nested frameworks keep their signatures; only the outer bundle changed
codesign --force --sign "$SIGN_IDENTITY" --options runtime \
    --entitlements "$ENTITLEMENTS" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Packaging DMG"
ln -s /Applications "$STAGE_DIR/dmg/Applications"
cp "$REPO_DIR/scripts/friends-install-notes.txt" "$STAGE_DIR/dmg/Как установить.txt"
mkdir -p "$OUT_DIR"
DMG="$OUT_DIR/Atoll-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Atoll $VERSION" -srcfolder "$STAGE_DIR/dmg" \
    -ov -format UDZO "$DMG" > /dev/null

echo "==> Archiving source"
SOURCE_ZIP="$OUT_DIR/Atoll-$VERSION-source.zip"
git archive --format=zip --prefix="Atoll-$VERSION/" -o "$SOURCE_ZIP" HEAD

echo "==> Done"
ls -lh "$DMG" "$SOURCE_ZIP"
