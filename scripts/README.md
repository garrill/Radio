# Release scripts

Adapted from `~/Developer/Leaf/scripts`.

## `make_dmg.sh`

Builds `Radio` in Release, strips the executable, re-signs with **Developer ID
Application: Jonny Garrill (VL4Z3W8N24)** (hardened runtime, secure timestamp, no
entitlements), packages `build/Radio-<version>.dmg`, then notarizes and staples it.
Also drops a `build/Radio-<version>-<build>.dSYM` copy for crash symbolication.

Build number = `git rev-list --count HEAD`, injected as `CFBundleVersion`.

Sparkle framework handling (lproj pruning, slice thinning, nested re-signing) is
guarded on `Sparkle.framework` being embedded — it's a no-op until Radio adopts
Sparkle, then activates automatically.

### One-time setup

The Developer ID cert is already in the keychain. You still need the notary profile:

```sh
xcrun notarytool store-credentials radio-notary \
  --apple-id you@example.com --team-id VL4Z3W8N24 \
  --password <app-specific-password>      # appleid.apple.com → App-Specific Passwords
```

### Run

```sh
./scripts/make_dmg.sh
```

## `sign_and_update_appcast.sh`

For later, once Sparkle is in. Signs the newest `build/*.dmg` with the EdDSA key and
merges an item into `appcast.xml`, pulling release notes from the matching
`## [X.Y.Z]` section of `CHANGELOG.md`. Assets are assumed to be hosted on GitHub
Releases for `garrill/Radio` (edit `REPO` in the script if that changes).

Needs `appcast.xml` at the repo root (seed an empty `<rss>` feed for the first run)
and Sparkle's `generate_keys` already run once.
