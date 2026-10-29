#!/bin/zsh
# Builds a Developer ID signed, notarized Leftover DMG for GitHub Releases and the Homebrew tap.
#
#   Scripts/release.sh                       # uses the "notary" notarytool keychain profile
#   NOTARY_PROFILE=other Scripts/release.sh
#
# Needs Local.xcconfig (see Local.xcconfig.example) and a notarytool profile, created once with:
#   xcrun notarytool store-credentials notary --apple-id <email> --team-id <TEAM_ID>
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f Local.xcconfig ]] || { echo "Local.xcconfig is missing (see Local.xcconfig.example)." >&2; exit 1; }
VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
# By SHA-1: names with non-ASCII letters (Ö) get mangled by `security`.
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | awk '{print $2}')
[[ -n "$IDENTITY" ]] || { echo "No Developer ID Application certificate found." >&2; exit 1; }

xcodegen generate --quiet
rm -rf build/release build/dmg
# Signing identity comes from Local.xcconfig. CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO keeps
# get-task-allow out, which notarization rejects.
xcodebuild -project Leftover.xcodeproj -scheme Leftover -configuration Release \
  -derivedDataPath build/release -destination 'generic/platform=macOS' \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp \
  clean build -quiet

APP=build/release/Build/Products/Release/Leftover.app
codesign --verify --strict --deep "$APP"

mkdir -p build/dmg dist
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
DMG="dist/Leftover-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Leftover" -srcfolder build/dmg -ov -format UDZO "$DMG" -quiet
codesign --sign "$IDENTITY" --timestamp "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:-notary}" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

echo "Package: $DMG"
echo "sha256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
