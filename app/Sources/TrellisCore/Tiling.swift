import Foundation

/// A permission-free description of a window, used to decide what the tiling
/// agent should manage. The real AX objects live in TrellisAX; this type is
/// pure data so admission and tree mapping can be unit-tested.
public struct WindowSnapshot: Equatable, Sendable, Codable {
    public var id: String
    public var ownerName: String
    public var bundleID: String
    public var pid: Int32
    public var role: String
    public var subrole: String
    public var isMinimized: Bool
    public var isFullscreen: Bool
    public var isOnMainDisplay: Bool
    public var activationPolicy: ProcessActivationPolicy

    public init(id: String,
                ownerName: String = "",
                bundleID: String = "",
                pid: Int32 = 0,
                role: String = "AXWindow",
                subrole: String = "AXStandardWindow",
                isMinimized: Bool = false,
                isFullscreen: Bool = false,
                isOnMainDisplay: Bool = true,
                activationPolicy: ProcessActivationPolicy = .regular) {
        self.id = id
        self.ownerName = ownerName
        self.bundleID = bundleID
        self.pid = pid
        self.role = role
        self.subrole = subrole
        self.isMinimized = isMinimized
        self.isFullscreen = isFullscreen
        self.isOnMainDisplay = isOnMainDisplay
        self.activationPolicy = activationPolicy
    }
}

public enum ProcessActivationPolicy: String, Codable, Equatable, Sendable {
    case regular
    case accessory
    case prohibited
}

public enum CycleDirection: String, Sendable {
    case next
    case previous
}

/// Admission rules for v0.1: standard windows of regular apps on the main
/// display, excluding minimized, fullscreen, and our own (or the original
/// TrellisWM) process.
public enum WindowAdmission: Sendable {
    public static let standardSubrole = "AXStandardWindow"
    public static let windowRole = "AXWindow"

    public static let skippedBundleIDs: Set<String> = [
        "app.trellisreverse.wm",
        "app.trellisreverse.studio",
        "app.trellisui.trelliswm",
    ]

    /// Why `admits` would reject this window, or `nil` if it would be kept.
    /// Used for diagnostics (managed-count vs AX-window-count mismatches).
    public static func rejectionReason(_ window: WindowSnapshot, ownPID: Int32) -> String? {
        if window.pid == ownPID { return "own-pid" }
        if window.pid == 0 { return "zero-pid" }
        if !window.bundleID.isEmpty, skippedBundleIDs.contains(window.bundleID) {
            return "skipped-bundle:\(window.bundleID)"
        }
        if window.activationPolicy != .regular { return "policy:\(window.activationPolicy.rawValue)" }
        if window.role != windowRole { return "role:\(window.role)" }
        if window.subrole != standardSubrole { return "subrole:\(window.subrole)" }
        if window.isMinimized { return "minimized" }
        if window.isFullscreen { return "fullscreen" }
        if !window.isOnMainDisplay { return "off-main" }
        return nil
    }

    public static func admits(_ window: WindowSnapshot, ownPID: Int32) -> Bool {
        rejectionReason(window, ownPID: ownPID) == nil
    }

    public static func admitted(_ windows: [WindowSnapshot], ownPID: Int32) -> [WindowSnapshot] {
        windows.filter { admits($0, ownPID: ownPID) }
    }
}

/// Map admitted windows onto a TrellisCore layout tree and apply tiling
/// operations (swap, axis flip, ratio resize, focus cycle). The stored tree
/// always keeps the required `desktop` leaf; geometry for real windows is
/// taken from `tilingSubtree`, which excludes that leaf so tiles fill the
/// visible frame.
public enum TilingLayout: Sendable {
    public static let rootID = "root"
    public static let tiledSplitID = "split-tiled"

    public static func panelID(for windowID: String) -> String { "p-\(windowID)" }

    public static func panel(_ windowID: String) -> LayoutNode {
        .panel(Panel(id: panelID(for: windowID), views: [windowID], selected: windowID))
    }

    /// Window (seat) ids of docked panels, in tree / tile order.
    public static func tiledWindowIDs(in root: LayoutNode) -> [String] {
        root.leaves.compactMap { node in
            if case .panel(let p) = node { return p.selected ?? p.views.first }
            return nil
        }
    }

    /// The subtree that actually fills the screen (everything but the
    /// placeholder desktop leaf). Nil when there are no tiled windows.
    public static func tilingSubtree(of root: LayoutNode) -> LayoutNode? {
        if case .split(let s) = root {
            let others = s.children.filter { $0.id != "desktop" }
            if others.count == 1 { return others[0] }
            if others.count > 1 {
                return .split(Split(id: s.id, axis: s.axis, children: others, weights: {
                    let idx = s.children.indices.filter { s.children[$0].id != "desktop" }
                    return LayoutNode.normalize(idx.map { s.weights[$0] }, to: others.count)
                }()))
            }
            return nil
        }
        if case .panel = root { return root }
        return nil
    }

    public static func preferredAxis(in root: LayoutNode) -> Axis {
        if let sub = tilingSubtree(of: root), case .split(let s) = sub { return s.axis }
        return .x
    }

    public static func build(windowIDs: [String], axis: Axis = .x) -> LayoutNode {
        if windowIDs.isEmpty { return .desktop }
        let panels = windowIDs.map(panel)
        let tiled: LayoutNode
        if panels.count == 1 {
            tiled = panels[0]
        } else {
            tiled = .split(Split(id: tiledSplitID, axis: axis, children: panels))
        }
        return .split(Split(id: rootID, axis: .x, children: [tiled, .desktop], weights: [1.0, 0.0]))
    }

