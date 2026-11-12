import AppKit
import Foundation
import WebKit
import TrellisCore

// MARK: - Visual language (light, high-contrast Ledger palette)

/// Computed, not stored: NSColor is not Sendable, so Swift 6 strict concurrency
/// rejects static stored properties of this type (they would be shared state).
private enum Ink {
    static var paper: NSColor   { NSColor(calibratedRed: 0.957, green: 0.949, blue: 0.929, alpha: 1) }
    static var canvas: NSColor  { NSColor(calibratedRed: 1.000, green: 0.998, blue: 0.992, alpha: 1) }
    static var grid: NSColor    { NSColor(calibratedRed: 0.905, green: 0.900, blue: 0.880, alpha: 1) }
    static var chrome: NSColor  { NSColor(calibratedRed: 0.980, green: 0.975, blue: 0.958, alpha: 1) }
    static var text: NSColor    { NSColor(calibratedRed: 0.090, green: 0.120, blue: 0.170, alpha: 1) }
    static var muted: NSColor   { NSColor(calibratedRed: 0.420, green: 0.450, blue: 0.500, alpha: 1) }
    static var accent: NSColor  { NSColor(calibratedRed: 0.110, green: 0.340, blue: 0.660, alpha: 1) }
    static var outline: NSColor { NSColor(calibratedRed: 0.760, green: 0.775, blue: 0.790, alpha: 1) }
    static var desktop: NSColor { NSColor(calibratedRed: 0.900, green: 0.880, blue: 0.830, alpha: 1) }
    static var leaf: [NSColor] {
        [
            NSColor(calibratedRed: 0.855, green: 0.915, blue: 0.980, alpha: 1),
            NSColor(calibratedRed: 0.865, green: 0.945, blue: 0.915, alpha: 1),
            NSColor(calibratedRed: 0.980, green: 0.920, blue: 0.850, alpha: 1),
            NSColor(calibratedRed: 0.930, green: 0.890, blue: 0.970, alpha: 1),
            NSColor(calibratedRed: 0.970, green: 0.890, blue: 0.900, alpha: 1),
        ]
    }
}

/// World coordinates used by the layout engine. The probe uses 1920x1080; the
/// studio uses a 16:10 world so the recursive tree reads well in a window.
private let kWorld = Rect(x: 0, y: 0, w: 1600, h: 1000)
private let motionSeconds: TimeInterval = 0.46  // observed SETTLED median, see capture/runtime-events.json

/// Display preference for the workbench, NOT an observed subject value.
/// `Settings.release.gap` (12pt) is evidence from ReleaseSettings.json and stays
/// untouched: `trellis-probe`, the JS simulator and the check suite keep using
/// it. The native canvas renders tighter (6pt) because a 12pt world-space gap
/// reads too wide at window size. The status bar labels both so the two are
/// never confused.
private let kDisplayGap: Double = 6

private func lerpRect(_ a: Rect, _ b: Rect, _ t: Double) -> Rect {
    Rect(x: a.x + (b.x - a.x) * t,
         y: a.y + (b.y - a.y) * t,
         w: a.w + (b.w - a.w) * t,
         h: a.h + (b.h - a.h) * t)
}

// MARK: - Canvas

/// Renders the derived fractal layout tree through a camera whose only state is
/// a framed node id. This is a *visualisation* of the derived spec; it never
/// touches Accessibility and never moves a real macOS window.
@MainActor
private final class CanvasView: NSView {
    override var isFlipped: Bool { true }

    let file: LayoutFile
    let engine: LayoutEngine
    let camera: Camera
    var rects: [String: Rect]
    var state: CameraState
    var displayFocus: Rect

    private var animation: (from: Rect, to: Rect, start: Date)?
    private var timer: Timer?

    var onUpdate: (() -> Void)?
    var onSelect: ((String) -> Void)?

