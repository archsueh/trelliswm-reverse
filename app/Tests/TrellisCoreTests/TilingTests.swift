import XCTest
@testable import TrellisCore

final class TilingTests: XCTestCase {

    private func snapshot(_ id: String,
                          bundle: String = "com.apple.Safari",
                          pid: Int32 = 42,
                          role: String = "AXWindow",
                          subrole: String = "AXStandardWindow",
                          minimized: Bool = false,
                          fullscreen: Bool = false,
                          main: Bool = true,
                          policy: ProcessActivationPolicy = .regular) -> WindowSnapshot {
        WindowSnapshot(id: id, ownerName: "Safari", bundleID: bundle, pid: pid,
                       role: role, subrole: subrole, isMinimized: minimized,
                       isFullscreen: fullscreen, isOnMainDisplay: main,
                       activationPolicy: policy)
    }

    // MARK: - Admission filter

    func testAdmissionKeepsStandardRegularWindows() {
        let ok = snapshot("w1")
        XCTAssertTrue(WindowAdmission.admits(ok, ownPID: 7))
        XCTAssertEqual(WindowAdmission.admitted([ok], ownPID: 7).map(\.id), ["w1"])
    }

    func testAdmissionRejectsMinimizedFullscreenOwnAccessoryAndForeign() {
        let ownPID: Int32 = 99
        let cases: [(String, WindowSnapshot)] = [
            ("minimized", snapshot("a", minimized: true)),
            ("fullscreen", snapshot("b", fullscreen: true)),
            ("own pid", snapshot("c", pid: ownPID)),
            ("zero pid", snapshot("d", pid: 0)),
            ("accessory", snapshot("e", policy: .accessory)),
            ("prohibited", snapshot("f", policy: .prohibited)),
            ("dialog", snapshot("g", subrole: "AXDialog")),
            ("non-window", snapshot("h", role: "AXUnknown")),
            ("off main", snapshot("i", main: false)),
            ("original wm", snapshot("j", bundle: "app.trellisui.trelliswm", pid: 8)),
            ("our wm", snapshot("k", bundle: "app.trellisreverse.wm", pid: 9)),
            ("studio", snapshot("l", bundle: "app.trellisreverse.studio", pid: 10)),
        ]
        for (name, window) in cases {
            XCTAssertFalse(WindowAdmission.admits(window, ownPID: ownPID), "should reject \(name)")
        }
        let mixed = cases.map(\.1) + [snapshot("keep", pid: 11)]
        XCTAssertEqual(WindowAdmission.admitted(mixed, ownPID: ownPID).map(\.id), ["keep"])
    }

    // MARK: - Tree mapping

    func testBuildEmptyIsDesktop() throws {
        let tree = TilingLayout.build(windowIDs: [])
        try tree.validate()
        XCTAssertEqual(tree.id, "desktop")
        XCTAssertNil(TilingLayout.tilingSubtree(of: tree))
        XCTAssertEqual(TilingLayout.tiledWindowIDs(in: tree), [])
    }

    func testBuildOneAndManyWindowsFillFrameWithoutDesktopStrip() throws {
        let one = TilingLayout.build(windowIDs: ["w1"])
        try one.validate()
        XCTAssertEqual(TilingLayout.tiledWindowIDs(in: one), ["w1"])
        let sub = try XCTUnwrap(TilingLayout.tilingSubtree(of: one))
        let engine = LayoutEngine(gap: 12)
        let frame = Rect(x: 10, y: 20, w: 1000, h: 800)
        let rects = engine.rects(for: sub, in: frame)
        XCTAssertEqual(rects["p-w1"], frame)

        let three = TilingLayout.build(windowIDs: ["w1", "w2", "w3"], axis: .x)
        try three.validate()
        XCTAssertEqual(TilingLayout.tiledWindowIDs(in: three), ["w1", "w2", "w3"])
        let tiled = try XCTUnwrap(TilingLayout.tilingSubtree(of: three))
        let laid = engine.rects(for: tiled, in: frame)
        // 1000 - 2*12 gap = 976 usable, equal thirds.
        let expected = 976.0 / 3.0
        XCTAssertEqual(laid["p-w1"]!.w, expected, accuracy: 1e-6)
        XCTAssertEqual(laid["p-w2"]!.x, frame.x + expected + 12, accuracy: 1e-6)
        XCTAssertEqual(laid["p-w3"]!.maxX, frame.maxX, accuracy: 1e-6)
        // No overlap between tiles, all inside the frame.
        let tiles = ["p-w1", "p-w2", "p-w3"].map { laid[$0]! }
        for (i, a) in tiles.enumerated() {
            XCTAssertEqual(a.y, frame.y, accuracy: 1e-9)
            XCTAssertEqual(a.h, frame.h, accuracy: 1e-9)
            for b in tiles.dropFirst(i + 1) {
                XCTAssertFalse(a.intersects(b) && a.maxX > b.x + 1e-9 && b.maxX > a.x + 1e-9
                               && a.w > 0 && b.w > 0 && abs(a.maxX - b.x) > 1e-6
                               && abs(b.maxX - a.x) > 1e-6 && min(a.maxX, b.maxX) - max(a.x, b.x) > 1)
                // Adjacent tiles are separated by the gap, so they must not overlap.
                XCTAssertLessThanOrEqual(min(a.maxX, b.maxX) - max(a.x, b.x), 1e-6)
            }
        }
    }