    /// Keep existing structure and weights where possible; drop gone windows
    /// and append newly admitted ones.
    public static func reconcile(root: LayoutNode,
                                 windowIDs: [String],
                                 axis: Axis? = nil,
                                 engine: LayoutEngine = LayoutEngine()) -> LayoutNode {
        let axis = axis ?? preferredAxis(in: root)
        let current = tiledWindowIDs(in: root)
        let wanted = windowIDs
        let wantedSet = Set(wanted)
        let kept = current.filter { wantedSet.contains($0) }
        let added = wanted.filter { !Set(current).contains($0) }

        if kept.isEmpty { return build(windowIDs: wanted, axis: axis) }

        var tree = root
        for id in current where !wantedSet.contains(id) {
            if let next = try? engine.removing(nodeID: panelID(for: id), from: tree) {
                tree = next
            }
        }

        if tiledWindowIDs(in: tree).isEmpty {
            return build(windowIDs: wanted, axis: axis)
        }

        for id in added {
            let target = tiledWindowIDs(in: tree).last.map(panelID(for:)) ?? "desktop"
            let edge: Direction = (axis == .x) ? .right : .down
            if let next = try? engine.inserting(panel: panel(id), adjacentTo: target, edge: edge, in: tree) {
                tree = next
            }
        }
        return tree
    }

    public static func resolvePanelID(_ token: String, in root: LayoutNode) -> String? {
        if root.node(id: token) != nil { return token }
        return root.panel(containing: token)?.id
    }

    public static func swap(_ a: String, _ b: String, in root: LayoutNode) throws -> LayoutNode {
        guard let idA = resolvePanelID(a, in: root),
              let idB = resolvePanelID(b, in: root),
              idA != idB,
              let nodeA = root.node(id: idA),
              let nodeB = root.node(id: idB) else {
            throw LayoutError.notFound("cannot swap '\(a)' and '\(b)'")
        }
        return rewrite(root) { node in
            if node.id == idA { return nodeB }
            if node.id == idB { return nodeA }
            return nil
        }
    }

    /// Flip the axis of the split that contains `windowID`. No-op when the
    /// window has no parent split (only one tile).
    public static func toggleAxis(ofWindow windowID: String, in root: LayoutNode) -> LayoutNode {
        guard let panelID = resolvePanelID(windowID, in: root),
              let parent = root.parent(of: panelID) else { return root }
        // Prefer flipping the tiled split, not the root wrapper that also
        // holds the zero-weight desktop leaf — unless that *is* the parent
        // and it has two real tiles (shouldn't happen with build()).
        let targetID: String
        if parent.id == rootID, let sub = tilingSubtree(of: root), case .split(let s) = sub {
            targetID = s.id
        } else if parent.id == rootID, parent.children.filter({ $0.id != "desktop" }).count < 2 {
            return root
        } else {
            targetID = parent.id
        }
        return rewrite(root) { node in
            guard case .split(let s) = node, s.id == targetID else { return nil }
            let flipped: Axis = s.axis == .x ? .y : .x
            return .split(Split(id: s.id, axis: flipped, children: s.children, weights: s.weights))
        }
    }

    public static func cycle(from windowID: String?, direction: CycleDirection, in root: LayoutNode) -> String? {
        let ids = tiledWindowIDs(in: root)
        guard !ids.isEmpty else { return nil }
        guard let windowID, let idx = ids.firstIndex(of: windowID) else { return ids.first }
        switch direction {
        case .next:
            return ids[(idx + 1) % ids.count]
        case .previous:
            return ids[(idx - 1 + ids.count) % ids.count]
        }
    }

    /// Grow (`delta` > 0) or shrink the focused tile against its neighbour.
    public static func resize(windowID: String,
                              delta: Double,
                              in root: LayoutNode,
                              engine: LayoutEngine = LayoutEngine()) throws -> LayoutNode {
        guard let panelID = resolvePanelID(windowID, in: root),
              let parent = root.parent(of: panelID),
              let idx = parent.children.firstIndex(where: { $0.id == panelID }) else {
            throw LayoutError.notFound("no split to resize for '\(windowID)'")
        }
        if let next = parent.children.dropFirst(idx + 1).first(where: { $0.id != "desktop" }) {
            return try engine.resizingGap(between: panelID, and: next.id, delta: delta, in: root)
        }
        if idx > 0 {
            let prev = parent.children[idx - 1]
            guard prev.id != "desktop" else {
                throw LayoutError.notFound("no sibling to resize against")
            }
            return try engine.resizingGap(between: prev.id, and: panelID, delta: -delta, in: root)
        }
        throw LayoutError.notFound("no sibling to resize against")
    }

    public static func neighbourWindow(of windowID: String,
                                       direction: CycleDirection,
                                       in root: LayoutNode) -> String? {
        cycle(from: windowID, direction: direction, in: root)
    }

    private static func rewrite(_ node: LayoutNode, replace: (LayoutNode) -> LayoutNode?) -> LayoutNode {
        if let swapped = replace(node) { return swapped }
        guard case .split(let s) = node else { return node }
        return .split(Split(id: s.id, axis: s.axis,
                            children: s.children.map { rewrite($0, replace: replace) },
                            weights: s.weights))
    }
}
