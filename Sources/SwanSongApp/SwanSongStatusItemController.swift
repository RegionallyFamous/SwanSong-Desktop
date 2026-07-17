import AppKit

@MainActor
final class SwanSongStatusItemController: NSObject {
    let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = SwanTheme.menuBarIcon
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "SwanSong"
            button.setAccessibilityLabel("SwanSong")
        }

        let menu = NSMenu(title: "SwanSong")
        let showItem = NSMenuItem(
            title: "Show SwanSong",
            action: #selector(showApplication(_:)),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit SwanSong",
            action: #selector(quitApplication(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc
    private func showApplication(_ sender: Any?) {
        NSApp.unhide(sender)
        for window in NSApp.windows where window.canBecomeKey {
            window.makeKeyAndOrderFront(sender)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    private func quitApplication(_ sender: Any?) {
        NSApp.terminate(sender)
    }
}
