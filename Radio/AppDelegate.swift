#if os(macOS)
import AppKit
import SwiftUI
import Combine

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
        setupPanel()
        setupStatusItem()
        observePlayingChannel()
        ntsService.startMonitor()
        ntsService.startPolling()
        player.setup()
        /// Open the menu automatically on launch so it can be triggered via app launcher shortcut
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showPanel()
        }
        /// Pre-warm the WebContent process so opening the tracklist during playback doesn't stutter
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            TracklistWindowManager.shared.preload()
        }
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

        let size = AppDelegate.panelSize(for: UserDefaults.standard.string(forKey: "artworkSize") ?? "medium")
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

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.closePanel()
        }
    }

    private static func panelSize(for artworkSetting: String) -> NSSize {
        let artwork: CGFloat = artworkSetting == "small" ? 66 : artworkSetting == "large" ? 120 : 80
        // Row: top(12) + artwork + bottom(10) + progressBar(27) + nextUp(24) = artwork + 73
        // 2 rows + row-divider(1) + list-top-pad(2) + bottom-divider(1) + buttons(100) + shadow-padding(36)
        return NSSize(width: 316, height: artwork * 2 + 286)
    }

    private func closePanel() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        player.isPanelVisible = false
        ntsService.stopPolling()
        panel.orderOut(nil)
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
