import Foundation

/// Pure layout geometry + tree mutations. No AppKit, no Accessibility, no global state:
/// every operation returns a new tree, which makes the derived specification testable.
public struct LayoutEngine: Sendable {
    /// Space between sibling tiles (`gap` in ReleaseSettings.json, default 12 pt).
    public var gap: Double
    /// Smallest share a tile may be squeezed to when resizing (`squeezeBelowMinimum`).
    public var minimumShare: Double

    public init(gap: Double = 12, minimumShare: Double = 0.05) {
        self.gap = max(0, gap)
        self.minimumShare = min(max(0.001, minimumShare), 0.49)
    }

    // MARK: - Geometry

    /// Map every node id to its rectangle inside `frame`. Split weights consume the
    /// space left after `(children.count - 1) * gap` has been removed.
    public func rects(for root: LayoutNode, in frame: Rect) -> [String: Rect] {
        var out: [String: Rect] = [:]
        place(root, frame, &out)
        return out
    }

    private func place(_ node: LayoutNode, _ frame: Rect, _ out: inout [String: Rect]) {
        out[node.id] = frame
        guard case .split(let s) = node, !s.children.isEmpty else { return }
        let count = s.children.count
        let total = (s.axis == .x) ? frame.w : frame.h
        let usable = max(0, total - gap * Double(count - 1))
        var cursor = (s.axis == .x) ? frame.x : frame.y
        for (i, child) in s.children.enumerated() {
            let length = usable * s.weights[i]
            let childFrame: Rect
            if s.axis == .x {
                childFrame = Rect(x: cursor, y: frame.y, w: length, h: frame.h)
            } else {
                childFrame = Rect(x: frame.x, y: cursor, w: frame.w, h: length)
            }
            place(child, childFrame, &out)
            cursor += length + gap
        }
    }

    // MARK: - Docking (insert)

    /// Dock `panel` against `targetID` on the given edge.
    ///
    /// Strategy (derived from the guide's "neighbours make room" + the observed
    /// split grammar; the exact heuristic is the one low-confidence item, see
    /// investigation.cany/questions.md Q13):
    ///   • parent split has the same axis → insert as a sibling, taking half of
    ///     the target's weight;
    ///   • parent split has the other axis → wrap the target in a new split on
    ///     that axis, so nesting grows one level;
    ///   • target is the root leaf → create a new root split, keeping the
    ///     `desktop` leaf intact.
    public func inserting(panel: LayoutNode,
                          adjacentTo targetID: String,
                          edge: Direction,
                          in root: LayoutNode) throws -> LayoutNode {
        guard root.node(id: targetID) != nil else {
            throw LayoutError.notFound("target '\(targetID)'")
        }
        let (result, didInsert) = insert(panel, targetID, edge, root, root)
        guard didInsert else { throw LayoutError.notFound("target '\(targetID)' is not dockable") }
        try result.validate()
        return result
    }

    private func insert(_ new: LayoutNode, _ targetID: String, _ edge: Direction,
                        _ node: LayoutNode, _ root: LayoutNode) -> (LayoutNode, Bool) {
        if case .split(let s) = node {
            if let idx = s.children.firstIndex(where: { $0.id == targetID }) {
                let newID = freshSplitID(in: root)
                if s.axis == edge.axis {
                    var kids = s.children
                    var weights = s.weights
                    let share = weights[idx] / 2
                    weights[idx] -= share
                    let at = edge.isNegative ? idx : idx + 1
                    kids.insert(new, at: at)
                    weights.insert(share, at: at)
                    let updated = Split(id: s.id, axis: s.axis, children: kids, weights: weights)
                    return (.split(updated), true)
                } else {
                    var kids = s.children
                    let pair: [LayoutNode] = edge.isNegative ? [new, kids[idx]] : [kids[idx], new]
                    kids[idx] = .split(Split(id: newID, axis: edge.axis,
                                             children: pair, weights: [0.5, 0.5]))
                    let updated = Split(id: s.id, axis: s.axis, children: kids, weights: s.weights)
                    return (.split(updated), true)
                }
            }
            var kids = s.children
            for i in kids.indices {
                let (child, done) = insert(new, targetID, edge, kids[i], root)
                if done {
                    kids[i] = child
                    return (.split(Split(id: s.id, axis: s.axis, children: kids, weights: s.weights)), true)
                }
            }
            return (node, false)
        }

        if node.id == targetID {
            // Never dock *into* the desktop; put the panel beside it.
            let pair: [LayoutNode] = edge.isNegative ? [new, node] : [node, new]
            return (.split(Split(id: freshSplitID(in: root), axis: edge.axis,
                                 children: pair, weights: [0.5, 0.5])), true)
        }
        return (node, false)
    }

    private func freshSplitID(in root: LayoutNode) -> String {
        let existing = Set(root.flatten().map(\.id))
        var n = root.flatten().count
        var candidate = "split-gen\(n)"
        while existing.contains(candidate) {
            n += 1
            candidate = "split-gen\(n)"
        }
        return candidate
    }

    // MARK: - Removal

    /// Remove a docked panel (or an entire sub-split). A split left with one
    /// child collapses into that child — the layout "makes room" on close.
    /// The `desktop` leaf is protected.
    public func removing(nodeID: String, from root: LayoutNode) throws -> LayoutNode {
        guard root.node(id: nodeID) != nil else { throw LayoutError.notFound("node '\(nodeID)'") }
        guard nodeID != "desktop" else { throw LayoutError.invariant("the desktop leaf cannot be removed") }
        let (result, didRemove) = remove(nodeID, root)
        guard didRemove else { throw LayoutError.notFound("node '\(nodeID)' is not removable") }
        try result.validate()
        return result
    }

