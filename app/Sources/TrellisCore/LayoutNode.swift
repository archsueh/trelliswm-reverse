import Foundation

/// Geometry in points, top-left origin (matches AX / NSWindow flipped coordinates).
public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double = 0, y: Double = 0, w: Double = 0, h: Double = 0) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    public var midX: Double { x + w / 2 }
    public var midY: Double { y + h / 2 }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
}

public struct Size: Codable, Equatable, Sendable {
    public var w: Double
    public var h: Double
    public init(w: Double = 0, h: Double = 0) { self.w = w; self.h = h }
}

public enum Axis: String, Codable, Equatable, Sendable {
    case x  // horizontal split: children laid out left → right
    case y  // vertical split: children laid out top → bottom
}

public enum Direction: String, Codable, Equatable, Sendable {
    case left, right, up, down
    public var axis: Axis { (self == .left || self == .right) ? .x : .y }
    public var isNegative: Bool { self == .left || self == .up }
}

/// A leaf holding one real window, or a tab group of them.
public struct Panel: Codable, Equatable, Sendable {
    public var id: String
    public var views: [String]
    public var selected: String?
    public var tabbed: Bool?

    public init(id: String, views: [String], selected: String? = nil, tabbed: Bool? = nil) {
        self.id = id
        self.views = views
        self.selected = selected ?? views.first
        self.tabbed = tabbed
    }

    public var isTabGroup: Bool { views.count > 1 }
}

/// A container. `children.count == weights.count`, `sum(weights) == 1`.
/// Children may themselves be splits — that recursion is the whole "fractal" model.
public struct Split: Codable, Equatable, Sendable {
    public var id: String
    public var axis: Axis
    public var children: [LayoutNode]
    public var weights: [Double]

    public init(id: String, axis: Axis, children: [LayoutNode], weights: [Double]? = nil) {
        self.id = id
        self.axis = axis
        self.children = children
        let n = max(children.count, 1)
        self.weights = LayoutNode.normalize(weights ?? Array(repeating: 1.0 / Double(n), count: children.count),
                                            to: children.count)
    }
}

