import AppKit

struct WMMenuState {
    var trusted: Bool
    var tilingEnabled: Bool
    var originalWMRunning: Bool
    var managedCount: Int
}

@MainActor
final class WMStatusItem: NSObject {
    var onEnableTiling: ((Bool) -> Void)?
    var onRetile: (() -> Void)?
    var onGrantAccess: (() -> Void)?
    var onQuit: (() -> Void)?

    private let item: NSStatusItem

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let image = NSImage(systemSymbolName: "rectangle.split.3x1",
                               accessibilityDescription: "Trellis WM") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "WM"
        }
        item.button?.toolTip = "Trellis WM"
        item.menu = NSMenu()
    }

    func reload(_ state: WMMenuState) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let title = NSMenuItem(title: "Trellis WM", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: state.tilingEnabled ? "Disable Tiling" : "Enable Tiling",
                                action: #selector(toggleTiling(_:)),
                                keyEquivalent: "")
        toggle.target = self
        let canEnable = state.trusted && !state.originalWMRunning
        toggle.isEnabled = canEnable || state.tilingEnabled
        if !state.trusted {
            toggle.toolTip = "Grant Accessibility first."
        } else if state.originalWMRunning {
            toggle.toolTip = "Quit the original TrellisWM first so two window managers are not fighting."
        }
        menu.addItem(toggle)

        let retile = NSMenuItem(title: "Retile Now", action: #selector(retileNow), keyEquivalent: "")
        retile.target = self
        retile.isEnabled = state.tilingEnabled && state.trusted && !state.originalWMRunning
        menu.addItem(retile)
        menu.addItem(.separator())

        let permissionTitle: String
        if state.trusted {
            permissionTitle = "Accessibility: Granted"
        } else {
            permissionTitle = "Accessibility: Not granted"
        }
        let permission = NSMenuItem(title: permissionTitle, action: nil, keyEquivalent: "")
        permission.isEnabled = false
        menu.addItem(permission)

        if !state.trusted {
            let grant = NSMenuItem(title: "Grant Accessibility…",
                                   action: #selector(grantAccess),
                                   keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }

        if state.originalWMRunning {
            let warn = NSMenuItem(title: "Original TrellisWM is running — tiling stays off",
                                  action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }

        let count = NSMenuItem(title: "Managed windows: \(state.managedCount)",
                               action: nil, keyEquivalent: "")
        count.isEnabled = false
        menu.addItem(count)

        menu.addItem(.separator())
        let keysHeader = NSMenuItem(title: "Hotkeys", action: nil, keyEquivalent: "")
        keysHeader.isEnabled = false
        menu.addItem(keysHeader)
        for key in WMHotkey.allCases {
            let line = NSMenuItem(title: "\(key.menuLabel)    \(key.binding)",
                                  action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Trellis WM", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func toggleTiling(_ sender: NSMenuItem) {
        // The agent decides the next value from current state.
        onEnableTiling?(true)
    }

    @objc private func retileNow() { onRetile?() }
    @objc private func grantAccess() { onGrantAccess?() }
    @objc private func quitApp() { onQuit?() }
}
