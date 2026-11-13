import XCTest
@testable import TrellisCore

final class ClampResolverTests: XCTestCase {

    private let frame = Rect(x: 0, y: 39, w: 2056, h: 1200)
    private let engine = LayoutEngine(gap: 12)

    private func tiled(_ ids: [String], axis: Axis = .x) throws -> (LayoutNode, [String: Rect]) {
        let tree = TilingLayout.build(windowIDs: ids, axis: axis)
        let sub = try XCTUnwrap(TilingLayout.tilingSubtree(of: tree))
        return (sub, engine.rects(for: sub, in: frame))
    }

    private func assertNoOverlap(_ tiles: [Rect], file: StaticString = #filePath, line: UInt = #line) {
        for (i, a) in tiles.enumerated() {
            for b in tiles.dropFirst(i + 1) {
                let overlap = min(a.maxX, b.maxX) - max(a.x, b.x)
                let vOverlap = min(a.maxY, b.maxY) - max(a.y, b.y)
                if overlap > 1e-6 && vOverlap > 1e-6 {
                    XCTFail("tiles overlap by \(overlap)×\(vOverlap): \(a) vs \(b)", file: file, line: line)
                }
            }
        }
    }

    func testPackDistributesLeftoverToFlexibleItems() {
        // 800 fixed + 2 flex, frame 2056, 2 gaps of 12: leftover = 2056-800-24 = 1232, each flex 616
        let lengths = ClampResolver.pack(mins: [800, 0, 0], flexShares: [0, 400, 400], total: 2056, gap: 12)
        XCTAssertEqual(lengths[0], 800, accuracy: 1e-9)
        XCTAssertEqual(lengths[1], 616, accuracy: 1e-9)
        XCTAssertEqual(lengths[2], 616, accuracy: 1e-9)
        XCTAssertEqual(lengths.reduce(0, +) + 24, 2056, accuracy: 1e-9)
    }

    func testPackOverflowKeepsMinima() {
        // 600+600+0 + 24 = 1224 > 1000. Flex collapses; pack overflows.
        let lengths = ClampResolver.pack(mins: [600, 600, 0], flexShares: [0, 0, 300], total: 1000, gap: 12)
        XCTAssertEqual(lengths, [600, 600, 0])
    }

    func testNoChangeWhenActualMatchesRequested() throws {
        let (sub, requested) = try tiled(["a", "b", "c", "d"])
        let resolved = ClampResolver.resolve(tree: sub, requested: requested, actual: requested,
                                             frame: frame, gap: 12)
        for id in ["p-a", "p-b", "p-c", "p-d"] {
            XCTAssertTrue(resolved[id]!.almostEqual(requested[id]!, tolerance: 1e-6), "\(id) moved")
        }
    }

    func testClampedMinWidthShrinksNeighborsWithoutOverlap() throws {
        let (sub, requested) = try tiled(["a", "b", "c", "d"])
        // Equal tiles: (2056 - 36) / 4 = 505
        XCTAssertEqual(requested["p-a"]!.w, 505, accuracy: 1e-6)

        var actual = requested
        actual["p-a"] = Rect(x: 0, y: 39, w: 800, h: 1200)
        let resolved = ClampResolver.resolve(tree: sub, requested: requested, actual: actual,
                                             frame: frame, gap: 12)

        XCTAssertEqual(resolved["p-a"]!.w, 800, accuracy: 1e-6)
        XCTAssertEqual(resolved["p-a"]!.x, 0, accuracy: 1e-6)
        // Remaining 2056 - 800 - 3*12 = 1220, shared by three flex tiles.
        let flex = 1220.0 / 3.0
        XCTAssertEqual(resolved["p-b"]!.w, flex, accuracy: 1e-6)
        XCTAssertEqual(resolved["p-b"]!.x, 812, accuracy: 1e-6)
        XCTAssertEqual(resolved["p-c"]!.x, resolved["p-b"]!.maxX + 12, accuracy: 1e-6)
        XCTAssertEqual(resolved["p-d"]!.maxX, frame.maxX, accuracy: 1e-6)

        let tiles = ["p-a", "p-b", "p-c", "p-d"].map { resolved[$0]! }
        for tile in tiles {
            XCTAssertGreaterThanOrEqual(tile.x, frame.x - 1e-6)
            XCTAssertLessThanOrEqual(tile.maxX, frame.maxX + 1e-6)
            XCTAssertEqual(tile.y, frame.y, accuracy: 1e-9)
            XCTAssertEqual(tile.h, frame.h, accuracy: 1e-9)
        }
        assertNoOverlap(tiles)
        // Gaps stay at 12 pt between neighbours in order.
        XCTAssertEqual(resolved["p-b"]!.x - resolved["p-a"]!.maxX, 12, accuracy: 1e-6)
        XCTAssertEqual(resolved["p-c"]!.x - resolved["p-b"]!.maxX, 12, accuracy: 1e-6)
        XCTAssertEqual(resolved["p-d"]!.x - resolved["p-c"]!.maxX, 12, accuracy: 1e-6)
    }

