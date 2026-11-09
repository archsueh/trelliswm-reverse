import ApplicationServices
import CoreGraphics
import Foundation
import TrellisCore

/// Thin Accessibility bridge. It is only *called* in `--live` mode, and even
/// then it refuses to do anything unless the process is trusted. The default
/// dry-run probe never touches a real window — important because the subject
/// window manager is running on this Mac.
@MainActor
public final class AXWindowBridge {

    public struct WindowInfo: CustomStringConvertible {
        public let ownerName: String
        public let pid: Int32
        public let number: Int
        public let bounds: Rect

        public var description: String {
            "\(ownerName) #\(number) @ (\(Int(bounds.x)), \(Int(bounds.y)) \(Int(bounds.w))×\(Int(bounds.h)))"
        }
    }

    public init() {}

    public var isTrusted: Bool { AXIsProcessTrusted() }

    /// Read-only enumeration via CGWindowList — does not require Accessibility.
    public func onScreenWindows() -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]] else { return [] }
        return raw.compactMap { dict in
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = dict[kCGWindowOwnerPID as String] as? Int32,
                  let number = dict[kCGWindowNumber as String] as? Int else { return nil }
            let bounds = dict[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let rect = Rect(
                x: (bounds["X"] as? Double) ?? 0,
                y: (bounds["Y"] as? Double) ?? 0,
                w: (bounds["Width"] as? Double) ?? 0,
                h: (bounds["Height"] as? Double) ?? 0)
            return WindowInfo(ownerName: (dict[kCGWindowOwnerName as String] as? String) ?? "?",
                              pid: pid, number: number, bounds: rect)
        }
    }

    /// The subject subscribes to AXWindowCreated / AXWindowMiniaturized /
    /// AXWindowDeminiaturized / AXUIElementDestroyed. This skeleton only exposes
    /// the two setters needed to prove the bridge compiles; observer wiring is
    /// deliberately left out (see investigation.cany/coverage.md).
    public func windowElements(pid: Int32) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    public func setFrame(_ rect: Rect, of element: AXUIElement) -> Bool {
        var point = CGPoint(x: rect.x, y: rect.y)
        var size = CGSize(width: rect.w, height: rect.h)
        guard let position = AXValueCreate(.cgPoint, &point),
              let extent = AXValueCreate(.cgSize, &size) else { return false }
        let a = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        let b = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, extent)
        return a == .success && b == .success
    }

    /// Guard for --live. Never prompts: prompting would intrusive-overlap the
    /// real window manager's own permission flow.
    public func assertTrusted() throws {
        guard isTrusted else {
            throw LayoutError.invariant("Accessibility not granted; refusing to move real windows")
        }
    }
}
