#if os(macOS)
import AppKit
import SwiftUI
import Combine
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate {

    /// Shared model objects — owned here, passed into SwiftUI via environmentObject
    let player = RadioPlayer()
    let ntsService = NTSService()
    let mixtapeNowPlayingService = MixtapeNowPlayingService()

    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var hostingController: NSHostingController<AnyView>!
    private var outsideClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        Log.lifecycle.notice("Launched Radio \(version, privacy: .public) (\(build, privacy: .public)) on \(ProcessInfo.processInfo.operatingSystemVersionString, privacy: .public)")

        setupPanel()
        setupStatusItem()
        observePlayingChannel()
        observeMixtapeConfig()
        observeMixtapeNowPlaying()
        DiagnosticsMonitor.shared.start()
        ntsService.startMonitor()
        ntsService.startPolling()
        ntsService.fetchMixtapes()
        player.setup()
        _ = UpdaterHolder.shared   // start Sparkle's background update checks

        // A refetch when the Mac wakes — the schedule is stale after sleep, and this
        // also re-warms things if the network changed while asleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            Log.lifecycle.debug("Woke from sleep — refetching")
            // The observer is registered with `queue: .main`, so this closure always
            // runs on the main thread — assert that to reach the @MainActor service.
            MainActor.assumeIsolated { self.ntsService.fetch() }
        }
        /// Open the menu automatically on launch so it can be triggered via app launcher shortcut —
        /// but not when launchd started us at login, where only the menu-bar icon should appear.
        if launchedAsLoginItem {
            Log.lifecycle.debug("Launched at login — not auto-showing panel")
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showPanel()
            }
        }
        /// Pre-warm the WebContent process so opening the tracklist during playback doesn't stutter
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            TracklistWindowManager.shared.preload()
        }
    }

    /// True when launchd launched us as a login item (rather than the user opening the app).
    /// The launch Apple event carries `keyAELaunchedAsLogInItem` in that case.
    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard player.playing != nil else { return .terminateNow }
        player.fadeOutAndStop {
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible { showPanel() }
        return false
    }

    /// Handles the `radio://` scheme — used by the desktop widget's tap target to bring
    /// the panel to front instead of just launching/activating the app.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "radio" }) else { return }
        if !panel.isVisible { showPanel() }
    }

    // MARK: - Panel

    private func setupPanel() {
        let content = AnyView(
            ContentView()
                .environmentObject(player)
                .environmentObject(ntsService)
                .environmentObject(mixtapeNowPlayingService)
        )
        hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = []

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
    }

    func showPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let artworkSize = UserDefaults.standard.string(forKey: "artworkSize").flatMap(ArtworkSize.init) ?? .medium
        let size = AppDelegate.panelSize(for: artworkSize, mixtapeCount: enabledMixtapeCount())
        panel.setContentSize(size)

        let buttonFrame = buttonWindow.frame
        // On launch the system assigns a temporary placeholder position to status items
        // before settling them at their real location — bail out and let the asyncAfter retry.
        guard NSScreen.screens.contains(where: { $0.frame.intersects(buttonFrame) }) else { return }

        var x = buttonFrame.midX - size.width / 2
        let y = buttonFrame.minY - size.height + 24

        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            x = max(visible.minX + 4, min(x, visible.maxX - size.width - 4))
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        player.isPanelVisible = true
        ntsService.startPolling()
        panel.orderFront(nil)
        Log.lifecycle.debug("Panel shown")

        // Defensive: never leak a monitor if showPanel runs twice without a closePanel.
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.closePanel()
        }
    }

    private static func panelSize(for artworkSize: ArtworkSize, mixtapeCount: Int) -> NSSize {
        // Row: top(12) + artwork + bottom(10) + progressBar(27) + nextUp(24) = artwork + 73
        // 2 rows + row-divider(1) + list-top-pad(2) + bottom-divider(1) + buttons(76) + shadow-padding(36)
        // buttons(): Website/Chatroom/Settings/Quit — ~24pt each.
        // Width: card(280) + shadow-padding(24*2) — must match ContentView's outer .frame(width:)/.padding(24)
        let base = artworkSize.dimension * 2 + 262
        return NSSize(width: 328, height: base + MixtapeGrid.sectionHeight(count: mixtapeCount))
    }

    /// Number of enabled mixtapes that actually exist in the loaded catalogue —
    /// read straight from `UserDefaults` (like `artworkSize`) so it is available
    /// before any SwiftUI view has mounted.
    private func enabledMixtapeCount() -> Int {
        guard UserDefaults.standard.bool(forKey: "showInfiniteMixtapes") else { return 0 }
        let raw = UserDefaults.standard.string(forKey: "enabledMixtapes") ?? ""
        let aliases = Set(MixtapeSelection.aliases(from: raw))
        guard !aliases.isEmpty else { return 0 }
        return ntsService.mixtapes.filter { aliases.contains($0.alias) }.count
    }

    private func closePanel() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        player.isPanelVisible = false
        ntsService.stopPolling()
        panel.orderOut(nil)
        Log.lifecycle.debug("Panel hidden")
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = .ntsMenuBarIcon
        button.image?.isTemplate = true
        // Respond to both left and right click
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.action = #selector(handleClick)
        button.target = self
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Dynamic Icon

    private func observePlayingChannel() {
        player.$playing
            .receive(on: RunLoop.main)
            .sink { [weak self] item in
                guard let self, let button = self.statusItem.button else { return }
                TracklistWindowManager.shared.isPlaybackActive = item != nil
                switch item {
                case .channel(let channel)?:
                    button.image = Self.symbolIcon(named: channel.menuBarSymbol, label: channel.label)
                case .mixtape(let mixtape)?:
                    self.setMixtapeMenuBarIcon(for: mixtape, button: button)
                case nil:
                    button.image = .ntsMenuBarIcon
                    button.image?.isTemplate = true
                }
            }
            .store(in: &cancellables)
    }

    private static func symbolIcon(named name: String, label: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(config)
        img?.size = NSSize(width: 18, height: 18)
        img?.isTemplate = true
        return img
    }

    // MARK: - Mixtape config

    /// Keeps `player.mixtapeStations` (the media-key rotation) current, and stops
    /// playback when the mixtape that's playing is switched off or hidden.
    private func observeMixtapeConfig() {
        ntsService.$mixtapes
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncMixtapeConfig() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncMixtapeConfig() }
            .store(in: &cancellables)

        syncMixtapeConfig()
    }

    private func syncMixtapeConfig() {
        let showMixtapes = UserDefaults.standard.bool(forKey: "showInfiniteMixtapes")
        let raw = UserDefaults.standard.string(forKey: "enabledMixtapes") ?? ""
        let enabled = showMixtapes
            ? ntsService.mixtapes.filter { MixtapeSelection.isEnabled($0.alias, in: raw) }
            : []
        player.mixtapeStations = enabled

        // Playing a mixtape that's just been deselected or hidden? Stop it.
        if case .mixtape(let playing)? = player.playing,
           !enabled.contains(where: { $0.alias == playing.alias }) {
            player.fadeOutAndStop()
        }
    }

    // MARK: - Mixtape now-playing

    /// Starts/stops `mixtapeNowPlayingService`'s Firestore poll as playback moves in
    /// and out of `.mixtape`, and feeds resolved titles back into `player` (Control
    /// Center / lock screen / media-key HUD, plus the mixtape tile's tooltip).
    private func observeMixtapeNowPlaying() {
        player.$playing
            .receive(on: RunLoop.main)
            .sink { [weak self] item in
                guard let self else { return }
                if case .mixtape(let mixtape)? = item {
                    self.mixtapeNowPlayingService.start(alias: mixtape.alias)
                } else {
                    self.mixtapeNowPlayingService.stop()
                }
            }
            .store(in: &cancellables)

        mixtapeNowPlayingService.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] nowPlaying in
                guard let self, case .mixtape(let mixtape)? = self.player.playing else { return }
                self.player.setMixtapeNowPlaying(nowPlaying, for: mixtape)
            }
            .store(in: &cancellables)
    }

    /// Shows a fallback glyph immediately, then swaps in the mixtape's own icon
    /// once it downloads — but only if that mixtape is still the one playing.
    private func setMixtapeMenuBarIcon(for mixtape: Mixtape, button: NSStatusBarButton) {
        if let cached = MixtapeMenuBarIcon.cached(for: mixtape) {
            button.image = cached
            return
        }
        button.image = Self.symbolIcon(named: MixtapeMenuBarIcon.fallbackSymbol, label: mixtape.title)
        Task { [weak self] in
            guard let image = await MixtapeMenuBarIcon.image(for: mixtape) else { return }
            guard let self, self.player.playing == .mixtape(mixtape),
                  let button = self.statusItem.button else { return }
            button.image = image
        }
    }
}
#endif
