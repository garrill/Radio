#!/bin/sh
# Signs a built DMG for Sparkle and folds the result into the repo's appcast.xml.
# Run after ./scripts/make_dmg.sh, once Radio has adopted Sparkle.
#
# Usage: ./scripts/sign_and_update_appcast.sh [path/to/Radio-X.Y.Z.dmg]
# With no argument, picks the newest .dmg in build/.
#
# Needs:
#   - the EdDSA private key from Sparkle's `generate_keys` still in this user's Keychain
#   - the project built at least once so SPM has resolved Sparkle's binary artifact
#   - an appcast.xml at the repo root (seed an empty <rss> feed for the first run)
#
# Adapted from ~/Developer/Leaf/scripts/sign_and_update_appcast.sh.
set -eu

cd "$(dirname "$0")/.."

REPO="garrill/Radio"   # GitHub repo the DMG is hosted on (Releases assets)

DMG_PATH="${1:-}"
if [ -z "$DMG_PATH" ]; then
	DMG_PATH=$(ls -t build/*.dmg 2>/dev/null | head -1)
fi
if [ -z "$DMG_PATH" ] || [ ! -f "$DMG_PATH" ]; then
	echo "error: no DMG found. Run ./scripts/make_dmg.sh first, or pass a path." >&2
	exit 1
fi

if [ ! -f appcast.xml ]; then
	echo "error: appcast.xml not found at repo root." >&2
	echo "Seed one first, e.g.:" >&2
	echo '  <?xml version="1.0" standalone="yes"?>' >&2
	echo '  <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><title>Radio</title></channel></rss>' >&2
	exit 1
fi

VERSION=$(basename "$DMG_PATH" .dmg | sed 's/^Radio-//')
if [ -z "$VERSION" ]; then
	echo "error: couldn't parse a version out of $DMG_PATH (expected Radio-X.Y.Z.dmg)" >&2
	exit 1
fi

GENERATE_APPCAST=$(find "$HOME/Library/Developer/Xcode/DerivedData" \
	-path "*/artifacts/sparkle/Sparkle/bin/generate_appcast" -print -quit 2>/dev/null || true)
# make_dmg.sh builds into ./build/DerivedData, so also look there.
if [ -z "$GENERATE_APPCAST" ]; then
	GENERATE_APPCAST=$(find "build/DerivedData" \
		-path "*/artifacts/sparkle/Sparkle/bin/generate_appcast" -print -quit 2>/dev/null || true)
fi
if [ -z "$GENERATE_APPCAST" ]; then
	echo "error: couldn't find Sparkle's generate_appcast. Build the project once so SPM resolves Sparkle." >&2
	exit 1
fi

STAGING="build/appcast-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp "$DMG_PATH" "$STAGING/"

# Pull this version's notes out of CHANGELOG.md (the section under "## [<version>]").
NOTES_FILE="$STAGING/Radio-$VERSION.md"
awk -v ver="[$VERSION]" '
	/^## \[/ { if (found) exit; if (index($0, ver)) { found=1; next } }
	found { print }
' CHANGELOG.md > "$NOTES_FILE" 2>/dev/null || true
if [ ! -s "$NOTES_FILE" ]; then
	echo "warning: no CHANGELOG.md section for [$VERSION] — item ships with no release notes" >&2
	rm -f "$NOTES_FILE"
else
	RELEASE_DATE=$(date -r "$DMG_PATH" "+%B %-d %Y")
	printf '### v%s (%s)\n\n%s\n' "$VERSION" "$RELEASE_DATE" "$(cat "$NOTES_FILE")" > "$NOTES_FILE"
fi

# generate_appcast merges into an existing appcast.xml in the target dir.
cp appcast.xml "$STAGING/appcast.xml"

"$GENERATE_APPCAST" --embed-release-notes \
	--download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
	--full-release-notes-url "https://github.com/$REPO/releases" \
	"$STAGING"

cp "$STAGING/appcast.xml" appcast.xml

echo "Updated appcast.xml with $DMG_PATH (version $VERSION)."
echo "Next: commit appcast.xml + CHANGELOG.md, push a GitHub Release tagged v$VERSION, and attach $DMG_PATH."
echo "The <enclosure url> in appcast.xml must exactly match that release asset's download URL."