    init(file: LayoutFile) {
        let e = LayoutEngine(gap: kDisplayGap)
        self.file = file
        self.engine = e
        self.camera = Camera(engine: e)
        self.rects = e.rects(for: file.doc.root, in: kWorld)
        self.state = CameraState(framed: file.doc.root.id)  // Q16 convention: everything -> root
        self.displayFocus = kWorld
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    private func focus(for st: CameraState) -> Rect {
        st.framed == file.doc.root.id ? kWorld : (rects[st.framed] ?? kWorld)
    }

    func apply(_ action: CameraAction) {
        let next = camera.apply(action, to: state, in: file.doc.root, frame: kWorld)
        guard next != state else { return }
        state = next
        animate(to: focus(for: next))
        onUpdate?()
    }

    private func animate(to target: Rect) {
        animation = (displayFocus, target, Date())
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 1.0 / 60.0, target: self,
                                     selector: #selector(tick), userInfo: nil, repeats: true)
    }

    @objc private func tick() {
        guard let a = animation else { timer?.invalidate(); timer = nil; return }
        let p = min(1.0, Date().timeIntervalSince(a.start) / motionSeconds)
        let eased = 1.0 - pow(1.0 - p, 3.0)
        displayFocus = lerpRect(a.from, a.to, eased)
        needsDisplay = true
        if p >= 1.0 {
            displayFocus = a.to
            animation = nil
            timer?.invalidate()
            timer = nil
            needsDisplay = true
        }
    }

    private var scaleFactor: CGFloat {
        let f = displayFocus
        guard f.w > 0, f.h > 0 else { return 1 }
        return min(bounds.width / CGFloat(f.w), bounds.height / CGFloat(f.h)) * 0.90
    }

    private func mapped(_ r: Rect) -> NSRect {
        let f = displayFocus
        let s = scaleFactor
        let ox = (bounds.width - CGFloat(f.w) * s) / 2
        let oy = (bounds.height - CGFloat(f.h) * s) / 2
        return NSRect(x: (CGFloat(r.x) - CGFloat(f.x)) * s + ox,
                      y: (CGFloat(r.y) - CGFloat(f.y)) * s + oy,
                      width: CGFloat(r.w) * s,
                      height: CGFloat(r.h) * s)
    }

    private func text(_ s: String, at p: NSPoint, size: CGFloat,
                      color: NSColor, bold: Bool = false) {
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        (s as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
    }

    override func draw(_ dirtyRect: NSRect) {
        Ink.canvas.setFill()
        NSBezierPath(rect: bounds).fill()

        // World grid — makes the camera transform legible.
        Ink.grid.setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 0.5
        for x in stride(from: 0.0, through: kWorld.w, by: 100) {
            let p = mapped(Rect(x: x, y: kWorld.y, w: 0, h: kWorld.h))
            grid.move(to: NSPoint(x: p.minX, y: 0))
            grid.line(to: NSPoint(x: p.minX, y: bounds.height))
        }
        for y in stride(from: 0.0, through: kWorld.h, by: 100) {
            let p = mapped(Rect(x: kWorld.x, y: y, w: kWorld.w, h: 0))
            grid.move(to: NSPoint(x: 0, y: p.minY))
            grid.line(to: NSPoint(x: bounds.width, y: p.minY))
        }
        grid.stroke()

        // Leaves first: split guides are painted on top of them below.
        // The desktop is the single floating-layer leaf.
        for (index, leaf) in file.doc.root.leaves.enumerated() {
            guard let r = rects[leaf.id] else { continue }
            let v = mapped(r).insetBy(dx: 3, dy: 3)
            guard v.intersects(bounds) else { continue }

            if leaf.id == "desktop" && state.desktopHidden {
                Ink.chrome.setFill()
                let p = NSBezierPath(roundedRect: v, xRadius: 8, yRadius: 8)
                p.fill()
                p.setLineDash([6, 4], count: 2, phase: 0)
                Ink.outline.setStroke(); p.lineWidth = 1.5; p.stroke()
                p.setLineDash(nil, count: 0, phase: 0)
                if v.width > 120 {
                    text("Desktop 已隐藏", at: NSPoint(x: v.minX + 14, y: v.minY + 14),
                         size: 12, color: Ink.muted, bold: true)
                }
                continue
            }

            let fill: NSColor = leaf.id == "desktop" ? Ink.desktop : Ink.leaf[index % Ink.leaf.count]
            fill.setFill()
            let path = NSBezierPath(roundedRect: v, xRadius: 8, yRadius: 8)
            path.fill()
            Ink.outline.setStroke()
            path.lineWidth = 1
            path.stroke()

            guard v.width > 76, v.height > 42 else { continue }
            text(leaf.id, at: NSPoint(x: v.minX + 14, y: v.minY + 13),
                 size: 13, color: Ink.text, bold: true)
            let subtitle: String
            switch leaf {
            case .desktop:
                subtitle = "Desktop · 唯一浮动层"
            case .panel(let p):
                subtitle = p.isTabGroup ? "\(p.views.count) views · tab group" : "\(p.views.count) view · panel"
            case .split:
                subtitle = "split"
            }
            if v.height > 66 {
                text(subtitle, at: NSPoint(x: v.minX + 14, y: v.minY + 34),
                     size: 10.5, color: Ink.muted)
            }
        }

        // Split containers last: dashed outlines and their level labels must
        // stay readable on top of the leaves they contain. Right-aligned so
        // they never collide with a leaf's top-left id.
        for node in file.doc.root.flatten() {
            guard case .split(let s) = node, let r = rects[s.id] else { continue }
            let v = mapped(r)
            guard v.intersects(bounds), v.width > 40 else { continue }
            let path = NSBezierPath(roundedRect: v.insetBy(dx: 7, dy: 7), xRadius: 5, yRadius: 5)
            path.lineWidth = 1
            path.setLineDash([4, 4], count: 2, phase: 0)
            Ink.outline.withAlphaComponent(0.95).setStroke()
            path.stroke()
            path.setLineDash(nil, count: 0, phase: 0)
            let depth = engine.path(to: s.id, in: file.doc.root).count - 1
            let label = "\(s.id) · axis \(s.axis.rawValue) · L\(depth)"
            let width = (label as NSString).size(withAttributes:
                [.font: NSFont.systemFont(ofSize: 10)]).width
            let x = min(v.maxX - width - 16, bounds.width - width - 8)
            text(label, at: NSPoint(x: max(8, x), y: max(6, v.minY + 9)),
                 size: 10, color: Ink.muted)
        }

        // Camera highlight.
        if state.framed != file.doc.root.id, let r = rects[state.framed] {
            let v = mapped(r).insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: v, xRadius: 9, yRadius: 9)
            Ink.accent.setStroke()
            path.lineWidth = 3
            path.stroke()
            let badge = "FRAMED  \(state.framed)"
            let badgeSize = (badge as NSString).size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: 10)])
            let badgeRect = NSRect(x: v.minX + 8, y: max(v.minY + 8, 8),
                                   width: badgeSize.width + 14, height: badgeSize.height + 6)
            Ink.accent.setFill()
            NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4).fill()
            text(badge, at: NSPoint(x: badgeRect.minX + 7, y: badgeRect.minY + 3),
                 size: 10, color: .white, bold: true)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        var best: (id: String, area: CGFloat)?
        for leaf in file.doc.root.leaves {
            guard let r = rects[leaf.id] else { continue }
            let v = mapped(r)
            guard v.contains(p) else { continue }
            let area = v.width * v.height
            if best == nil || area < best!.area { best = (leaf.id, area) }
        }
        if let id = best?.id {
            onSelect?(id)
            apply(.frame(nodeID: id))  // framing the same node steps back out
        }
    }
}