    func testReconcileRemovesAndAppendsPreservingWeights() throws {
        let engine = LayoutEngine()
        var tree = TilingLayout.build(windowIDs: ["w1", "w2", "w3"])
        tree = try engine.resizingGap(between: "p-w1", and: "p-w2", delta: 0.1, in: tree)
        let before = tree.parent(of: "p-w1")!.weights
        let beforeRatio = before[0] / before[2]

        let shrunk = TilingLayout.reconcile(root: tree, windowIDs: ["w1", "w3"], engine: engine)
        try shrunk.validate()
        XCTAssertEqual(TilingLayout.tiledWindowIDs(in: shrunk), ["w1", "w3"])
        XCTAssertNil(shrunk.node(id: "p-w2"))
        // Removing a sibling re-normalizes the remaining weights to 1; the
        // relative share between w1 and w3 must be preserved.
        let after = shrunk.parent(of: "p-w1")!.weights
        XCTAssertEqual(after.reduce(0, +), 1.0, accuracy: 1e-9)
        XCTAssertEqual(after[0] / after[1], beforeRatio, accuracy: 1e-9)
        XCTAssertGreaterThan(after[0], after[1])

        let grown = TilingLayout.reconcile(root: shrunk, windowIDs: ["w1", "w3", "w4"], engine: engine)
        try grown.validate()
        XCTAssertEqual(TilingLayout.tiledWindowIDs(in: grown), ["w1", "w3", "w4"])
    }

    func testReconcileFromEmptyAndBack() throws {
        let empty = TilingLayout.build(windowIDs: [])
        let first = TilingLayout.reconcile(root: empty, windowIDs: ["a", "b"])
        try first.validate()
        XCTAssertEqual(TilingLayout.tiledWindowIDs(in: first), ["a", "b"])
        let none = TilingLayout.reconcile(root: first, windowIDs: [])
        try none.validate()
        XCTAssertEqual(none.id, "desktop")
    }

    func testSwapAndCycleAndToggleAxis() throws {
        let tree = TilingLayout.build(windowIDs: ["w1", "w2", "w3"], axis: .x)
        let swapped = try TilingLayout.swap("w1", "w3", in: tree)
        try swapped.validate()
        XCTAssertEqual(TilingLayout.tiledWindowIDs(in: swapped), ["w3", "w2", "w1"])

        XCTAssertEqual(TilingLayout.cycle(from: "w2", direction: .next, in: tree), "w3")
        XCTAssertEqual(TilingLayout.cycle(from: "w3", direction: .next, in: tree), "w1")
        XCTAssertEqual(TilingLayout.cycle(from: "w1", direction: .previous, in: tree), "w3")
        XCTAssertEqual(TilingLayout.cycle(from: nil, direction: .next, in: tree), "w1")

        let flipped = TilingLayout.toggleAxis(ofWindow: "w2", in: tree)
        try flipped.validate()
        XCTAssertEqual(TilingLayout.preferredAxis(in: flipped), .y)
        let again = TilingLayout.toggleAxis(ofWindow: "w2", in: flipped)
        XCTAssertEqual(TilingLayout.preferredAxis(in: again), .x)

        let single = TilingLayout.build(windowIDs: ["only"])
        XCTAssertEqual(TilingLayout.toggleAxis(ofWindow: "only", in: single), single)
    }

    func testResizeGrowsFocusedAgainstSibling() throws {
        let engine = LayoutEngine(minimumShare: 0.05)
        let tree = TilingLayout.build(windowIDs: ["w1", "w2", "w3"])
        let grown = try TilingLayout.resize(windowID: "w1", delta: 0.1, in: tree, engine: engine)
        try grown.validate()
        let weights = grown.parent(of: "p-w1")!.weights
        XCTAssertEqual(weights[0], (1.0 / 3.0) + 0.1, accuracy: 1e-9)
        XCTAssertEqual(weights[1], (1.0 / 3.0) - 0.1, accuracy: 1e-9)

        let lastGrown = try TilingLayout.resize(windowID: "w3", delta: 0.1, in: tree, engine: engine)
        let last = lastGrown.parent(of: "p-w3")!.weights
        XCTAssertEqual(last[2], (1.0 / 3.0) + 0.1, accuracy: 1e-9)
        XCTAssertEqual(last[1], (1.0 / 3.0) - 0.1, accuracy: 1e-9)
    }

    func testCocoaAXRoundTrip() {
        let cocoaY: Double = 80
        let cocoaH: Double = 900
        let primaryMaxY: Double = 1080
        let ax = Rect.fromCocoa(x: 12, y: cocoaY, w: 800, h: cocoaH, primaryMaxY: primaryMaxY)
        XCTAssertEqual(ax.x, 12)
        XCTAssertEqual(ax.y, primaryMaxY - (cocoaY + cocoaH), accuracy: 1e-9)
        XCTAssertEqual(ax.w, 800)
        XCTAssertEqual(ax.h, cocoaH)
        let back = ax.toCocoa(primaryMaxY: primaryMaxY)
        XCTAssertEqual(back.x, 12, accuracy: 1e-9)
        XCTAssertEqual(back.y, cocoaY, accuracy: 1e-9)
        XCTAssertEqual(back.w, 800, accuracy: 1e-9)
        XCTAssertEqual(back.h, cocoaH, accuracy: 1e-9)
        XCTAssertTrue(ax.contains(x: ax.midX, y: ax.midY))
        XCTAssertFalse(ax.intersects(Rect(x: 900, y: 0, w: 10, h: 10)))
    }
}
