import AppKit

@MainActor
final class WMAppDelegate: NSObject, NSApplicationDelegate {
    let agent: WMAgent

    init(agent: WMAgent) {
        self.agent = agent
    }

    func applicationWillTerminate(_ notification: Notification) {
        agent.shutdown()
    }
}

@main
enum TrellisWMMain {
    @MainActor
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let verify = args.contains("--verify-launch")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let agent = WMAgent(verifyLaunch: verify)
        let delegate = WMAppDelegate(agent: agent)
        app.delegate = delegate
        agent.start()
        if verify {
            // Stay up briefly so the menu-bar item is visible, then quit.
            // Never enable tiling and never prompt for Accessibility.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                agent.shutdown()
                NSApp.terminate(nil)
            }
        }
        app.run()
    }
}