// MARK: - Controller

@MainActor
private final class StudioController: NSObject, NSTextFieldDelegate {
    let window: NSWindow
    let canvas: CanvasView
    let statusLabel: NSTextField
    let urlField: NSTextField
    let parser = CommandURL()
    let file: LayoutFile

    private var flashText: String?
    private var flashTimer: Timer?
    private var simWindow: NSWindow?

    private let toolbarCommands: [(String, String)] = [
        ("全部", "trellisprobe://everything"),
        ("深入一层", "trellisprobe://zoom-in"),
        ("退出一层", "trellisprobe://zoom-out"),
        ("后退", "trellisprobe://back"),
        ("前进", "trellisprobe://forward"),
        ("聚焦窗口", "trellisprobe://frame-window"),
        ("聚焦 Desktop", "trellisprobe://frame-desktop"),
        ("隐藏 Desktop", "trellisprobe://toggle-desktop"),
        ("保存视图 1", "trellisprobe://save-view?n=1"),
        ("视图 1", "trellisprobe://view?n=1"),
    ]

    private static let allCommands: [(String, String)] = [
        ("Show everything", "trellisprobe://everything"),
        ("Zoom out (step out)", "trellisprobe://zoom-out"),
        ("Zoom in (step in)", "trellisprobe://zoom-in"),
        ("Back", "trellisprobe://back"),
        ("Forward", "trellisprobe://forward"),
        ("Neighbour left", "trellisprobe://neighbour?dir=left"),
        ("Neighbour right", "trellisprobe://neighbour?dir=right"),
        ("Frame focused window", "trellisprobe://frame-window"),
        ("Frame the Desktop", "trellisprobe://frame-desktop"),
        ("Hide / show Desktop", "trellisprobe://toggle-desktop"),
        ("Save view 1", "trellisprobe://save-view?n=1"),
        ("Go to view 1", "trellisprobe://view?n=1"),
        ("Split with Finder", "trellisprobe://split-finder"),
        ("Arrange all windows", "trellisprobe://arrange"),
        ("Float all windows", "trellisprobe://float-all"),
        ("Settings · Shortcuts", "trellisprobe://settings?pane=shortcuts"),
    ]

