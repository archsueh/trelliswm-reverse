import Carbon
import Foundation

/// Global hotkeys via Carbon `RegisterEventHotKey`. This needs no Input
/// Monitoring permission, unlike a CGEvent tap.
enum WMHotkey: UInt32, CaseIterable {
    case focusNext = 1
    case focusPrev = 2
    case swapNext = 3
    case swapPrev = 4
    case toggleAxis = 5
    case grow = 6
    case shrink = 7
    case retile = 8
    case toggleTiling = 9

    var menuLabel: String {
        switch self {
        case .focusNext: return "Focus Next"
        case .focusPrev: return "Focus Previous"
        case .swapNext: return "Swap with Next"
        case .swapPrev: return "Swap with Previous"
        case .toggleAxis: return "Toggle Split Orientation"
        case .grow: return "Grow Tile"
        case .shrink: return "Shrink Tile"
        case .retile: return "Retile Now"
        case .toggleTiling: return "Toggle Tiling"
        }
    }

    /// Human-readable binding, using Control-Option-Command to stay off
    /// common macOS shortcuts and the original TrellisWM ⌃⌥ map.
    var binding: String {
        switch self {
        case .focusNext: return "⌃⌥⌘J"
        case .focusPrev: return "⌃⌥⌘K"
        case .swapNext: return "⌃⌥⌘⇧J"
        case .swapPrev: return "⌃⌥⌘⇧K"
        case .toggleAxis: return "⌃⌥⌘O"
        case .grow: return "⌃⌥⌘="
        case .shrink: return "⌃⌥⌘-"
        case .retile: return "⌃⌥⌘R"
        case .toggleTiling: return "⌃⌥⌘T"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .focusNext, .swapNext: return UInt32(kVK_ANSI_J)
        case .focusPrev, .swapPrev: return UInt32(kVK_ANSI_K)
        case .toggleAxis: return UInt32(kVK_ANSI_O)
        case .grow: return UInt32(kVK_ANSI_Equal)
        case .shrink: return UInt32(kVK_ANSI_Minus)
        case .retile: return UInt32(kVK_ANSI_R)
        case .toggleTiling: return UInt32(kVK_ANSI_T)
        }
    }

    var modifiers: UInt32 {
        let base = UInt32(controlKey | optionKey | cmdKey)
        switch self {
        case .swapNext, .swapPrev:
            return base | UInt32(shiftKey)
        default:
            return base
        }
    }
}

@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    var onHotkey: ((WMHotkey) -> Void)?
    private var refs: [EventHotKeyRef?] = []
    private var installed = false

    private static let signature = OSType(0x5452574D) // 'TRWM'

    func register() {
        if !installed {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(),
                                hotkeyEventHandler,
                                1,
                                &eventType,
                                nil,
                                nil)
            installed = true
        }
        unregister()
        for key in WMHotkey.allCases {
            var ref: EventHotKeyRef?
            let ident = EventHotKeyID(signature: Self.signature, id: key.rawValue)
            let status = RegisterEventHotKey(key.keyCode, key.modifiers, ident,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr {
                refs.append(ref)
            }
        }
    }

    func unregister() {
        for ref in refs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        refs.removeAll()
    }

    fileprivate func dispatch(_ id: UInt32) {
        if let key = WMHotkey(rawValue: id) {
            onHotkey?(key)
        }
    }
}

private func hotkeyEventHandler(next: EventHandlerCallRef?,
                                event: EventRef?,
                                userData: UnsafeMutableRawPointer?) -> OSStatus {
    var ident = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &ident)
    guard status == noErr, ident.signature == OSType(0x5452574D) else { return status }
    let hotKeyID = ident.id
    DispatchQueue.main.async {
        HotkeyCenter.shared.dispatch(hotKeyID)
    }
    return noErr
}