/// Derived from the subject's own persisted layout documents (grammar in
/// capture/layout-schema.json). This is an independent implementation of that
/// observable document format; no subject source code is used.
public indirect enum LayoutNode: Codable, Equatable, Sendable {
    case desktop
    case panel(Panel)
    case split(Split)

    private enum Keys: String, CodingKey {
        case kind, id, axis, children, weights, views, selected, tabbed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "desktop":
            self = .desktop
        case "panel":
            let id = try c.decode(String.self, forKey: .id)
            let views = try c.decode([String].self, forKey: .views)
            let selected = try c.decodeIfPresent(String.self, forKey: .selected)
            let tabbed = try c.decodeIfPresent(Bool.self, forKey: .tabbed)
            self = .panel(Panel(id: id, views: views, selected: selected, tabbed: tabbed))
        case "split":
            let id = try c.decode(String.self, forKey: .id)
            let axis = try c.decode(Axis.self, forKey: .axis)
            let children = try c.decode([LayoutNode].self, forKey: .children)
            let weights = try c.decodeIfPresent([Double].self, forKey: .weights)
            self = .split(Split(id: id, axis: axis, children: children, weights: weights))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c, debugDescription: "unknown node kind '\(kind)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .desktop:
            try c.encode("desktop", forKey: .kind)
            try c.encode("desktop", forKey: .id)
        case .panel(let p):
            try c.encode("panel", forKey: .kind)
            try c.encode(p.id, forKey: .id)
            try c.encode(p.views, forKey: .views)
            try c.encodeIfPresent(p.selected, forKey: .selected)
            try c.encodeIfPresent(p.tabbed, forKey: .tabbed)
        case .split(let s):
            try c.encode("split", forKey: .kind)
            try c.encode(s.id, forKey: .id)
            try c.encode(s.axis, forKey: .axis)
            try c.encode(s.children, forKey: .children)
            try c.encode(s.weights, forKey: .weights)
        }
    }

    // MARK: - Identity & traversal

    public var id: String {
        switch self {
        case .desktop: return "desktop"
        case .panel(let p): return p.id
        case .split(let s): return s.id
        }
    }

    public var isLeaf: Bool {
        if case .split = self { return false }
        return true
    }

    public var children: [LayoutNode] {
        if case .split(let s) = self { return s.children }
        return []
    }

    /// Every node in pre-order, including self.
    public func flatten() -> [LayoutNode] {
        var out: [LayoutNode] = [self]
        for child in children { out += child.flatten() }
        return out
    }

    public func node(id wanted: String) -> LayoutNode? {
        flatten().first { $0.id == wanted }
    }

    /// The direct parent split of `childID`, or nil when it is the root / missing.
    public func parent(of childID: String) -> Split? {
        for n in flatten() {
            if case .split(let s) = n, s.children.contains(where: { $0.id == childID }) { return s }
        }
        return nil
    }

    public var leaves: [LayoutNode] { flatten().filter(\.isLeaf) }

    public func panel(containing seatID: String) -> Panel? {
        for n in flatten() {
            if case .panel(let p) = n, p.views.contains(seatID) { return p }
        }
        return nil
    }

    /// Depth of the deepest split. 0 means a bare desktop.
    public var nestingDepth: Int {
        guard case .split(let s) = self else { return 0 }
        return 1 + (s.children.map(\.nestingDepth).max() ?? 0)
    }

    // MARK: - Weight hygiene

    public static func normalize(_ weights: [Double], to count: Int) -> [Double] {
        guard count > 0 else { return [] }
        var w = Array(weights.prefix(count))
        if w.count < count { w += Array(repeating: 1.0 / Double(count), count: count - w.count) }
        w = w.map { max(0, $0) }
        let sum = w.reduce(0, +)
        if sum <= 0 { return Array(repeating: 1.0 / Double(count), count: count) }
        return w.map { $0 / sum }
    }

    /// Re-normalize every split in the tree. Cheap repair for imported documents.
    public func normalized() -> LayoutNode {
        guard case .split(let s) = self else { return self }
        let kids = s.children.map { $0.normalized() }
        return .split(Split(id: s.id, axis: s.axis, children: kids,
                            weights: LayoutNode.normalize(s.weights, to: kids.count)))
    }

    /// Structural invariants from capture/layout-schema.json.
    public func validate() throws {
        for n in flatten() {
            guard case .split(let s) = n else { continue }
            guard s.children.count == s.weights.count else {
                throw LayoutError.invariant("split '\(s.id)': \(s.children.count) children vs \(s.weights.count) weights")
            }
            guard !s.children.isEmpty else {
                throw LayoutError.invariant("split '\(s.id)' has no children")
            }
            guard s.weights.allSatisfy({ $0 >= 0 }) else {
                throw LayoutError.invariant("split '\(s.id)' has a negative weight")
            }
            let sum = s.weights.reduce(0, +)
            guard abs(sum - 1.0) < 1e-6 else {
                throw LayoutError.invariant("split '\(s.id)': weights sum to \(sum), expected 1.0")
            }
        }
        let desktops = flatten().filter { if case .desktop = $0 { return true } else { return false } }
        guard desktops.count == 1 else {
            throw LayoutError.invariant("expected exactly one desktop leaf, found \(desktops.count)")
        }
    }
}

public enum LayoutError: Error, Equatable, CustomStringConvertible {
    case invariant(String)
    case notFound(String)
    case invalidCommand(String)

    public var description: String {
        switch self {
        case .invariant(let m): return "invariant: \(m)"
        case .notFound(let m): return "not found: \(m)"
        case .invalidCommand(let m): return "invalid command: \(m)"
        }
    }
}
