import XCTest
@testable import TrellisCore

final class TrellisCoreTests: XCTestCase {

    // A scrubbed transcription of a real nested template from departures.json
    // (see capture/layout-sample.json). Weights are the observed values.
    private let observedTreeJSON = """
    {
      "kind": "split", "id": "split-root", "axis": "y",
      "children": [
        {
          "kind": "split", "id": "split-row", "axis": "x",
          "children": [
            {"kind": "panel", "id": "p1", "views": ["w1"], "selected": "w1"},
            {"kind": "panel", "id": "p2", "views": ["w2"], "selected": "w2"},
            {
              "kind": "split", "id": "split-col", "axis": "y",
              "children": [
                {"kind": "panel", "id": "p3", "views": ["w3"], "selected": "w3"},
                {"kind": "panel", "id": "p4", "views": ["w4"], "selected": "w4"}
              ],
              "weights": [0.5, 0.5]
            },
            {"kind": "panel", "id": "p5", "views": ["w5"], "selected": "w5"}
          ],
          "weights": [0.5853658536585367, 0.01219512195121951, 0.01219512195121951, 0.39024390243902435]
        },
        {"kind": "desktop", "id": "desktop"}
      ],
      "weights": [0.6666666666666666, 0.3333333333333333]
    }
    """

    private func observedTree() throws -> LayoutNode {
        try JSONDecoder().decode(LayoutNode.self, from: Data(observedTreeJSON.utf8))
    }

    // MARK: - Observed document format

    func testDecodeObservedSplitTree() throws {
        let tree = try observedTree()
        try tree.validate()
        XCTAssertEqual(tree.nestingDepth, 3, "observed templates nest three split levels")
        XCTAssertEqual(tree.leaves.count, 6)          // 5 panels + 1 desktop
        XCTAssertEqual(tree.node(id: "p3")?.id, "p3")
        XCTAssertEqual(tree.parent(of: "p3")?.id, "split-col")
        XCTAssertTrue(tree.node(id: "desktop") != nil)
    }

    func testLayoutFileIgnoresUnknownSeatShape() throws {
        let json = """
        {
          "doc": {"root": {"kind":"desktop","id":"desktop"}, "floating": [], "hidden": []},
          "dockSpots": {}, "floatSizes": {}, "framed": "desktop", "framings": {},
          "framedLeaves": [], "saved": 1794206168.34, "version": 2,
          "world": "display|desktop-1", "mirrorDigest": "abc", "saltDigest": "def",
          "seats": {"s-1": {"titles": ["anything"], "pid": 42, "session": {"boot": "x"}}},
          "session": {"began": 1, "boot": "x", "bootTime": 0, "login": "y"},
          "owners": {"w1": "s-1"}
        }
        """
        let file = try JSONDecoder().decode(LayoutFile.self, from: Data(json.utf8))
        XCTAssertEqual(file.version, 2)
        XCTAssertEqual(file.framed, "desktop")
        XCTAssertEqual(file.doc.root.id, "desktop")
        let round = try JSONEncoder().encode(file)
        XCTAssertNoThrow(try JSONDecoder().decode(LayoutFile.self, from: round))
    }

    func testFloatingPanelHasNoKindKey() throws {
        let json = """
        {"panel":{"id":"p1","selected":"w1","tabbed":false,"views":["w1"]},
         "rect":{"x":10,"y":20,"w":300,"h":200},"size":{"w":300,"h":200},"z":3}
        """
        let f = try JSONDecoder().decode(FloatingWindow.self, from: Data(json.utf8))
        XCTAssertEqual(f.panel.id, "p1")
        XCTAssertEqual(f.rect.w, 300)
    }

    // MARK: - Geometry

    func testRectsRespectGapAndWeights() throws {
        let tree = try observedTree()
        let engine = LayoutEngine(gap: 12)
        let r = engine.rects(for: tree, in: Rect(x: 0, y: 0, w: 1000, h: 800))
        // root is a y-split: 800 - 12 gap = 788 usable; top gets 2/3.
        XCTAssertEqual(r["split-row"]!.h, 788 * 2.0 / 3.0, accuracy: 1e-6)
        XCTAssertEqual(r["desktop"]!.h, 788 / 3.0, accuracy: 1e-6)
        XCTAssertEqual(r["desktop"]!.y, 788 * 2.0 / 3.0 + 12, accuracy: 1e-6)
        // five panels + desktop + 4 containers are all laid out
        XCTAssertEqual(r.count, tree.flatten().count)
    }

