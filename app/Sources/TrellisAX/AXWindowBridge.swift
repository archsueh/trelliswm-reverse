import ApplicationServices
import CoreGraphics
import Foundation
import TrellisCore

/// Thin Accessibility bridge used by the read-only probe and the real WM.
/// Write operations refuse to run unless the process is trusted.
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

    /// A live AX window plus a session-stable id (not based on bounds, so it
    /// survives retile).
    public struct LiveWindow {
        public let id: String
        public let snapshot: WindowSnapshot
        public let element: AXUIElement
        public let bounds: Rect
    }

    public static let originalWMBundleID = "app.trellisui.trelliswm"

    private var identities: [Identity] = []
    private var nextSerial: Int = 1

    private struct Identity {
        var id: String
        var pid: Int32
        var element: AXUIElement
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

    public func windowElements(pid: Int32) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    /// Set a window frame and return the actual frame after the write.
    /// Apps may clamp the size (minimum width / height); the caller must
    /// read this return value rather than assume the request stuck.
    ///
    /// Refuses the write and returns `nil` when the process is not trusted,
    /// as promised by `assertTrusted()`.
    ///
    /// Order is size, then position, then size again — the usual AX idiom.
    /// Setting position first lets a subsequent size clamp walk the window
    /// and is a common source of overlap.
    @discardableResult
    public func setFrame(_ rect: Rect, of element: AXUIElement) -> Rect? {
        do {
            try assertTrusted()
        } catch {
            return nil
        }
        var point = CGPoint(x: rect.x, y: rect.y)
        var size = CGSize(width: max(1, rect.w), height: max(1, rect.h))
        guard let position = AXValueCreate(.cgPoint, &point),
              let extent = AXValueCreate(.cgSize, &size) else { return nil }
        _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, extent)
        _ = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, extent)
        return frame(of: element)
    }

    /// Guard for write paths. Never prompts.
    public func assertTrusted() throws {
        guard isTrusted else {
            throw LayoutError.invariant("Accessibility not granted; refusing to move real windows")
        }
    }

    /// Official TCC prompt plus an attempt to open the Accessibility settings pane.
    @discardableResult
    public func promptForTrust() -> Bool {
        // The kAXTrustedCheckOptionPrompt global is not concurrency-safe in the
        // Swift 6 SDK; the documented key string is stable.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    public func boolAttribute(_ name: String, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    public func frame(of element: AXUIElement) -> Rect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, CFGetTypeID(posVal) == AXValueGetTypeID(),
              let sizeVal = sizeRef, CFGetTypeID(sizeVal) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        let pos = posVal as! AXValue
        let ext = sizeVal as! AXValue
        guard AXValueGetValue(pos, .cgPoint, &point), AXValueGetValue(ext, .cgSize, &size) else { return nil }
        return Rect(x: point.x, y: point.y, w: size.width, h: size.height)
    }

    public func raiseAndFocus(_ element: AXUIElement, pid: Int32) {
        do {
            try assertTrusted()
        } catch {
            return
        }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    /// Enumerate AX standard windows of regular apps and assign stable ids.
    public func enumerateLiveWindows(ownPID: Int32,
                                     ownBundleIDs: Set<String> = WindowAdmission.skippedBundleIDs,
                                     apps: [RunningApp],
                                     mainDisplayAX: Rect) -> [LiveWindow] {
        var seen: [Identity] = []
        var result: [LiveWindow] = []

        for app in apps {
            if app.pid == ownPID { continue }
            if let bid = app.bundleID, ownBundleIDs.contains(bid) { continue }
            let policy = app.activationPolicy
            for element in windowElements(pid: app.pid) {
                let role = stringAttribute(kAXRoleAttribute as String, of: element) ?? ""
                let subrole = stringAttribute(kAXSubroleAttribute as String, of: element) ?? ""
                let minimized = boolAttribute(kAXMinimizedAttribute as String, of: element) ?? false
                let fullscreen = boolAttribute("AXFullScreen", of: element) ?? false
                let bounds = frame(of: element) ?? Rect()
                let onMain = mainDisplayAX.contains(x: bounds.midX, y: bounds.midY)
                let id = stableID(for: element, pid: app.pid)
                if let ident = identities.first(where: { CFEqual($0.element, element) }) {
                    seen.append(ident)
                } else {
                    seen.append(Identity(id: id, pid: app.pid, element: element))
                }
                let snap = WindowSnapshot(
                    id: id,
                    ownerName: app.localizedName ?? "?",
                    bundleID: app.bundleID ?? "",
                    pid: app.pid,
                    role: role,
                    subrole: subrole,
                    isMinimized: minimized,
                    isFullscreen: fullscreen,
                    isOnMainDisplay: onMain,
                    activationPolicy: policy)
                result.append(LiveWindow(id: id, snapshot: snap, element: element, bounds: bounds))
            }
        }
        identities = seen
        return result
    }

    private func stableID(for element: AXUIElement, pid: Int32) -> String {
        if let existing = identities.first(where: { CFEqual($0.element, element) }) {
            return existing.id
        }
        let id = "win-\(pid)-\(nextSerial)"
        nextSerial += 1
        identities.append(Identity(id: id, pid: pid, element: element))
        return id
    }
}

/// Process metadata the bridge can consume without importing AppKit itself
/// (the WM fills this from NSRunningApplication).
public struct RunningApp: Sendable {
    public var pid: Int32
    public var bundleID: String?
    public var localizedName: String?
    public var activationPolicy: ProcessActivationPolicy

    public init(pid: Int32,
                bundleID: String?,
                localizedName: String?,
                activationPolicy: ProcessActivationPolicy) {
        self.pid = pid
        self.bundleID = bundleID
        self.localizedName = localizedName
        self.activationPolicy = activationPolicy
    }
}
