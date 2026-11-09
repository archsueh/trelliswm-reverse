import AppKit
import TrellisCore

/// Menu bar skeleton. The subject is an LSUIElement agent with a status item;
/// this reproduces only the command surface, not its artwork.
@MainActor
public final class MenuBarController: NSObject {
    private let item: NSStatusItem
    private let parser = CommandURL()
    private let onCommand: (Command) -> Void

    public init(onCommand: @escaping (Command) -> Void) {
        self.onCommand = onCommand
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        item.button?.title = "▦"
        item.button?.toolTip = "Trellis probe (clean-room)"
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        let labels: [(String, Command)] = [
            ("Show everything", .everything),
            ("Step out a level", .zoomOut),
            ("Step in a level", .zoomIn),
            ("Back", .back),
            ("Forward", .forward),
            ("Frame focused window", .frameWindow),
            ("Frame the Desktop", .frameDesktop),
            ("Hide / show Desktop", .toggleDesktop),
            ("Save view 1", .saveView(1)),
            ("Go to view 1", .view(1)),
            ("Split with Finder", .splitFinder),
            ("Arrange all windows", .arrange),
            ("Float all windows", .floatAll),
            ("Settings", .settings(.general)),
        ]
        for (index, entry) in labels.enumerated() {
            let mi = NSMenuItem(title: entry.0, action: #selector(run(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = index
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit probe", action: #selector(quit), keyEquivalent: "q"))
        menu.items.last?.target = self
        item.menu = menu
        self.labels = labels
    }

    private var labels: [(String, Command)] = []

    @objc private func run(_ sender: NSMenuItem) {
        guard labels.indices.contains(sender.tag) else { return }
        onCommand(labels[sender.tag].1)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
