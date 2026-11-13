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

    /// Main screen visible frame in AX (top-left, y-down) coordinates.
    static func mainVisibleFrameAX() -> (rect: Rect, primaryMaxY: Double)? {
        guard let primary = NSScreen.screens.first else { return nil }
        let main = NSScreen.main ?? primary
        let primaryMaxY = primary.frame.maxY
        let v = main.visibleFrame
        let rect = Rect.fromCocoa(x: v.origin.x, y: v.origin.y, w: v.width, h: v.height,
                                  primaryMaxY: primaryMaxY)
        return (rect, primaryMaxY)
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
