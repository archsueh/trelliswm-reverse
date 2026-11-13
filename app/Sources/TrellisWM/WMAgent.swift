import AppKit
import Foundation
import TrellisAX
import TrellisCore

@MainActor
final class WMAgent: NSObject {
    private let verifyLaunch: Bool
    private let bridge = AXWindowBridge()
    private let status = WMStatusItem()
    private let observers = ObserverLoop()
    private let log: AgentLog

    private var tree: LayoutNode = .desktop
    private var engine = Settings.release.layoutEngine
    private var focusedWindowID: String?
    private var live: [String: AXWindowBridge.LiveWindow] = [:]
    private var tilingEnabled: Bool
    private let defaultsKey = "tilingEnabled"

    init(verifyLaunch: Bool) {
        self.verifyLaunch = verifyLaunch
        self.log = AgentLog()
        self.tilingEnabled = verifyLaunch ? false : UserDefaults.standard.bool(forKey: defaultsKey)
        super.init()
    }

    func start() {
        status.onEnableTiling = { [weak self] _ in self?.userToggleTiling() }
        status.onRetile = { [weak self] in self?.retile(apply: true) }
        status.onGrantAccess = { [weak self] in self?.grantAccessibility() }
        status.onQuit = { NSApp.terminate(nil) }

        HotkeyCenter.shared.onHotkey = { [weak self] key in self?.handle(key) }
        if !verifyLaunch {
            HotkeyCenter.shared.register()
        }

        observers.onChange = { [weak self] in self?.retile(apply: true) }
        observers.start()

        retile(apply: false)
        refreshMenu()
        writeLaunchReport()
        log.line("started trusted=\(bridge.isTrusted) tiling=\(tilingEnabled) originalWM=\(AppKitGlue.originalTrellisWMRunning) verify=\(verifyLaunch)")
    }

    func shutdown() {
        HotkeyCenter.shared.unregister()
        observers.stop()
    }

    // MARK: - Menu / accessibility

    private func userToggleTiling() {
        if tilingEnabled {
            setTiling(false)
            return
        }
        if !bridge.isTrusted {
            grantAccessibility()
            return
        }
        if AppKitGlue.originalTrellisWMRunning {
            refreshMenu()
            return
        }
        setTiling(true)
        retile(apply: true)
    }

    private func setTiling(_ enabled: Bool) {
        tilingEnabled = enabled
        if !verifyLaunch {
            UserDefaults.standard.set(enabled, forKey: defaultsKey)
        }
        refreshMenu()
    }

    private func grantAccessibility() {
        _ = bridge.promptForTrust()
        AppKitGlue.openAccessibilitySettings()
        refreshMenu()
        log.line("prompted for Accessibility; trusted=\(bridge.isTrusted)")
    }

    private var canTile: Bool {
        tilingEnabled && bridge.isTrusted && !AppKitGlue.originalTrellisWMRunning
    }

    // MARK: - Tiling

    private func retile(apply: Bool) {
        guard let frame = AppKitGlue.mainVisibleFrameAX()?.rect else {
            refreshMenu()
            return
        }
        let listed = bridge.enumerateLiveWindows(ownPID: AppKitGlue.ownPID,
                                                 apps: AppKitGlue.runningApps(),
                                                 mainDisplayAX: frame)
        live = Dictionary(uniqueKeysWithValues: listed.map { ($0.id, $0) })
        let admitted = WindowAdmission.admitted(listed.map(\.snapshot), ownPID: AppKitGlue.ownPID)
        let ids = admitted.map(\.id)
        if let focus = focusedWindowID, !ids.contains(focus) {
            focusedWindowID = ids.first
        }
        tree = TilingLayout.reconcile(root: tree, windowIDs: ids, engine: engine)

        if apply, canTile {
            applyFrames(in: frame)
        }
        refreshMenu()
    }