    func testZeroGapMatchesFrameExactly() {
        let tree = LayoutFixtures.fractalTree()
        let r = LayoutEngine(gap: 0).rects(for: tree, in: Rect(w: 1920, h: 1080))
        XCTAssertEqual(r[tree.id]!.w, 1920)
        for (_, rect) in r {
            XCTAssertGreaterThanOrEqual(rect.w, 0)
            XCTAssertGreaterThanOrEqual(rect.h, 0)
        }
    }

    // MARK: - Docking / removal / resize

    func testInsertOnSameAxisAddsSibling() throws {
        let tree = try observedTree()
        let newPanel = LayoutNode.panel(Panel(id: "p-new", views: ["w-new"]))
        let result = try LayoutEngine().inserting(panel: newPanel, adjacentTo: "p1",
                                                  edge: .right, in: tree)
        try result.validate()
        XCTAssertEqual(result.parent(of: "p-new")?.id, "split-row")
        XCTAssertEqual(result.parent(of: "p1")?.children.count, 5)
        XCTAssertEqual(result.nestingDepth, tree.nestingDepth, "same-axis insert must not add a level")
    }

    func testInsertOnCrossAxisGrowsNesting() throws {
        let tree = try observedTree()
        let newPanel = LayoutNode.panel(Panel(id: "p-new", views: ["w-new"]))
        let result = try LayoutEngine().inserting(panel: newPanel, adjacentTo: "p1",
                                                  edge: .down, in: tree)
        try result.validate()
        // p1 is wrapped in a new y-split. Global depth does not grow here only
        // because a sibling branch (split-col) was already at that depth.
        XCTAssertEqual(result.parent(of: "p-new")?.axis, .y)
        XCTAssertEqual(result.parent(of: "p1")?.id, result.parent(of: "p-new")?.id)
        XCTAssertEqual(result.node(id: "split-row")?.children.count, 4)

        // On a shallow tree the same operation must add exactly one level.
        let shallow = LayoutNode.split(Split(id: "r", axis: .x,
                                             children: [.panel(Panel(id: "only", views: ["s1"])), .desktop],
                                             weights: [0.5, 0.5]))
        let grown = try LayoutEngine().inserting(panel: newPanel, adjacentTo: "only",
                                                 edge: .down, in: shallow)
        XCTAssertEqual(grown.nestingDepth, shallow.nestingDepth + 1)
    }

    func testDesktopIsProtectedAndPreserved() throws {
        let tree = try observedTree()
        XCTAssertThrowsError(try LayoutEngine().removing(nodeID: "desktop", from: tree))
        let docked = try LayoutEngine().inserting(
            panel: .panel(Panel(id: "p-new", views: ["w-new"])),
            adjacentTo: "desktop", edge: .left, in: tree)
        XCTAssertEqual(docked.leaves.filter { $0.id == "desktop" }.count, 1)
    }

    func testRemoveCollapsesParentSplit() throws {
        let tree = try observedTree()
        let result = try LayoutEngine().removing(nodeID: "p3", from: tree)
        try result.validate()
        XCTAssertNil(result.node(id: "p3"))
        XCTAssertNil(result.node(id: "split-col"), "a one-child split collapses")
        XCTAssertNotNil(result.node(id: "p4"))
    }

    func testResizeGapPreservesSumAndClamps() throws {
        let tree = LayoutFixtures.fractalTree()   // siblings at 0.3 / 0.3 / 0.4
        let engine = LayoutEngine(minimumShare: 0.05)
        let resized = try engine.resizingGap(between: "p-notes", and: "p-browser",
                                             delta: 0.1, in: tree)
        try resized.validate()
        let before = tree.parent(of: "p-notes")!.weights
        let after = resized.parent(of: "p-notes")!.weights
        XCTAssertEqual(after.reduce(0, +), 1.0, accuracy: 1e-9)
        XCTAssertEqual(after[0], before[0] + 0.1, accuracy: 1e-9)
        XCTAssertEqual(after[1], before[1] - 0.1, accuracy: 1e-9)

        let huge = try engine.resizingGap(between: "p-notes", and: "p-browser",
                                          delta: 99, in: tree)
        try huge.validate()
        let clamped = huge.parent(of: "p-browser")!.weights
        XCTAssertEqual(clamped[1], 0.05, accuracy: 1e-9, "a sibling cannot be squeezed past minimumShare")
        XCTAssertTrue(clamped.allSatisfy { $0 >= 0 })
    }

    func testNeighbourUsesSpatialLayout() throws {
        let tree = LayoutFixtures.fractalTree()
        let engine = LayoutEngine(gap: 12)
        let frame = Rect(w: 1920, h: 1080)
        XCTAssertEqual(engine.neighbour(of: "p-notes", direction: .right, in: tree, frame: frame),
                       "p-browser")
        XCTAssertNil(engine.neighbour(of: "p-editor", direction: .right, in: tree, frame: frame))
    }

