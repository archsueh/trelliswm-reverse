import Foundation

/// The "camera" is just a node id plus browser-like history. There is no hidden
/// zoom engine in the observable document: `framed` in layout-*.json points at
/// the node being looked at, and `framings` caches where to return to.
public struct CameraState: Codable, Equatable, Sendable {
    /// Node id currently framed. `"desktop"` is both the floating-layer leaf id
    /// and the value seen in all-floating documents, where root == desktop; the
    /// two readings cannot be separated from the captured samples. This build
    /// keeps them distinct: `everything` frames the root, `frameDesktop` frames
    /// the desktop leaf (see investigation.cany/questions.md Q16).
    public var framed: String
    public var backStack: [String]
    public var forwardStack: [String]
    /// 1...9, per display in the subject.
    public var savedViews: [Int: String]
    public var desktopHidden: Bool

    public init(framed: String = "desktop",
                backStack: [String] = [],
                forwardStack: [String] = [],
                savedViews: [Int: String] = [:],
                desktopHidden: Bool = false) {
        self.framed = framed
        self.backStack = backStack
        self.forwardStack = forwardStack
        self.savedViews = savedViews
        self.desktopHidden = desktopHidden
    }
}

public enum CameraAction: Equatable, Sendable {
    case everything
    case zoomIn(towardSeat: String?)
    case zoomOut
    case frame(nodeID: String)
    case frameDesktop
    case toggleDesktop
    case back
    case forward
    case saveView(Int)
    case goToView(Int)
    case neighbour(Direction, frame: Rect)
}

public struct Camera: Sendable {
    public var engine: LayoutEngine

    public init(engine: LayoutEngine = LayoutEngine()) { self.engine = engine }

    public func apply(_ action: CameraAction, to state: CameraState,
                      in tree: LayoutNode, frame: Rect) -> CameraState {
        switch action {
        case .everything:
            return move(to: tree.id, state)

        case .zoomOut:
            let path = engine.path(to: state.framed, in: tree)
            let target = path.count > 1 ? path[path.count - 2] : tree.id
            return move(to: target, state)

        case .zoomIn(let seat):
            let target: String
            if let seat, let found = engine.zoomTarget(containing: seat, in: tree) {
                target = found
            } else if let node = tree.node(id: state.framed),
                      let first = node.children.first(where: { $0.id != "desktop" }) {
                target = first.id
            } else {
                let deepest = tree.leaves.first { $0.id != "desktop" }
                target = deepest?.id ?? state.framed
            }
            return move(to: target, state)

        case .frame(let nodeID):
            guard tree.node(id: nodeID) != nil else { return state }
            // "again to go back": framing the same node returns to the parent.
            if state.framed == nodeID {
                return move(to: tree.id, state)
            }
            return move(to: nodeID, state)

        case .frameDesktop:
            return state.framed == "desktop" ? move(to: tree.id, state) : move(to: "desktop", state)

        case .toggleDesktop:
            var next = state
            next.desktopHidden.toggle()
            return next

        case .back:
            guard let previous = state.backStack.last else { return state }
            var next = state
            next.backStack.removeLast()
            next.forwardStack.append(state.framed)
            next.framed = previous
            return next

        case .forward:
            guard let following = state.forwardStack.last else { return state }
            var next = state
            next.forwardStack.removeLast()
            next.backStack.append(state.framed)
            next.framed = following
            return next

        case .saveView(let n):
            guard (1...9).contains(n) else { return state }
            var next = state
            next.savedViews[n] = state.framed
            return next

        case .goToView(let n):
            guard (1...9).contains(n), let target = state.savedViews[n],
                  tree.node(id: target) != nil || target == "desktop" else { return state }
            return move(to: target, state)

        case .neighbour(let direction, let rect):
            guard let target = engine.neighbour(of: state.framed, direction: direction,
                                                in: tree, frame: rect) else { return state }
            return move(to: target, state)
        }
    }

    private func move(to target: String, _ state: CameraState) -> CameraState {
        guard target != state.framed else { return state }
        var next = state
        next.backStack.append(state.framed)
        next.forwardStack.removeAll()
        next.framed = target
        return next
    }
}
