import Foundation

/// Re-solves a tiling after some windows have clamped their size
/// (application minimum width or height).
///
/// Approach:
/// - A tile is clamped on an axis when its actual size differs from the
///   requested size by more than `tolerance` (default 2 pt). The common
///   case is a minimum width: the window comes out wider than the tile.
/// - Walk the split tree. At each split, a child's minimum along the
///   split axis is its clamped size (or, for a nested split, the packed
///   minimum of its descendants). Flexible children share leftover space
///   in proportion to their original requested sizes.
/// - The configured gap is preserved between siblings.
/// - If clamped minima plus gaps exceed the frame, children are packed
///   from the origin and may extend past the trailing edge. They never
///   overlap. Flexible children shrink (to zero if needed) rather than
///   overlapping a clamped neighbour.
/// - Nested splits are resolved recursively inside the region assigned
///   to that child.
public enum ClampResolver: Sendable {

    public static let defaultTolerance: Double = 2

    public static func resolve(tree: LayoutNode,
                               requested: [String: Rect],
                               actual: [String: Rect],
                               frame: Rect,
                               gap: Double,
                               tolerance: Double = defaultTolerance) -> [String: Rect] {
        var out: [String: Rect] = [:]
        place(tree, in: frame, requested: requested, actual: actual,
              gap: gap, tolerance: tolerance, out: &out)
        return out
    }

    /// Pack lengths along one axis. Items with `flexShares[i] == 0` keep
    /// `mins[i]`. Flexible items share leftover space proportional to
    /// their shares. When minima plus gaps exceed `total`, minima are
    /// kept and the pack overflows the trailing edge.
    public static func pack(mins: [Double], flexShares: [Double], total: Double, gap: Double) -> [Double] {
        let n = mins.count
        precondition(flexShares.count == n)
        guard n > 0 else { return [] }
        let reserved = mins.reduce(0, +) + gap * Double(n - 1)
        let leftover = total - reserved
        let flexTotal = flexShares.reduce(0, +)
        if leftover >= 0, flexTotal > 0 {
            return zip(mins, flexShares).map { minLen, share in
                minLen + leftover * (share / flexTotal)
            }
        }
        return mins
    }

    // MARK: - Tree walk

    private static func place(_ node: LayoutNode,
                              in frame: Rect,
                              requested: [String: Rect],
                              actual: [String: Rect],
                              gap: Double,
                              tolerance: Double,
                              out: inout [String: Rect]) {
        out[node.id] = frame
        guard case .split(let s) = node, !s.children.isEmpty else { return }

        let kids = s.children
        var mins = [Double](repeating: 0, count: kids.count)
        var flex = [Double](repeating: 0, count: kids.count)
        for (i, child) in kids.enumerated() {
            let reqLen = requestedLength(child, axis: s.axis, requested: requested)
            let minLen = minimumLength(child, axis: s.axis, requested: requested,
                                       actual: actual, gap: gap, tolerance: tolerance)
            mins[i] = minLen
            flex[i] = max(0, reqLen - minLen)
        }

        let total = (s.axis == .x) ? frame.w : frame.h
        let origin = (s.axis == .x) ? frame.x : frame.y
        let lengths = pack(mins: mins, flexShares: flex, total: total, gap: gap)
        var cursor = origin
        for (i, child) in kids.enumerated() {
            let length = lengths[i]
            let childFrame: Rect = s.axis == .x
                ? Rect(x: cursor, y: frame.y, w: length, h: frame.h)
                : Rect(x: frame.x, y: cursor, w: frame.w, h: length)
            place(child, in: childFrame, requested: requested, actual: actual,
                  gap: gap, tolerance: tolerance, out: &out)
            cursor += length + gap
        }
    }

    private static func requestedLength(_ node: LayoutNode, axis: Axis, requested: [String: Rect]) -> Double {
        if let r = requested[node.id] {
            return axis == .x ? r.w : r.h
        }
        let rects = panelIDs(in: node).compactMap { requested[$0] }
        guard !rects.isEmpty else { return 0 }
        if axis == .x {
            return (rects.map(\.maxX).max() ?? 0) - (rects.map(\.x).min() ?? 0)
        }
        return (rects.map(\.maxY).max() ?? 0) - (rects.map(\.y).min() ?? 0)
    }

    private static func minimumLength(_ node: LayoutNode,
                                      axis: Axis,
                                      requested: [String: Rect],
                                      actual: [String: Rect],
                                      gap: Double,
                                      tolerance: Double) -> Double {
        switch node {
        case .desktop:
            return 0
        case .panel(let p):
            guard let a = actual[p.id] else { return 0 }
            let actualLen = axis == .x ? a.w : a.h
            let reqLen = requested[p.id].map { axis == .x ? $0.w : $0.h } ?? actualLen
            return abs(actualLen - reqLen) > tolerance ? actualLen : 0
        case .split(let s):
            let childMins = s.children.map {
                minimumLength($0, axis: axis, requested: requested, actual: actual,
                              gap: gap, tolerance: tolerance)
            }
            if s.axis == axis {
                return childMins.reduce(0, +) + gap * Double(max(0, s.children.count - 1))
            }
            return childMins.max() ?? 0
        }
    }

    private static func panelIDs(in node: LayoutNode) -> [String] {
        switch node {
        case .desktop: return []
        case .panel(let p): return [p.id]
        case .split(let s): return s.children.flatMap { panelIDs(in: $0) }
        }
    }
}
