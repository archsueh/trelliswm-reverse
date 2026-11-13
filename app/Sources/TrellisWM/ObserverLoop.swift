import AppKit
import ApplicationServices
import Foundation

/// Per-application AXObserver plus NSWorkspace launch/terminate notifications.
/// All window events are coalesced onto a single debounced retile callback.
@MainActor
final class ObserverLoop: NSObject {
    static weak var current: ObserverLoop?

    var onChange: (() -> Void)?

    /// While frames are being written, incoming AX events are not dropped:
    /// they set `pendingWhileApplying` and flush into a retile once
    /// `isApplying` becomes false.
    var isApplying = false {
        didSet {
            if oldValue && !isApplying && pendingWhileApplying {
                pendingWhileApplying = false
                schedule()
            }
        }
    }
    private var pendingWhileApplying = false

    private var observers: [Int32: AXObserver] = [:]
    private var debounceWork: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.12
    private var workspaceObservers: [NSObjectProtocol] = []

    func start() {
        stop()
        ObserverLoop.current = self
        let nc = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                           object: nil, queue: nil) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                let regular = app?.activationPolicy == .regular
                DispatchQueue.main.async {
                    Task { @MainActor in
                        if let pid, regular { self?.attach(pid: pid) }
                        self?.schedule()
                    }
                }
            },
            nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                           object: nil, queue: nil) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let pid = app?.processIdentifier
                DispatchQueue.main.async {
                    Task { @MainActor in
                        if let pid { self?.detach(pid: pid) }
                        self?.schedule()
                    }
                }
            },
        ]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            attach(pid: app.processIdentifier)
        }
    }

    func stop() {
        debounceWork?.cancel()
        for pid in Array(observers.keys) { detach(pid: pid) }
        let nc = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers { nc.removeObserver(token) }
        workspaceObservers.removeAll()
        if ObserverLoop.current === self { ObserverLoop.current = nil }
    }

    func schedule() {
        if isApplying {
            pendingWhileApplying = true
            return
        }
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    func attach(pid: Int32) {
        if pid == ProcessInfo.processInfo.processIdentifier { return }
        if observers[pid] != nil {
            observeExistingWindows(pid: pid)
            return
        }
        var observer: AXObserver?
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverCreate(pid, observerCallback, &observer) == .success,
              let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        let appNotes = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]
        for note in appNotes {
            _ = AXObserverAddNotification(observer, app, note as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        observeExistingWindows(pid: pid)
    }

    func detach(pid: Int32) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    func observeExistingWindows(pid: Int32) {
        guard let observer = observers[pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        let notes = [
            kAXUIElementDestroyedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
        ]
        for window in windows {
            for note in notes {
                _ = AXObserverAddNotification(observer, window, note as CFString, refcon)
            }
        }
    }
}

private func observerCallback(_ observer: AXObserver,
                              _ element: AXUIElement,
                              _ notification: CFString,
                              _ refcon: UnsafeMutableRawPointer?) {
    let name = notification as String
    var pid: pid_t = 0
    let gotPID = AXUIElementGetPid(element, &pid) == .success
    DispatchQueue.main.async {
        Task { @MainActor in
            guard let loop = ObserverLoop.current else { return }
            if name == (kAXWindowCreatedNotification as String), gotPID {
                loop.observeExistingWindows(pid: pid)
            }
            loop.schedule()
        }
    }
}
