#!/bin/sh
# Builds Radio in Release configuration, code-signs it with the Developer ID Application
# identity, packages it into a DMG under build/, then notarizes and staples it.
#
# Requires:
#   - a "Developer ID Application" certificate in this Mac's keychain. Check with
#     `security find-identity -v -p codesigning`; the IDENTITY string below must match.
#   - a notarytool keychain profile named "radio-notary":
#       xcrun notarytool store-credentials radio-notary \
#         --apple-id you@example.com --team-id VL4Z3W8N24 \
#         --password <app-specific-password>   # from appleid.apple.com
#
# Adapted from ~/Developer/Leaf/scripts/make_dmg.sh. The Sparkle-specific handling is
# guarded on the framework being present, so this works both before and after Radio
# adopts Sparkle.
set -eu

cd "$(dirname "$0")/.."

BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_NAME="Radio"
IDENTITY="Developer ID Application: Jonny Garrill (VL4Z3W8N24)"
NOTARY_PROFILE="radio-notary"

# Build number: monotonic git commit count, injected as CFBundleVersion (Info.plist maps
# CFBundleVersion -> $(CURRENT_PROJECT_VERSION)). Falls back to 1 outside a git checkout.
if git rev-parse --git-dir >/dev/null 2>&1; then
	BUILD_NUMBER=$(git rev-list --count HEAD)
else
	BUILD_NUMBER=1
fi

rm -rf "$DERIVED_DATA"

xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
	-derivedDataPath "$DERIVED_DATA" \
	CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
	build

APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
	echo "error: built app not found at $APP_PATH" >&2
	exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
echo "Packaging $APP_NAME $VERSION (build $BUILD_NUMBER)"

# `xcodebuild build` (vs archive/install) never runs Xcode's install-time strip, so the
# executable still carries its full symbol table. -rSTx drops debug + local symbols while
# keeping dynamically-referenced ones (safe for @objc/AppKit interop). The build's
# dwarf-with-dsym Radio.app.dSYM is untouched, so crash symbolication still works —
# archive it per release (roadmap: "Keep every dSYM").
strip -rSTx "$APP_PATH/Contents/MacOS/$APP_NAME"

DSYM_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app.dSYM"
if [ -d "$DSYM_PATH" ]; then
	cp -R "$DSYM_PATH" "$BUILD_DIR/$APP_NAME-$VERSION-$BUILD_NUMBER.dSYM"
	echo "Saved $BUILD_DIR/$APP_NAME-$VERSION-$BUILD_NUMBER.dSYM"
fi

# --- Sparkle: only runs once the framework is embedded -------------------------------
SPARKLE_FW="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
	SPARKLE_VER="$SPARKLE_FW/Versions/B"

	# Sparkle ships ~36 .lproj translations of its updater UI; Radio is English-only.
	find "$SPARKLE_VER/Resources" -maxdepth 1 -name '*.lproj' \
		! -name 'en.lproj' ! -name 'Base.lproj' -exec rm -rf {} +

	# If the app is built arm64-only, thin Sparkle's fat Mach-Os to match (dead x86_64
	# weight otherwise). Left universal when the app is universal.
	APP_ARCHS=$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME" 2>/dev/null || echo "")
	if [ "$APP_ARCHS" = "arm64" ]; then
		for macho in \
			"$SPARKLE_VER/Sparkle" \
			"$SPARKLE_VER/Autoupdate" \
			"$SPARKLE_VER/Updater.app/Contents/MacOS/Updater" \
			"$SPARKLE_VER/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
			"$SPARKLE_VER/XPCServices/Installer.xpc/Contents/MacOS/Installer"; do
			if lipo -archs "$macho" 2>/dev/null | grep -qw x86_64; then
				lipo "$macho" -thin arm64 -output "$macho"
			fi
		done
	fi

	# Xcode's Automatic-signing embed phase does not reliably re-sign Sparkle's prebuilt
	# nested helpers. Re-sign innermost first, with hardened runtime and a secure timestamp.
	codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPARKLE_VER/Autoupdate"
	codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPARKLE_VER/XPCServices/Downloader.xpc"
	codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPARKLE_VER/XPCServices/Installer.xpc"
	codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPARKLE_VER/Updater.app"
	codesign --force --options runtime --timestamp --sign "$IDENTITY" "$SPARKLE_FW"
fi
# -----------------------------------------------------------------------------------

# Re-sign the outer app last, with hardened runtime, a secure timestamp, and NO
# entitlements — the sandbox/entitlements file was removed, and this also drops the
# com.apple.security.get-task-allow that a plain build can bake in (fails notarization).
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING"

echo "Notarizing $DMG_PATH ..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "Created $DMG_PATH"