    init(file: LayoutFile) {
        self.file = file
        let canvas = CanvasView(file: file)

        let header = NSStackView()
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2
        let title = NSTextField(labelWithString: "Trellis Reverse  ·  分形布局工作台")
        title.font = NSFont.boldSystemFont(ofSize: 17)
        title.textColor = Ink.text
        let subtitle = NSTextField(labelWithString:
            "Clean-room 规格模型 — 只可视化布局与相机，不接管窗口、不请求辅助功能权限")
        subtitle.font = NSFont.systemFont(ofSize: 11.5)
        subtitle.textColor = Ink.muted
        header.addView(title, in: .leading)
        header.addView(subtitle, in: .leading)

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.distribution = .fillEqually

        let urlField = NSTextField()
        // A real value, not just a placeholder: the field is usable on first launch.
        urlField.stringValue = "trellisprobe://zoom-in"
        urlField.placeholderString = "也可输入 trelliswm://… 证据形态 URL"
        urlField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        urlField.textColor = Ink.text
        urlField.bezelStyle = .roundedBezel

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = Ink.muted

        self.canvas = canvas
        self.urlField = urlField
        self.statusLabel = statusLabel

        let root = NSStackView(views: [header, toolbar, urlField, canvas, statusLabel])
        root.orientation = .vertical
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 12, right: 18)
        root.distribution = .fill
        canvas.setContentHuggingPriority(NSLayoutConstraint.Priority(rawValue: 100), for: .vertical)
        canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true
        urlField.heightAnchor.constraint(equalToConstant: 26).isActive = true
        statusLabel.heightAnchor.constraint(equalToConstant: 18).isActive = true

        // No .fullSizeContentView: a standard title bar keeps the header clear.
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Trellis Reverse"
        win.contentView = root
        win.backgroundColor = Ink.paper
        win.minSize = NSSize(width: 900, height: 620)
        win.center()
        win.setFrameAutosaveName("TrellisReverseStudio")
        self.window = win

        super.init()

        urlField.delegate = self
        for (index, entry) in toolbarCommands.enumerated() {
            let b = NSButton(title: entry.0, target: self, action: #selector(toolbarHit(_:)))
            b.bezelStyle = .rounded
            b.font = NSFont.systemFont(ofSize: 11.5)
            // Explicit dark title: on a custom light window background the default
            // tint can resolve to near-white and the labels disappear.
            b.contentTintColor = Ink.text
            b.attributedTitle = NSAttributedString(string: entry.0, attributes: [
                .font: NSFont.systemFont(ofSize: 11.5),
                .foregroundColor: Ink.text,
            ])
            b.tag = index
            b.toolTip = entry.1
            toolbar.addView(b, in: .leading)
        }
        canvas.onUpdate = { [weak self] in self?.refresh() }
        canvas.onSelect = { [weak self] id in self?.flash("点击 \(id) · 再次点击同一节点退回全景") }
        refresh()
    }

    // MARK: Status

    private func refresh() {
        let tree = file.doc.root
        let s = canvas.state
        let base = String(format:
            "framed: %@   ·   depth %d   ·   nodes %d   ·   leaves %d   ·   back %d / forward %d   ·   saved %d   ·   gap %dpt (view) / %dpt (subject)   ·   desktop %@",
            s.framed as NSString,
            tree.nestingDepth, tree.flatten().count, tree.leaves.count,
            s.backStack.count, s.forwardStack.count, s.savedViews.count,
            Int(kDisplayGap), Settings.release.gap as Int,
            (s.desktopHidden ? "hidden" : "shown") as NSString)
        statusLabel.stringValue = flashText.map { "\($0)    ｜    \(base)" } ?? base
    }

