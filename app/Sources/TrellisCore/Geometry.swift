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
}