    // MARK: - Camera

    func testCameraStepOutInAndBrowserHistory() throws {
        let tree = LayoutFixtures.fractalTree()
        let camera = Camera(engine: LayoutEngine())
        let frame = Rect(w: 1920, h: 1080)
        var state = CameraState(framed: "p-terminal")
        state = camera.apply(.zoomOut, to: state, in: tree, frame: frame)
        XCTAssertEqual(state.framed, "split-inner")
        state = camera.apply(.back, to: state, in: tree, frame: frame)
        XCTAssertEqual(state.framed, "p-terminal")
        state = camera.apply(.forward, to: state, in: tree, frame: frame)
        XCTAssertEqual(state.framed, "split-inner")
        state = camera.apply(.everything, to: state, in: tree, frame: frame)
        XCTAssertEqual(state.framed, "root")
        XCTAssertTrue(state.forwardStack.isEmpty, "a new move clears forward history")
    }

    func testFrameAgainGoesBackAndSavedViews() throws {
        let tree = LayoutFixtures.fractalTree()
        let camera = Camera()
        let frame = Rect(w: 1920, h: 1080)
        var state = CameraState()
        state = camera.apply(.frame(nodeID: "p-editor"), to: state, in: tree, frame: frame)
        XCTAssertEqual(state.framed, "p-editor")
        state = camera.apply(.saveView(3), to: state, in: tree, frame: frame)
        state = camera.apply(.everything, to: state, in: tree, frame: frame)
        state = camera.apply(.goToView(3), to: state, in: tree, frame: frame)
        XCTAssertEqual(state.framed, "p-editor")
        state = camera.apply(.frame(nodeID: "p-editor"), to: state, in: tree, frame: frame)
        XCTAssertEqual(state.framed, "root", "framing the same node again returns")
        XCTAssertNoThrow(camera.apply(.saveView(99), to: state, in: tree, frame: frame))
    }

    func testZoomInTowardSeat() throws {
        let tree = LayoutFixtures.fractalTree()
        let camera = Camera()
        let state = camera.apply(.zoomIn(towardSeat: "s-terminal"), to: CameraState(),
                                 in: tree, frame: Rect(w: 1920, h: 1080))
        XCTAssertEqual(state.framed, "split-inner")
    }

    // MARK: - Commands & settings

    func testAllPublishedCommandsParse() throws {
        let parser = CommandURL()
        let urls = [
            "trelliswm://everything", "trelliswm://zoom-out", "trelliswm://zoom-in",
            "trelliswm://back", "trelliswm://forward", "trelliswm://neighbour?dir=left",
            "trelliswm://frame-window", "trelliswm://frame-desktop",
            "trelliswm://toggle-desktop", "trelliswm://view?n=1",
            "trelliswm://save-view?n=1", "trelliswm://split-finder",
            "trelliswm://arrange", "trelliswm://float-all",
            "trelliswm://settings?pane=shortcuts",
        ]
        XCTAssertEqual(urls.count, 15)
        let parsed = try urls.map { try parser.parse($0) }
        XCTAssertEqual(Set(parsed.map { parser.url(for: $0) }).count, 15)
        XCTAssertEqual(try parser.parse("trelliswm://view?n=9"), .view(9))
        XCTAssertEqual(try parser.parse("trelliswm://settings?pane=license"), .settings(.license))
        XCTAssertEqual(try parser.parse("trellisprobe://everything"), .everything)
    }

    func testCommandRejectsBadInput() {
        let parser = CommandURL()
        XCTAssertThrowsError(try parser.parse("https://example.com"))
        XCTAssertThrowsError(try parser.parse("trelliswm://view?n=10"))
        XCTAssertThrowsError(try parser.parse("trelliswm://neighbour?dir=sideways"))
        XCTAssertThrowsError(try parser.parse("trelliswm://nope"))
    }

    func testSettingsHas47ReleaseDefaults() throws {
        XCTAssertEqual(Settings.keyCount, 47)
        XCTAssertEqual(Settings.release.gap, 12)
        XCTAssertEqual(Settings.release.previewStyle, "tinted")
        XCTAssertEqual(Settings.release.returnReopenedWindows, "afterQuit")
        let obj = try Settings.release.asJSONObject()
        XCTAssertEqual(obj.count, 47)
    }

    func testSettingsPanesMatchGuide() {
        XCTAssertEqual(Set(SettingsPane.allCases.map(\.rawValue)),
                       Set(["general", "windows", "tabs", "appearance",
                            "gestures", "apps", "shortcuts", "license"]))
    }
}
