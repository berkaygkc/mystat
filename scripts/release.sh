#!/bin/bash
# Builds a signed, notarized and stapled mystat.app and DMG for a GitHub release.
# Usage: scripts/release.sh
#
# Needs a "Developer ID Application" certificate and a notarytool keychain profile (default name: mystat-notary):
#   xcrun notarytool store-credentials mystat-notary --apple-id <Apple ID> --team-id <Team ID>
# You'll be asked for an app-specific password (appleid.apple.com → Sign-In and Security → App-Specific Passwords).
#
# Notarization runs twice: first the app (so a copy dragged out of the DMG opens offline too), then the DMG built from
# the stapled app.
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE="${NOTARY_PROFILE:-mystat-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP="build/mystat.app"
DMG="build/mystat-$VERSION.dmg"

fail() { echo "error: $*" >&2; exit 1; }

# Preflight: certificate, notary profile, clean tree, green tests.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Developer ID Application' | sed -E 's/.*"(.*)"/\1/' || true)"
[ -n "$IDENTITY" ] || fail "no Developer ID Application certificate in the keychain"
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    fail "no notarytool profile \"$PROFILE\"; create it with:
  xcrun notarytool store-credentials $PROFILE --apple-id <Apple ID> --team-id <Team ID>"
fi
[ -z "$(git status --porcelain --untracked-files=no)" ] || fail "uncommitted changes; commit or stash them first"
# SwiftPM compiles every file under Sources/ and make-app.sh copies Locales/ and Resources/: untracked files there would ship.
UNTRACKED="$(git ls-files --others --exclude-standard -- Sources Locales Resources Package.swift)"
[ -z "$UNTRACKED" ] || fail "untracked files would be built into the app:
$UNTRACKED"
echo "Running tests…"
mkdir -p build
swift test >build/release-tests.log 2>&1 || fail "tests failed (see build/release-tests.log)"

# Submits a file and waits; stops unless Apple accepts it.
notarize() {
    local out id
    echo "Notarizing $(basename "$1")…"
    out="$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1)" || true
    # Here-strings, not pipes: under pipefail a grep with no match would end the script before the error is shown.
    id="$(awk '/^ *id:/ { print $2; exit }' <<< "$out")"
    if ! grep -q 'status: Accepted' <<< "$out"; then
        echo "$out" >&2
        fail "notarization was not accepted${id:+; details: xcrun notarytool log $id --keychain-profile $PROFILE}"
    fi
    echo "  id: $id"
    echo "  status: Accepted"
}

# 1. The app.
scripts/make-app.sh release
ZIP="build/mystat-$VERSION-app.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"
rm -f "$ZIP"
xcrun stapler staple -q "$APP"

# 2. The DMG: the stapled app and a shortcut to /Applications.
STAGE="build/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname mystat -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple -q "$DMG"

# 3. Verify the way Gatekeeper will.
spctl -a -vv "$APP" 2>&1 | sed 's/^/  /'
spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | sed 's/^/  /'
xcrun stapler validate -q "$APP" && xcrun stapler validate -q "$DMG" || fail "stapled ticket missing"
(cd build && shasum -a 256 "mystat-$VERSION.dmg" > "mystat-$VERSION.dmg.sha256")
echo "Ready: $DMG ($(du -h "$DMG" | cut -f1)), $(cut -d' ' -f1 "$DMG.sha256")"