    private func remove(_ id: String, _ node: LayoutNode) -> (LayoutNode, Bool) {
        guard case .split(let s) = node else { return (node, false) }
        if let idx = s.children.firstIndex(where: { $0.id == id }) {
            var kids = s.children
            if case .desktop = kids[idx] { return (node, false) }
            kids.remove(at: idx)
            var weights = s.weights
            weights.remove(at: idx)
            if kids.count == 1 { return (kids[0], true) }   // collapse
            return (.split(Split(id: s.id, axis: s.axis, children: kids,
                                 weights: LayoutNode.normalize(weights, to: kids.count))), true)
        }
        var kids = s.children
        for i in kids.indices {
            let (child, done) = remove(id, kids[i])
            if done {
                kids[i] = child
                return (.split(Split(id: s.id, axis: s.axis, children: kids, weights: s.weights)), true)
            }
        }
        return (node, false)
    }

    // MARK: - Gap resize

    /// Drag the gap between two sibling leaves. `delta` is a fraction of the
    /// parent's usable length (positive moves it toward `secondID`).
    public func resizingGap(between firstID: String, and secondID: String,
                            delta: Double, in root: LayoutNode) throws -> LayoutNode {
        guard let parent = root.parent(of: firstID), parent.children.contains(where: { $0.id == secondID }) else {
            throw LayoutError.notFound("'\(firstID)' and '\(secondID)' are not siblings")
        }
        guard let a = parent.children.firstIndex(where: { $0.id == firstID }),
              let b = parent.children.firstIndex(where: { $0.id == secondID }),
              abs(a - b) == 1 else {
            throw LayoutError.invariant("gap drag requires adjacent siblings")
        }
        let result = resize(parentID: parent.id, a: min(a, b), b: max(a, b), delta: delta, node: root)
        try result.validate()
        return result
    }

    private func resize(parentID: String, a: Int, b: Int, delta: Double, node: LayoutNode) -> LayoutNode {
        guard case .split(let s) = node else { return node }
        if s.id == parentID {
            var weights = s.weights
            // Positive delta grows `a` and shrinks `b`; negative does the reverse.
            // Each side is floored at minimumShare, so neither can go negative and
            // then get silently swallowed by normalization.
            let upper = max(0, weights[b] - minimumShare)
            let lower = min(0, -(weights[a] - minimumShare))
            let clamped = delta >= 0 ? min(delta, upper) : max(delta, lower)
            weights[a] += clamped
            weights[b] -= clamped
            return .split(Split(id: s.id, axis: s.axis, children: s.children, weights: weights))
        }
        let kids = s.children.map { resize(parentID: parentID, a: a, b: b, delta: delta, node: $0) }
        return .split(Split(id: s.id, axis: s.axis, children: kids, weights: s.weights))
    }

    // MARK: - Neighbouring space & camera targets

    /// The nearest leaf in `direction` from `fromID`, measured in laid-out space.
    /// This models "the neighbouring space", not a macOS Space switch.
    public func neighbour(of fromID: String, direction: Direction,
                          in root: LayoutNode, frame: Rect) -> String? {
        let r = rects(for: root, in: frame)
        guard let origin = r[fromID] else { return nil }
        let candidates = root.leaves.filter { $0.id != fromID && $0.id != "desktop" }
        let viable = candidates.compactMap { n -> (String, Double)? in
            guard let c = r[n.id] else { return nil }
            let along: Double
            let cross: Double
            switch direction {
            case .left:
                along = origin.midX - c.midX; cross = abs(origin.midY - c.midY)
                guard along > 0 else { return nil }
            case .right:
                along = c.midX - origin.midX; cross = abs(origin.midY - c.midY)
                guard along > 0 else { return nil }
            case .up:
                along = origin.midY - c.midY; cross = abs(origin.midX - c.midX)
                guard along > 0 else { return nil }
            case .down:
                along = c.midY - origin.midY; cross = abs(origin.midX - c.midX)
                guard along > 0 else { return nil }
            }
            return (n.id, along + cross * 0.001)
        }
        return viable.min { $0.1 < $1.1 }?.0
    }

    /// Ancestor chain from root to `nodeID`, used by the camera for step in/out.
    public func path(to nodeID: String, in root: LayoutNode) -> [String] {
        func walk(_ node: LayoutNode, _ acc: [String]) -> [String]? {
            if node.id == nodeID { return acc + [node.id] }
            if case .split(let s) = node {
                for child in s.children {
                    if let found = walk(child, acc + [node.id]) { return found }
                }
            }
            return nil
        }
        return walk(root, []) ?? [root.id]
    }

    /// Zoom targets: a docked panel's own subtree, or the deepest split
    /// containing the given seat. Used by `zoom-in` / "step in toward pointer".
    public func zoomTarget(containing seatID: String, in root: LayoutNode) -> String? {
        func walk(_ node: LayoutNode, _ parent: String?) -> String? {
            switch node {
            case .desktop:
                return nil
            case .panel(let p):
                return p.views.contains(seatID) ? (parent ?? p.id) : nil
            case .split(let s):
                for child in s.children {
                    if let hit = walk(child, node.id) { return hit }
                }
                return nil
            }
        }
        return walk(root, nil)
    }
}
