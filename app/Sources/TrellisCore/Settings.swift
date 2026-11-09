import Foundation

/// The 47 release defaults shipped in the subject's Resources/ReleaseSettings.json.
/// Property names intentionally match the observed keys so `Codable` needs no
/// custom CodingKeys; `checks/check_evidence.py` diffs this struct against the
/// captured file. The `offered` visibility tiers live in capture/ only.
public struct Settings: Codable, Equatable, Sendable {
    public var animationSpeed: Double = 1
    public var appColourAmount: Double = 0.25
    public var appColours: Bool = true
    public var deskGapHandles: Bool = true
    public var deskPinchSteps: Bool = false
    public var desktopEdgeStrength: Double = 0.05
    public var dimBlur: Int = 20
    public var dimDocked: Bool = true
    public var dimOpacity: Double = 0.3
    public var fixedMinimum: Bool = false
    public var gap: Int = 12
    public var gapHandlesAlwaysShown: Bool = false
    public var gesturesLand: Bool = false
    public var hiddenDesktopReturns: Bool = false
    public var historyButtons: Bool = true
    public var interruptLandings: Bool = true
    public var keepPushed: Bool = true
    public var menuBarControls: Bool = true
    public var menuBarFill: Double = 0.12
    public var overviewSwipesSpaces: Bool = false
    public var panSensitivity: Double = 1.8
    public var parkOutOfViewSmall: Bool = true
    public var previewDrags: Bool = true
    public var previewStyle: String = "tinted"
    public var redrawWait: Double = 0.5
    public var reflowWhileDragging: Bool = true
    public var replaceMissionControl: Bool = true
    public var returnReopenedWindows: String = "afterQuit"
    public var shareRemovedSpace: Bool = true
    public var soleFloatTakesDesktop: Bool = true
    public var squeezeBelowMinimum: Bool = true
    public var stepTowardPointer: Bool = false
    public var stretchPictures: Bool = false
    public var tabChipMargin: Int = 4
    public var tabCloseButtons: Bool = true
    public var tabCloseOnRight: Bool = false
    public var tabGlassOpaqueWhenInactive: Bool = true
    public var tabInset: Int = 2
    public var tabPadding: Int = 8
    public var tabSelectedChip: Bool = true
    public var tabStripLights: Bool = false
    public var tabStyle: String = "material"
    public var tabTint: Int = 0
    public var tintOpacity: Double = 0.8
    public var touchPinchPan: Bool = true
    public var tuckStrips: Bool = false
    public var windowButtonsActOnGroup: Bool = true

    public init() {}

    public static let release = Settings()

    /// Number of declared keys. The evidence file has 47; the test asserts this.
    public static var keyCount: Int {
        Mirror(reflecting: Settings()).children.count
    }

    public func asJSONObject() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            throw LayoutError.invariant("settings did not encode to an object")
        }
        return dict
    }

    /// Geometry/animation knobs consumed by the pure core.
    public var layoutEngine: LayoutEngine {
        LayoutEngine(gap: Double(gap), minimumShare: 0.05)
    }
}

/// Placeholder for the subject's window-identity matching. The real algorithm
/// (mirrorDigest / saltDigest / title-token weighting) is not observable, so the
/// clean-room build exposes a protocol instead of inventing an equivalent.
public protocol SeatMatcher: Sendable {
    func match(departed: SeatFingerprint, candidates: [SeatFingerprint]) -> String?
}

public struct SeatFingerprint: Codable, Equatable, Sendable {
    public var seatID: String
    public var bundleID: String
    public var document: String?
    public var titleTokens: [String]
    public var number: Int
    public var order: Int
    public var placement: String

    public init(seatID: String, bundleID: String, document: String? = nil,
                titleTokens: [String] = [], number: Int = 0, order: Int = 0,
                placement: String = "floating") {
        self.seatID = seatID; self.bundleID = bundleID; self.document = document
        self.titleTokens = titleTokens; self.number = number; self.order = order
        self.placement = placement
    }
}

/// A deterministic, obviously-not-equivalent fallback used by the simulator.
public struct SimpleSeatMatcher: SeatMatcher {
    public init() {}
    public func match(departed: SeatFingerprint, candidates: [SeatFingerprint]) -> String? {
        candidates.first { $0.bundleID == departed.bundleID && $0.document == departed.document }?.seatID
    }
}
