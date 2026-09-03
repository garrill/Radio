#if os(macOS)
import AppKit
import SwiftUI
import Combine
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate {

    /// Shared model objects — owned here, passed into SwiftUI via environmentObject
    let player = RadioPlayer()
    let ntsService = NTSService()

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
        DiagnosticsMonitor.shared.start()
        ntsService.startMonitor()
        ntsService.startPolling()
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
        guard player.playingChannel != nil else { return .terminateNow }
        player.fadeOutAndStop {
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible { showPanel() }
        return false
    }

    // MARK: - Panel

    private func setupPanel() {
        let content = AnyView(
            ContentView()
                .environmentObject(player)
                .environmentObject(ntsService)
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

    private func showPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let artworkSize = UserDefaults.standard.string(forKey: "artworkSize").flatMap(ArtworkSize.init) ?? .medium
        let size = AppDelegate.panelSize(for: artworkSize)
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

    private static func panelSize(for artworkSize: ArtworkSize) -> NSSize {
        // Row: top(12) + artwork + bottom(10) + progressBar(27) + nextUp(24) = artwork + 73
        // 2 rows + row-divider(1) + list-top-pad(2) + bottom-divider(1) + buttons(76) + shadow-padding(36)
        // buttons(): Website/Chatroom/Settings/Quit — ~24pt each.
        // Width: card(280) + shadow-padding(24*2) — must match ContentView's outer .frame(width:)/.padding(24)
        return NSSize(width: 328, height: artworkSize.dimension * 2 + 262)
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
        player.$playingChannel
            .receive(on: RunLoop.main)
            .sink { [weak self] channel in
                guard let self, let button = self.statusItem.button else { return }
                TracklistWindowManager.shared.isPlaybackActive = channel != nil
                if let channel {
                    let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
                    let img = NSImage(
                        systemSymbolName: channel.menuBarSymbol,
                        accessibilityDescription: channel.label
                    )?.withSymbolConfiguration(config)
                    img?.size = NSSize(width: 18, height: 18)
                    img?.isTemplate = true
                    button.image = img
                } else {
                    button.image = .ntsMenuBarIcon
                    button.image?.isTemplate = true
                }
            }
            .store(in: &cancellables)
    }
}
#endif
