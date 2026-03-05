#if os(macOS)
import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {

    // Shared model objects — owned here, passed into SwiftUI via environmentObject
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
        // Open the menu automatically on launch so it can be triggered via app launcher shortcut
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
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
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
    }

    private func showPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        // Size panel to fit content
        let size = hostingController.preferredContentSize
        panel.setContentSize(size)

        // Position below the status item
        let buttonScreenFrame = buttonWindow.convertToScreen(button.bounds)
        let x = buttonScreenFrame.midX - size.width / 2
        let y = buttonScreenFrame.minY - size.height - 4
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        panel.makeKeyAndOrderFront(nil)

        // Close when clicking anywhere outside
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.closePanel()
        }
    }

    private func closePanel() {
        panel.orderOut(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
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