    private func applyFrames(in frame: Rect) {
        guard let subtree = TilingLayout.tilingSubtree(of: tree) else { return }
        observers.isApplying = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.observers.isApplying = false
            }
        }
        let rects = engine.rects(for: subtree, in: frame)
        for (id, window) in live {
            let panelID = TilingLayout.panelID(for: id)
            guard let rect = rects[panelID], !rect.isEmpty else { continue }
            _ = bridge.setFrame(rect, of: window.element)
        }
    }

    private func refreshMenu() {
        status.reload(WMMenuState(trusted: bridge.isTrusted,
                                  tilingEnabled: tilingEnabled,
                                  originalWMRunning: AppKitGlue.originalTrellisWMRunning,
                                  managedCount: TilingLayout.tiledWindowIDs(in: tree).count))
    }

    // MARK: - Hotkeys

    private func handle(_ key: WMHotkey) {
        switch key {
        case .toggleTiling:
            userToggleTiling()
        case .retile:
            retile(apply: true)
        case .focusNext:
            focus(.next)
        case .focusPrev:
            focus(.previous)
        case .swapNext:
            swap(.next)
        case .swapPrev:
            swap(.previous)
        case .toggleAxis:
            guard canTile, let id = currentFocus() else { return }
            tree = TilingLayout.toggleAxis(ofWindow: id, in: tree)
            applyCurrent()
        case .grow:
            resize(delta: 0.05)
        case .shrink:
            resize(delta: -0.05)
        }
    }

    private func currentFocus() -> String? {
        if let focusedWindowID, TilingLayout.tiledWindowIDs(in: tree).contains(focusedWindowID) {
            return focusedWindowID
        }
        // Fall back to the frontmost app's first managed window, then first tile.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let frontPID, let match = live.values.first(where: { $0.snapshot.pid == frontPID }) {
            focusedWindowID = match.id
            return match.id
        }
        let first = TilingLayout.tiledWindowIDs(in: tree).first
        focusedWindowID = first
        return first
    }

    private func focus(_ direction: CycleDirection) {
        guard let from = currentFocus(),
              let next = TilingLayout.cycle(from: from, direction: direction, in: tree),
              let window = live[next] else { return }
        focusedWindowID = next
        bridge.raiseAndFocus(window.element, pid: window.snapshot.pid)
        AppKitGlue.activate(pid: window.snapshot.pid)
    }

    private func swap(_ direction: CycleDirection) {
        guard canTile, let from = currentFocus(),
              let other = TilingLayout.cycle(from: from, direction: direction, in: tree),
              other != from else { return }
        if let next = try? TilingLayout.swap(from, other, in: tree) {
            tree = next
            applyCurrent()
        }
    }

    private func resize(delta: Double) {
        guard canTile, let from = currentFocus() else { return }
        if let next = try? TilingLayout.resize(windowID: from, delta: delta, in: tree, engine: engine) {
            tree = next
            applyCurrent()
        }
    }

    private func applyCurrent() {
        if let frame = AppKitGlue.mainVisibleFrameAX()?.rect, canTile {
            applyFrames(in: frame)
        }
        refreshMenu()
    }

    // MARK: - Launch report

    private func writeLaunchReport() {
        let payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "trusted": bridge.isTrusted,
            "tilingEnabled": tilingEnabled,
            "originalTrellisWMRunning": AppKitGlue.originalTrellisWMRunning,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "app.trellisreverse.wm",
            "verifyLaunch": verifyLaunch,
            "managedCount": TilingLayout.tiledWindowIDs(in: tree).count,
            "canTile": canTile,
        ]
        log.writeJSON(payload, name: "launch-verify.json")
    }
}

final class AgentLog {
    private let directory: URL
    private let file: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        directory = home.appendingPathComponent("Library/Logs", isDirectory: true)
        file = directory.appendingPathComponent("TrellisReverseWM.log")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func line(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp)  \(message)\n"
        if let data = text.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: file.path) {
                if let handle = try? FileHandle(forWritingTo: file) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: file)
            }
        }
    }

    func writeJSON(_ payload: [String: Any], name: String) {
        let url = directory.appendingPathComponent(name)
        if JSONSerialization.isValidJSONObject(payload),
           let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
        if let trusted = payload["trusted"], let tiling = payload["tilingEnabled"] {
            line("launch-report trusted=\(trusted) tiling=\(tiling) originalWM=\(payload["originalTrellisWMRunning"] ?? "?") canTile=\(payload["canTile"] ?? "?")")
        }
    }
}
