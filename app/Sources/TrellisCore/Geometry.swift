import Foundation

extension Rect {
    /// Convert a Cocoa-style rectangle (origin at bottom-left, y increases up)
    /// into AX / this engine's top-left, y-down space. `primaryMaxY` is the
    /// maximum Y of the primary screen's Cocoa frame (typically its top edge).
    public static func fromCocoa(x: Double, y: Double, w: Double, h: Double,
                                 primaryMaxY: Double) -> Rect {
        Rect(x: x, y: primaryMaxY - (y + h), w: w, h: h)
    }

    /// Inverse of `fromCocoa`.
    public func toCocoa(primaryMaxY: Double) -> (x: Double, y: Double, w: Double, h: Double) {
        (x: x, y: primaryMaxY - (y + h), w: w, h: h)
    }

    public var isEmpty: Bool { w <= 0 || h <= 0 }

    public func intersects(_ other: Rect) -> Bool {
        maxX > other.x && x < other.maxX && maxY > other.y && y < other.maxY
    }

    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px <= maxX && py >= y && py <= maxY
    }

    /// Cocoa-space frames of attached screens. The primary screen is the
    /// one whose origin is `(0, 0)`; `primaryMaxY` is that screen's top
    /// edge in Cocoa coordinates and is the value used to flip *any*
    /// screen into AX space. Do not use another screen's `maxY`, even if
    /// it is taller or listed first.
    public static func primaryMaxY(cocoaScreens: [Rect]) -> Double? {
        guard !cocoaScreens.isEmpty else { return nil }
        let primary = cocoaScreens.first(where: { abs($0.x) < 1e-9 && abs($0.y) < 1e-9 }) ?? cocoaScreens[0]
        return primary.maxY
    }

    public func almostEqual(_ other: Rect, tolerance: Double = 2) -> Bool {
        abs(x - other.x) <= tolerance
            && abs(y - other.y) <= tolerance
            && abs(w - other.w) <= tolerance
            && abs(h - other.h) <= tolerance
    }
}