    private func flash(_ message: String) {
        flashText = message
        refresh()
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(timeInterval: 3.0, target: self,
                                          selector: #selector(clearFlash), userInfo: nil, repeats: false)
    }

    @objc private func clearFlash() {
        flashText = nil
        flashTimer?.invalidate()
        flashTimer = nil
        refresh()
    }

    // MARK: Commands

    func run(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let command = try parser.parse(trimmed)
            if let action = parser.cameraAction(for: command, focusedNode: "p-editor", frame: kWorld) {
                canvas.apply(action)
                flash("\(parser.url(for: command))  →  framed \(canvas.state.framed)")
            } else {
                flash("「\(parser.url(for: command))」需要窗口系统；本工作台只模拟相机与布局（README 第 5 节）")
            }
        } catch {
            flash("解析失败：\(error)")
        }
        refresh()
    }

    @objc private func toolbarHit(_ sender: NSButton) {
        guard toolbarCommands.indices.contains(sender.tag) else { return }
        run(toolbarCommands[sender.tag].1)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            run(urlField.stringValue)
            return true
        }
        return false
    }

    // MARK: Panels

    func openSimulator() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html",
                                        subdirectory: "Simulator") else {
            flash("未找到内嵌模拟器（Simulator/index.html）")
            return
        }
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 820), configuration: config)
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
                           styleMask: [.titled, .closable, .resizable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.title = "Trellis 交互模拟器 · 24 项自检"
        win.contentView = web
        win.center()
        win.makeKeyAndOrderFront(nil)
        simWindow = win
    }

    func revealSource() {
        if let dir = Bundle.main.resourceURL?.appendingPathComponent("Source") {
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        } else {
            flash("未找到内嵌源码目录")
        }
    }

    func exportLayout() {
        let panel = NSSavePanel()
        panel.title = "导出当前布局文档"
        panel.nameFieldStringValue = "layout-simulated.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var doc = file
        doc.framed = canvas.state.framed
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(doc).write(to: url)
            flash("已导出 \(url.lastPathComponent)")
        } catch {
            flash("导出失败：\(error.localizedDescription)")
        }
    }

    func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Trellis Reverse 1.0.0"
        alert.informativeText = """
        Clean-room 规格研究的可视化工作台，基于 TrellisWM 0.10.0 (build 560) 的可见证据独立实现。

        与 TrellisWM 及其作者无关联、未获背书；未复制任何源码、图标或资源。
        本 app 不是窗口管理器：不注册 trelliswm://、不请求辅助功能权限、不移动任何真实窗口。

        Swift 18/18 单测 · Check 14/14 READY · JS 24/24 自检。
        证据台账、置信度与明确局限见内嵌 README.md / NOTICE.md。
        """
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    static var commandMenuItems: [(String, String)] { allCommands }
}

// MARK: - App delegate & menu

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: StudioController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let c = StudioController(file: LayoutFixtures.document())
        controller = c
        c.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        let about = NSMenuItem(title: "关于 Trellis Reverse", action: #selector(aboutAction), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏 Trellis Reverse",
                                   action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 Trellis Reverse",
                                   action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        for (title, sel, key) in [
            ("打开交互模拟器", #selector(simulatorAction), "1"),
            ("在 Finder 中显示源码与证据", #selector(sourceAction), "2"),
            ("导出当前布局 JSON…", #selector(exportAction), "e"),
        ] as [(String, Selector, String)] {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            item.target = self
            fileMenu.addItem(item)
        }
        fileItem.submenu = fileMenu

        let cmdItem = NSMenuItem()
        main.addItem(cmdItem)
        let cmdMenu = NSMenu(title: "命令")
        for (index, entry) in StudioController.commandMenuItems.enumerated() {
            let item = NSMenuItem(title: entry.0, action: #selector(commandAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.toolTip = entry.1
            cmdMenu.addItem(item)
        }
        cmdItem.submenu = cmdMenu

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    @objc private func aboutAction() { controller?.showAbout() }
    @objc private func simulatorAction() { controller?.openSimulator() }
    @objc private func sourceAction() { controller?.revealSource() }
    @objc private func exportAction() { controller?.exportLayout() }

    @objc private func commandAction(_ sender: NSMenuItem) {
        let items = StudioController.commandMenuItems
        guard items.indices.contains(sender.tag) else { return }
        controller?.run(items[sender.tag].1)
    }
}

@main
private struct StudioMain {
    @MainActor static var delegateRef: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        delegateRef = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
