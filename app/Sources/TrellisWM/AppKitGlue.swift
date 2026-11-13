import AppKit
import TrellisAX
import TrellisCore

enum AppKitGlue {
    static var ownPID: Int32 { ProcessInfo.processInfo.processIdentifier }

    static func runningApps() -> [RunningApp] {
        NSWorkspace.shared.runningApplications.map { app in
            let policy: ProcessActivationPolicy
            switch app.activationPolicy {
            case .regular: policy = .regular
            case .accessory: policy = .accessory
            default: policy = .prohibited
            }
            return RunningApp(pid: app.processIdentifier,
                              bundleID: app.bundleIdentifier,
                              localizedName: app.localizedName,
                              activationPolicy: policy)
        }
    }

    static var originalTrellisWMRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "app.trellisui.trelliswm"
        }
    }

    /// The primary display is the screen whose Cocoa origin is `(0, 0)`,
    /// not necessarily `NSScreen.main` (the key-window screen) or
    /// `NSScreen.screens.first` if that array is ever reordered.
    static var primaryScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
    }

    /// Convert one screen's Cocoa visible frame into AX coordinates, flipping
    /// against the primary screen's top edge. Safe to call for any screen;
    /// v0.1 still only *manages* the primary display.
    static func visibleFrameAX(of screen: NSScreen, primaryMaxY: Double) -> Rect {
        let v = screen.visibleFrame
        return Rect.fromCocoa(x: v.origin.x, y: v.origin.y, w: v.width, h: v.height,
                              primaryMaxY: primaryMaxY)
    }

    /// Primary display visible frame in AX (top-left, y-down) coordinates.
    /// v0.1 manages only this display, not `NSScreen.main`.
    static func mainVisibleFrameAX() -> (rect: Rect, primaryMaxY: Double)? {
        guard let primary = primaryScreen else { return nil }
        let primaryMaxY = primary.frame.maxY
        return (visibleFrameAX(of: primary, primaryMaxY: primaryMaxY), primaryMaxY)
    }

    static func activate(pid: Int32) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
    }

    static func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }
}
