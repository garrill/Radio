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
        ntsService.startPolling()
        player.setup()
        /// Open the menu automatically on launch so it can be triggered via app launcher shortcut
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showPanel()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible { showPanel() }
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if !panel.isVisible { showPanel() }
    }

    // MARK: - Panel

    private func setupPanel() {
        let content = AnyView(
            ContentView()
                .environmentObject(player)
                .environmentObject(ntsService)
        )
        hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = .preferredContentSize

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

        // Force SwiftUI to complete its layout pass so preferredContentSize is valid.
        // Without this, applicationDidBecomeActive can call showPanel() before the
        // first render, resulting in a zero size and a mispositioned panel.
        hostingController.view.layoutSubtreeIfNeeded()

        let size = hostingController.preferredContentSize
        // Guard against a pre-layout zero size — the asyncAfter will retry.
        guard size.width > 0, size.height > 0 else { return }
        panel.setContentSize(size)

        // NSWindow.frame is already in screen coordinates — no conversion needed.
        // The status item's window frame IS the button's screen rect.
        let buttonFrame = buttonWindow.frame

        // On launch the system assigns a temporary placeholder position to status items
        // before settling them at their real location. If the button frame doesn't
        // intersect any real screen it hasn't been placed yet — bail out and let the
        // asyncAfter in applicationDidFinishLaunching retry.
        guard NSScreen.screens.contains(where: { $0.frame.intersects(buttonFrame) }) else { return }

        var x = buttonFrame.midX - size.width / 2
        let y = buttonFrame.minY - size.height + 17

        // Clamp horizontally so the panel never goes off-screen
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            x = max(visible.minX + 4, min(x, visible.maxX - size.width - 4))
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        player.isPanelVisible = true
        ntsService.startPolling() // refresh data and restart 30 s poll
        panel.makeKeyAndOrderFront(nil)

        // Close when clicking anywhere outside
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        player.isPanelVisible = false
        ntsService.stopPolling() // no background work while panel is hidden
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
                    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                    let img = NSImage(
                        systemSymbolName: channel.menuBarSymbol,
                        accessibilityDescription: channel.label
                    )?.withSymbolConfiguration(config)
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
