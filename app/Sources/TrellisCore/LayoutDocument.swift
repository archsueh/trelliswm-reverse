import Foundation

/// One floating window on the Desktop. In the observed documents the `panel`
/// object has no `kind` key, so it decodes directly into `Panel`.
public struct FloatingWindow: Codable, Equatable, Sendable {
    public var panel: Panel
    public var rect: Rect
    public var size: Size
    public var z: Int?
}

public struct LayoutDocument: Codable, Equatable, Sendable {
    public var root: LayoutNode
    public var floating: [FloatingWindow]
    public var hidden: [String]

    public init(root: LayoutNode = .desktop,
                floating: [FloatingWindow] = [],
                hidden: [String] = []) {
        self.root = root; self.floating = floating; self.hidden = hidden
    }
}

/// Top-level shape of `layout-<displayUUID>|desktop-1.json` (version 2).
/// Keys whose internal shape is not established (`seats`, `session`, `owners`)
/// are deliberately not declared — Swift's decoder ignores them, so importing a
/// real document never fails on an unknown value type. Their field lists are
/// recorded in capture/layout-schema.json for reference.
public struct LayoutFile: Codable, Equatable, Sendable {
    public var doc: LayoutDocument
    public var dockSpots: [String: Rect]
    public var floatSizes: [String: Size]
    public var framed: String
    public var framings: [String: Rect]
    public var framedLeaves: [String]
    public var saved: Double?
    public var version: Int
    public var world: String?
    public var mirrorDigest: String?
    public var saltDigest: String?

    private enum Keys: String, CodingKey {
        case doc, dockSpots, floatSizes, framed, framings, framedLeaves
        case saved, version, world, mirrorDigest, saltDigest
    }

    public init(doc: LayoutDocument = LayoutDocument(),
                dockSpots: [String: Rect] = [:],
                floatSizes: [String: Size] = [:],
                framed: String = "desktop",
                framings: [String: Rect] = [:],
                framedLeaves: [String] = [],
                saved: Double? = nil,
                version: Int = 2,
                world: String? = nil) {
        self.doc = doc; self.dockSpots = dockSpots; self.floatSizes = floatSizes
        self.framed = framed; self.framings = framings; self.framedLeaves = framedLeaves
        self.saved = saved; self.version = version; self.world = world
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        doc = try c.decode(LayoutDocument.self, forKey: .doc)
        // Tolerate shape drift in these dictionaries without failing import.
        // `try? decodeIfPresent` is doubly optional: flatten then default.
        let spots: [String: Rect]?? = try? c.decodeIfPresent([String: Rect].self, forKey: .dockSpots)
        let sizes: [String: Size]?? = try? c.decodeIfPresent([String: Size].self, forKey: .floatSizes)
        let frames: [String: Rect]?? = try? c.decodeIfPresent([String: Rect].self, forKey: .framings)
        let leaves: [String]?? = try? c.decodeIfPresent([String].self, forKey: .framedLeaves)
        dockSpots = spots.flatMap { $0 } ?? [:]
        floatSizes = sizes.flatMap { $0 } ?? [:]
        framed = try c.decodeIfPresent(String.self, forKey: .framed) ?? "desktop"
        framings = frames.flatMap { $0 } ?? [:]
        framedLeaves = leaves.flatMap { $0 } ?? []
        saved = try c.decodeIfPresent(Double.self, forKey: .saved)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 2
        world = try c.decodeIfPresent(String.self, forKey: .world)
        mirrorDigest = try c.decodeIfPresent(String.self, forKey: .mirrorDigest)
        saltDigest = try c.decodeIfPresent(String.self, forKey: .saltDigest)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(doc, forKey: .doc)
        try c.encode(dockSpots, forKey: .dockSpots)
        try c.encode(floatSizes, forKey: .floatSizes)
        try c.encode(framed, forKey: .framed)
        try c.encode(framings, forKey: .framings)
        try c.encode(framedLeaves, forKey: .framedLeaves)
        try c.encodeIfPresent(saved, forKey: .saved)
        try c.encode(version, forKey: .version)
        try c.encodeIfPresent(world, forKey: .world)
        try c.encodeIfPresent(mirrorDigest, forKey: .mirrorDigest)
        try c.encodeIfPresent(saltDigest, forKey: .saltDigest)
    }
}

public enum LayoutFixtures {
    /// A three-level fractal tree, built independently for demonstration and
    /// testing. Mirrors the *shape* seen in departures.json, not its data.
    public static func fractalTree() -> LayoutNode {
        let a = LayoutNode.panel(Panel(id: "p-notes", views: ["s-notes"]))
        let b = LayoutNode.panel(Panel(id: "p-browser", views: ["s-browser"]))
        let c = LayoutNode.panel(Panel(id: "p-terminal", views: ["s-terminal", "s-logs"], tabbed: true))
        let d = LayoutNode.panel(Panel(id: "p-editor", views: ["s-editor"]))
        let inner = LayoutNode.split(Split(id: "split-inner", axis: .y,
                                           children: [c, d], weights: [0.5, 0.5]))
        let row = LayoutNode.split(Split(id: "split-row", axis: .x,
                                         children: [a, b, inner],
                                         weights: [0.3, 0.3, 0.4]))
        return .split(Split(id: "root", axis: .x,
                            children: [row, .desktop],
                            weights: [0.72, 0.28]))
    }

    public static func document() -> LayoutFile {
        LayoutFile(doc: LayoutDocument(root: fractalTree()), framed: "desktop",
                   version: 2, world: "simulated-display|desktop-1")
    }
}
