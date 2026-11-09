import AppKit
import Foundation
import TrellisCore

/// Clean-room probe. Default mode is a dry run: it computes layout geometry and
/// camera transitions from the derived specification, prints a report, and exits.
/// It never registers a URL scheme handler, never asks for Accessibility, and
/// never moves a real window — the subject WM is running on this Mac.
@main
struct TrellisProbe {
    @MainActor
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--help") { printHelp(); return }

        var file = LayoutFixtures.document()
        let engine = LayoutEngine(gap: Double(Settings.release.gap))
        let probe = Camera(engine: engine)
        let parser = CommandURL()
        let frame = Rect(x: 0, y: 0, w: 1920, h: 1080)
        var state = CameraState(framed: file.framed)

        print("Trellis probe — clean-room model (dry run)")
        print("subject: TrellisWM 0.10.0 build 560 · derived spec v2")
        print(String(repeating: "─", count: 64))
        print("tree depth: \(file.doc.root.nestingDepth) · nodes: \(file.doc.root.flatten().count) · leaves: \(file.doc.root.leaves.count)")
        print("settings: \(Settings.keyCount) release defaults · gap \(Settings.release.gap)pt · motion ~460ms (observed 461/464ms)")

        let rects = engine.rects(for: file.doc.root, in: frame)
        print("\nLayout rects (1920×1080, gap \(Int(engine.gap))):")
        for node in file.doc.root.leaves {
            guard let r = rects[node.id] else { continue }
            let marker = node.id == "desktop" ? "  ← floating layer" : ""
            print(String(format: "  %-14@ %7.1f,%7.1f  %7.1f×%7.1f%@",
                         node.id as NSString, r.x, r.y, r.w, r.h, marker as NSString))
        }

        if let index = args.firstIndex(of: "--commands"), args.count > index + 1 {
            let urls = args[index + 1].split(separator: ",").map(String.init)
            print("\nCommands (\(urls.count)):")
            for raw in urls {
                do {
                    let command = try parser.parse(raw.trimmingCharacters(in: .whitespaces))
                    let action = parser.cameraAction(for: command,
                                                     focusedNode: "p-editor", frame: frame)
                    if let action {
                        state = probe.apply(action, to: state, in: file.doc.root, frame: frame)
                    }
                    print("  \(parser.url(for: command))  → framed=\(state.framed)  history=\(state.backStack.count)/\(state.forwardStack.count)")
                } catch {
                    print("  \(raw)  → error: \(error)")
                }
            }
        } else {
            // Default demonstration: the five headline moves from the guide.
            let demo = ["trellisprobe://frame-window", "trellisprobe://save-view?n=1",
                        "trellisprobe://everything", "trellisprobe://view?n=1",
                        "trellisprobe://back", "trellisprobe://forward"]
            print("\nDefault demonstration:")
            for raw in demo {
                let command = try! parser.parse(raw)
                if let action = parser.cameraAction(for: command, focusedNode: "p-editor", frame: frame) {
                    state = probe.apply(action, to: state, in: file.doc.root, frame: frame)
                }
                print("  \(parser.url(for: command))  → framed=\(state.framed)")
            }
        }

        print("\nFinal camera: framed=\(state.framed) · saved views=\(state.savedViews.count) · desktopHidden=\(state.desktopHidden)")
        file.framed = state.framed
        do {
            let data = try JSONEncoder().encode(file)
            print("Persisted document: \(data.count) bytes, version \(file.version)")
        } catch {
            print("Persist failed: \(error)")
        }

        if args.contains("--live") {
            let bridge = AXWindowBridge()
            let windows = bridge.onScreenWindows()
            print("\nLive read-only check: \(windows.count) on-screen windows · Accessibility trusted=\(bridge.isTrusted)")
            for w in windows.prefix(5) { print("  \(w)") }
            print("  (no window was moved; --apply is intentionally not implemented)")
        }

        if args.contains("--menubar") {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            let controller = MenuBarController { command in
                if let action = parser.cameraAction(for: command, focusedNode: "p-editor", frame: frame) {
                    state = probe.apply(action, to: state, in: file.doc.root, frame: frame)
                    print("command \(parser.url(for: command)) → framed=\(state.framed)")
                }
            }
            _ = controller
            app.run()
        }
    }

    static func printHelp() {
        print("""
        Trellis probe — clean-room reimplementation of an observable layout spec

        Usage: trellis-probe [options]

          (no args)                 dry-run report + demonstration of 6 commands
          --commands "<u>,<u>,..."  apply comma-separated trelliswm:// or
                                    trellisprobe:// commands to the model
          --live                    read-only CGWindowList check; never moves windows
          --menubar                 run as an LSUIElement-style menu bar agent
          --help                    this text

        This is a model, not a replacement window manager. See ../README.md.
        """)
    }
}
