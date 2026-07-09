# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Radio is a macOS menu-bar app for streaming NTS Radio (channels 1 and 2). It runs as an `LSUIElement` (no Dock icon, no main window) — the entire UI is a borderless `NSPanel` dropped from the status bar item, plus a standard `Settings` scene. There is a stubbed iOS placeholder in `RadioApp.swift` but the app is macOS-only in practice.

## Build & test

```bash
xcodebuild -scheme Radio -destination 'platform=macOS' build
```

Open `Radio.xcodeproj` in Xcode for day-to-day development (Cmd+R to run, Cmd+U to test). There is no SPM package and no external dependencies — the project has no `packageReferences` in `project.pbxproj`; keep it that way unless a dependency is genuinely required.

Unit tests live in `RadioTests/`, UI tests in `RadioUITests/`. Run a single test via `xcodebuild test -scheme Radio -destination 'platform=macOS' -only-testing:RadioTests/RadioTests/<testMethodName>`.

## Architecture

### Ownership and lifecycle

`AppDelegate` (macOS-only, `#if os(macOS)`) is the composition root: it owns the single `RadioPlayer` and `NTSService` instances for the app's lifetime and injects them into SwiftUI via `.environmentObject`. There is no other DI mechanism — new shared state should be added as `@Published` properties on one of these two `ObservableObject`s, or on a new object owned by `AppDelegate` alongside them.

The panel (`NSPanel` wrapping `ContentView` via `NSHostingController`) is created once in `setupPanel()` and toggled with `orderFront`/`orderOut` — it's never re-created. `panelSize(for:)` computes the window size by hand from `ChannelRow`'s known internal paddings (see the comment at `AppDelegate.swift`); if you change `ChannelRow`'s layout (padding, artwork size options, progress bar height, etc.) you must update this calculation or rows will clip.

Two independent async producers exist:
- `NTSService`: polls `https://www.nts.live/api/v2/live` every 30s while the panel is open (`startPolling`/`stopPolling`, called from `showPanel`/`closePanel`), decodes `NTSLiveResponse` into `channels`. A single persistent `NWPathMonitor` (started once at launch, never stopped) drives `isOffline` and triggers a re-fetch on reconnect.
- `RadioPlayer`: wraps a single `AVPlayer` for whichever of the two live streams is active. `toggle`/`play`/`stop`/`fadeOutAndStop` are the only entry points; `play` always calls `stop` first to tear down the previous player/observers before building a new one. KVO observers (`timeControlObserver`, `itemStatusObserver`) are created per-`play()` call and invalidated in `stop()`.

### View structure

`ContentView` is the panel's root (channel list + bottom menu row). It was split out of a single monolithic file into topic files — when adding UI, follow the existing split rather than growing one file:
- `ChannelRow.swift` — per-channel row (artwork, now/next broadcast, progress, play toggle, tracklist button)
- `MarqueeComponents.swift` / `AnimationComponents.swift` — scrolling-text and shared animation helpers used by rows
- `MenuComponents.swift` — the bottom menu rows (Refresh/Chatroom/Settings/Quit) shared between `ContentView` and elsewhere
- `NTSLogoImage.swift` — logo/icon asset helpers
- `SettingsView.swift` — the `Settings` scene (General + About tabs), including the `NSViewRepresentable` hack that hides the miniaturize/zoom window buttons on the Settings window
- `TracklistWindowManager.swift` — a singleton managing per-channel `WKWebView` windows for the live tracklist page; windows are preloaded at launch and kept alive (`isReleasedWhenClosed = false`) after close so the WebContent process stays warm and reopening doesn't stutter

### Models

`NTSModels.swift` defines the API response shapes. `Broadcast` decodes ISO8601 timestamps and HTML-entity-decodes/title-cases the broadcast title once at decode time (not on every render). `ChannelData.effectiveNow`/`effectiveNext` compensate for the NTS API occasionally lagging behind the real schedule by promoting `next` to current when `now` has already ended.

### User-facing settings

Stored via `@AppStorage` (no separate settings model): `artworkSize` (typed as `ArtworkSize`, defined in `ArtworkSize.swift` — the single source of truth for the small/medium/large dimensions, used by `ChannelRow`, `AppDelegate.panelSize`, and the Settings `Picker`), `showTracklisting`, `chatroomLinkType` (`web`/`app`/`hidden`).
