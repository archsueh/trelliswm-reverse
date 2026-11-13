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
    /// Frames captured when tiling was turned on, keyed by stable window id.
    /// Restored on disable and on quit; entries for windows that have since
    /// closed are skipped.
    private var preTileFrames: [String: Rect] = [:]

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

        if canTile {
            refreshLive(apply: false)
            snapshotPreTileFrames()
            retile(apply: true)
        } else {
            retile(apply: false)
        }
        refreshMenu()
        writeLaunchReport()
        log.line("started trusted=\(bridge.isTrusted) tiling=\(tilingEnabled) originalWM=\(AppKitGlue.originalTrellisWMRunning) verify=\(verifyLaunch)")
    }

    func shutdown() {
        if tilingEnabled {
            restorePreTileFrames()
            tilingEnabled = false
            // Preference is left as the user last set it; frames are restored
            // so the desktop is not left in a tiled state after quit.
        }
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
        if enabled && !tilingEnabled {
            refreshLive(apply: false)
            snapshotPreTileFrames()
        } else if !enabled && tilingEnabled {
            restorePreTileFrames()
        }
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
        guard refreshLive(apply: apply) else {
            refreshMenu()
            return
        }
        refreshMenu()
    }

    /// Enumerate, admit, and reconcile. When `apply` is true and tiling is
    /// allowed, write frames (with clamp re-solve). Returns false when the
    /// primary visible frame cannot be read.
    @discardableResult
    private func refreshLive(apply: Bool) -> Bool {
        guard let frame = AppKitGlue.mainVisibleFrameAX()?.rect else { return false }
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
            applyFrames(in: frame, listed: listed, admittedIDs: Set(ids))
        }
        return true
    }

    private func applyFrames(in frame: Rect,
                             listed: [AXWindowBridge.LiveWindow] = [],
                             admittedIDs: Set<String> = []) {
        guard let subtree = TilingLayout.tilingSubtree(of: tree) else { return }
        observers.isApplying = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.observers.isApplying = false
            }
        }

        let ids = TilingLayout.tiledWindowIDs(in: tree)
        let requested = engine.rects(for: subtree, in: frame)
        var actual: [String: Rect] = [:]

        func write(_ rects: [String: Rect]) {
            for id in ids {
                let panelID = TilingLayout.panelID(for: id)
                guard let rect = rects[panelID], !rect.isEmpty, let window = live[id] else { continue }
                if let prev = actual[panelID], prev.almostEqual(rect, tolerance: 1) {
                    continue
                }
                if let got = bridge.setFrame(rect, of: window.element) {
                    actual[panelID] = got
                }
            }
        }

        write(requested)
        var resolved = requested
        for _ in 0..<2 {
            let next = ClampResolver.resolve(tree: subtree,
                                             requested: requested,
                                             actual: actual,
                                             frame: frame,
                                             gap: engine.gap)
            let changed = ids.contains { id in
                let panelID = TilingLayout.panelID(for: id)
                switch (next[panelID], resolved[panelID]) {
                case let (a?, b?): return !a.almostEqual(b, tolerance: 1)
                case (nil, nil): return false
                default: return true
                }
            }
            resolved = next
            if !changed { break }
            write(resolved)
        }
        logApply(listed: listed, admittedIDs: admittedIDs.isEmpty ? Set(ids) : admittedIDs,
                 requested: requested, actual: actual, resolved: resolved, frame: frame)
    }

    private func snapshotPreTileFrames() {
        preTileFrames = Dictionary(uniqueKeysWithValues: live.map { ($0.key, $0.value.bounds) })
        log.line("snapshot \(preTileFrames.count) window frames")
    }

    private func restorePreTileFrames() {
        observers.isApplying = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.observers.isApplying = false
            }
        }
        _ = refreshLive(apply: false)
        var restored = 0
        var skipped = 0
        for (id, original) in preTileFrames {
            guard let window = live[id] else {
                skipped += 1
                continue
            }
            _ = bridge.setFrame(original, of: window.element)
            restored += 1
        }
        log.line("restore frames restored=\(restored) closed=\(skipped)")
        preTileFrames.removeAll()
    }

    private func logApply(listed: [AXWindowBridge.LiveWindow],
                          admittedIDs: Set<String>,
                          requested: [String: Rect],
                          actual: [String: Rect],
                          resolved: [String: Rect],
                          frame: Rect) {
        let rejections: [[String: String]] = listed.compactMap { window in
            guard let reason = WindowAdmission.rejectionReason(window.snapshot, ownPID: AppKitGlue.ownPID) else {
                return nil
            }
            return ["id": window.id, "owner": window.snapshot.ownerName,
                    "role": window.snapshot.role, "subrole": window.snapshot.subrole,
                    "reason": reason]
        }
        func dict(_ rects: [String: Rect]) -> [String: [String: Double]] {
            var out: [String: [String: Double]] = [:]
            for (id, r) in rects {
                out[id] = ["x": r.x, "y": r.y, "w": r.w, "h": r.h]
            }
            return out
        }
        let payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "frame": ["x": frame.x, "y": frame.y, "w": frame.w, "h": frame.h],
            "listedCount": listed.count,
            "admittedCount": admittedIDs.count,
            "movedCount": actual.count,
            "rejections": rejections,
            "requested": dict(requested),
            "actual": dict(actual),
            "resolved": dict(resolved),
        ]
        log.writeJSON(payload, name: "trellis-wm-last-apply.json")
        log.line("apply listed=\(listed.count) admitted=\(admittedIDs.count) moved=\(actual.count) rejected=\(rejections.count)")
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
        // Fall back to the frontmost app's first managed window in tree
        // order (Dictionary iteration is not a stable focus order), then the
        // first tile.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let frontPID {
            let ordered = TilingLayout.tiledWindowIDs(in: tree)
            if let match = ordered.first(where: { live[$0]?.snapshot.pid == frontPID }) {
                focusedWindowID = match
                return match
            }
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
        let hotkeys = HotkeyCenter.shared.lastReport
        let payload: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "trusted": bridge.isTrusted,
            "tilingEnabled": tilingEnabled,
            "originalTrellisWMRunning": AppKitGlue.originalTrellisWMRunning,
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "app.trellisreverse.wm",
            "verifyLaunch": verifyLaunch,
            "managedCount": TilingLayout.tiledWindowIDs(in: tree).count,
            "canTile": canTile,
            "hotkeysRegistered": hotkeys.registered,
            "hotkeyFailures": hotkeys.failures,
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