    func testOverflowPacksFromOriginWithoutOverlap() throws {
        let tree = TilingLayout.build(windowIDs: ["a", "b", "c"])
        let sub = try XCTUnwrap(TilingLayout.tilingSubtree(of: tree))
        let box = Rect(x: 0, y: 0, w: 1000, h: 800)
        let requested = engine.rects(for: sub, in: box)
        var actual = requested
        actual["p-a"] = Rect(x: 0, y: 0, w: 600, h: 800)
        actual["p-b"] = Rect(x: 0, y: 0, w: 600, h: 800)
        let resolved = ClampResolver.resolve(tree: sub, requested: requested, actual: actual,
                                             frame: box, gap: 12)
        XCTAssertEqual(resolved["p-a"]!.w, 600, accuracy: 1e-9)
        XCTAssertEqual(resolved["p-a"]!.x, 0, accuracy: 1e-9)
        XCTAssertEqual(resolved["p-b"]!.x, 612, accuracy: 1e-9)
        XCTAssertEqual(resolved["p-b"]!.w, 600, accuracy: 1e-9)
        // Flexible c shrinks to zero and starts past the trailing edge
        // rather than overlapping a or b.
        XCTAssertEqual(resolved["p-c"]!.x, 1224, accuracy: 1e-9)
        XCTAssertEqual(resolved["p-c"]!.w, 0, accuracy: 1e-9)
        assertNoOverlap(["p-a", "p-b", "p-c"].map { resolved[$0]! })
        XCTAssertGreaterThan(resolved["p-b"]!.maxX, box.maxX)
    }

    func testVerticalClamp() throws {
        let (sub, requested) = try tiled(["a", "b", "c"], axis: .y)
        var actual = requested
        let minH: Double = 700
        actual["p-a"] = Rect(x: frame.x, y: frame.y, w: frame.w, h: minH)
        let resolved = ClampResolver.resolve(tree: sub, requested: requested, actual: actual,
                                             frame: frame, gap: 12)
        XCTAssertEqual(resolved["p-a"]!.h, minH, accuracy: 1e-6)
        XCTAssertEqual(resolved["p-a"]!.y, frame.y, accuracy: 1e-6)
        let leftover = frame.h - minH - 24
        XCTAssertEqual(resolved["p-b"]!.h, leftover / 2, accuracy: 1e-6)
        XCTAssertEqual(resolved["p-b"]!.y, frame.y + minH + 12, accuracy: 1e-6)
        XCTAssertEqual(resolved["p-c"]!.maxY, frame.maxY, accuracy: 1e-6)
        assertNoOverlap(["p-a", "p-b", "p-c"].map { resolved[$0]! })
    }

    func testNestedSplitClampOnOuterAxis() throws {
        let inner = LayoutNode.split(Split(id: "inner", axis: .y, children: [
            TilingLayout.panel("b"),
            TilingLayout.panel("c"),
        ]))
        let tiled = LayoutNode.split(Split(id: "split-tiled", axis: .x, children: [
            TilingLayout.panel("a"),
            inner,
        ]))
        let box = Rect(x: 0, y: 0, w: 1000, h: 800)
        let requested = engine.rects(for: tiled, in: box)
        // Equal x-split: (1000-12)/2 = 494 each.
        XCTAssertEqual(requested["p-a"]!.w, 494, accuracy: 1e-6)
        var actual = requested
        actual["p-a"] = Rect(x: 0, y: 0, w: 700, h: 800)
        let resolved = ClampResolver.resolve(tree: tiled, requested: requested, actual: actual,
                                             frame: box, gap: 12)
        XCTAssertEqual(resolved["p-a"]!.w, 700, accuracy: 1e-6)
        // Inner column gets the leftover: 1000 - 700 - 12 = 288
        XCTAssertEqual(resolved["p-b"]!.x, 712, accuracy: 1e-6)
        XCTAssertEqual(resolved["p-b"]!.w, 288, accuracy: 1e-6)
        XCTAssertEqual(resolved["p-c"]!.w, 288, accuracy: 1e-6)
        XCTAssertEqual(resolved["p-c"]!.x, 712, accuracy: 1e-6)
        // Vertical split inside the inner column keeps the 12 pt gap.
        XCTAssertEqual(resolved["p-c"]!.y, resolved["p-b"]!.maxY + 12, accuracy: 1e-6)
        XCTAssertEqual(resolved["p-c"]!.maxY, box.maxY, accuracy: 1e-6)
        assertNoOverlap(["p-a", "p-b", "p-c"].map { resolved[$0]! })
    }
}
