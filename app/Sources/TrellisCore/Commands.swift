import Foundation

public enum SettingsPane: String, Codable, Equatable, Sendable, CaseIterable {
    case general, windows, tabs, appearance, gestures, apps, shortcuts, license
}

/// The 15 commands published in the subject's public guide (capture/commands.json).
/// Names and query parameters are quoted verbatim so the clean-room build can be
/// checked against the evidence set.
public enum Command: Equatable, Sendable {
    case everything
    case zoomOut
    case zoomIn
    case back
    case forward
    case neighbour(Direction)
    case frameWindow
    case frameDesktop
    case toggleDesktop
    case view(Int)
    case saveView(Int)
    case splitFinder
    case arrange
    case floatAll
    case settings(SettingsPane)

    public static let allCases: [Command] = [
        .everything, .zoomOut, .zoomIn, .back, .forward,
        .neighbour(.left), .frameWindow, .frameDesktop, .toggleDesktop,
        .view(1), .saveView(1), .splitFinder, .arrange, .floatAll, .settings(.shortcuts),
    ]
}

public struct CommandURL: Sendable {
    /// The subject owns `trelliswm`. This constant is kept only so the parser can
    /// accept evidence-shaped URLs; the clean-room app registers its own scheme.
    public static let evidenceScheme = "trelliswm"
    public static let ownScheme = "trellisprobe"

    public init() {}

    /// Accepts `trelliswm://everything`, `trelliswm://view?n=1`, and the
    /// clean-room scheme. Query parsing is deliberately hand-rolled: Foundation's
    /// URLComponents treats the command as a `host`, which is easy to misread.
    public func parse(_ raw: String) throws -> Command {
        let allowed = [Self.evidenceScheme, Self.ownScheme]
        guard let marker = allowed.compactMap({ scheme -> String? in
            let prefix = scheme + "://"
            return raw.hasPrefix(prefix) ? prefix : nil
        }).first else {
            throw LayoutError.invalidCommand("expected \(allowed.joined(separator: " or ")):// prefix")
        }
        let rest = String(raw.dropFirst(marker.count))
        let pieces = rest.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(pieces.first ?? "").lowercased()
        var query: [String: String] = [:]
        if pieces.count == 2 {
            for pair in pieces[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if kv.count == 2 {
                    query[String(kv[0]).lowercased()] = String(kv[1]).lowercased()
                }
            }
        }
        switch name {
        case "everything": return .everything
        case "zoom-out":   return .zoomOut
        case "zoom-in":    return .zoomIn
        case "back":       return .back
        case "forward":    return .forward
        case "neighbour":
            guard let rawDir = query["dir"], let dir = Direction(rawValue: rawDir) else {
                throw LayoutError.invalidCommand("neighbour requires dir=left|right|up|down")
            }
            return .neighbour(dir)
        case "frame-window":  return .frameWindow
        case "frame-desktop": return .frameDesktop
        case "toggle-desktop":return .toggleDesktop
        case "view":          return .view(try number(query["n"], name: "view"))
        case "save-view":     return .saveView(try number(query["n"], name: "save-view"))
        case "split-finder":  return .splitFinder
        case "arrange":       return .arrange
        case "float-all":     return .floatAll
        case "settings":
            let pane = query["pane"].flatMap(SettingsPane.init(rawValue:)) ?? .general
            return .settings(pane)
        default:
            throw LayoutError.invalidCommand("unknown command '\(name)'")
        }
    }

    private func number(_ raw: String?, name: String) throws -> Int {
        guard let raw, let n = Int(raw), (1...9).contains(n) else {
            throw LayoutError.invalidCommand("\(name) requires n=1..9")
        }
        return n
    }

    public func url(for command: Command, scheme: String = ownScheme) -> String {
        "\(scheme)://" + path(command)
    }

    private func path(_ command: Command) -> String {
        switch command {
        case .everything:      return "everything"
        case .zoomOut:         return "zoom-out"
        case .zoomIn:          return "zoom-in"
        case .back:            return "back"
        case .forward:         return "forward"
        case .neighbour(let d):return "neighbour?dir=\(d.rawValue)"
        case .frameWindow:     return "frame-window"
        case .frameDesktop:    return "frame-desktop"
        case .toggleDesktop:   return "toggle-desktop"
        case .view(let n):     return "view?n=\(n)"
        case .saveView(let n): return "save-view?n=\(n)"
        case .splitFinder:     return "split-finder"
        case .arrange:         return "arrange"
        case .floatAll:        return "float-all"
        case .settings(let p): return "settings?pane=\(p.rawValue)"
        }
    }

    /// Commands that are pure camera moves. The rest need the window system.
    public func cameraAction(for command: Command, focusedNode: String? = nil,
                             frame: Rect = Rect(w: 1920, h: 1080)) -> CameraAction? {
        switch command {
        case .everything:       return .everything
        case .zoomOut:          return .zoomOut
        case .zoomIn:           return .zoomIn(towardSeat: nil)
        case .back:             return .back
        case .forward:          return .forward
        case .frameWindow:      return focusedNode.map { .frame(nodeID: $0) }
        case .frameDesktop:     return .frameDesktop
        case .toggleDesktop:    return .toggleDesktop
        case .view(let n):      return .goToView(n)
        case .saveView(let n):  return .saveView(n)
        case .neighbour(let d): return .neighbour(d, frame: frame)
        default:                return nil
        }
    }
}
