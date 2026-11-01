import SwiftUI
import AppKit

@main
final class PanelAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = PanelAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let model = PanelModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "MacPanel")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "MacPanel"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 250)
        popover.contentViewController = NSHostingController(rootView:
            PanelView(onHeightChange: { [weak self] height in
                self?.popover.contentSize = NSSize(width: 420, height: height)
            }).environmentObject(model))
        model.start()
        DispatchQueue.main.async { [weak self] in self?.showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) { model.stop() }
}
