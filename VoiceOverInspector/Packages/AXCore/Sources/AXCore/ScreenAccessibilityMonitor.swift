import AppKit
import ApplicationServices
import Combine

/// Observes the frontmost application and publishes a live, VoiceOver-style
/// description of whatever is currently focused on screen.
///
/// Retargets automatically when the user switches apps, and reacts to focus,
/// value, and selection changes via an `AXObserver` — the same event stream
/// VoiceOver responds to. Updates are delivered on the main run loop.
public final class ScreenAccessibilityMonitor: ObservableObject {

    @Published public private(set) var frontmostAppName: String = "—"
    @Published public private(set) var focusedDescription: String = ""
    @Published public private(set) var isTrusted: Bool = AccessibilityPermissions.isTrusted
    @Published public private(set) var tree: AccessibilityReader.Node?

    /// Simulated iOS apps currently running, offered as inspection targets.
    @Published public private(set) var simulatorApps: [RunningProcess] = []
    /// Simulator.app host process(es), also offered as targets.
    @Published public private(set) var simulatorHosts: [RunningProcess] = []
    /// Path of the last diagnostics dump written, for display.
    @Published public private(set) var lastDumpPath: String?
    /// Label of what we're currently inspecting.
    @Published public private(set) var targetLabel: String = "Frontmost app"

    private var observer: AXObserver?
    private var observedApp: AXUIElement?
    private var observedPID: pid_t?
    private var workspaceToken: NSObjectProtocol?
    private var trustTimer: Timer?
    private var refreshTimer: Timer?

    /// When set, we inspect this pinned process instead of following the
    /// frontmost app (used for apps inside the iOS Simulator).
    private var pinnedPID: pid_t?

    private let ownPID = ProcessInfo.processInfo.processIdentifier

    public init() {}

    deinit { stop() }

    /// Begins monitoring. Safe to call after the user grants permission.
    public func start() {
        refreshTrust()
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.retarget(to: app ?? NSWorkspace.shared.frontmostApplication)
        }
        retarget(to: NSWorkspace.shared.frontmostApplication)
        refreshSimulatorApps()

        // The user may grant Accessibility access while the app is already
        // running. Poll until trusted, then wire up observing automatically —
        // no relaunch or button press needed.
        if !isTrusted { startTrustPolling() }
    }

    /// Rescans for running iOS Simulator apps and hosts.
    public func refreshSimulatorApps() {
        simulatorApps = HostProcesses.simulatorApps()
        simulatorHosts = HostProcesses.simulatorHosts()
    }

    /// Writes a verbose AX dump of the current target to /tmp for diagnostics.
    @discardableResult
    public func dumpTargetTree() -> String? {
        guard let pid = observedPID else { return nil }
        let text = AccessibilityReader.debugDump(pid: pid)
        let path = "/tmp/vo-inspector-dump.txt"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        lastDumpPath = path
        return path
    }

    /// Pin inspection to a specific process (e.g. an app inside the Simulator).
    public func inspect(_ process: RunningProcess) {
        pinnedPID = process.id
        targetLabel = process.name
        teardownObserver()
        frontmostAppName = process.name
        observedPID = process.id
        observedApp = AXUIElementCreateApplication(process.id)
        // Ask lazily-vending apps (iOS Simulator) to activate accessibility.
        AccessibilityReader.enableManualAccessibility(pid: process.id)
        setupObserver(pid: process.id)
        updateContent()
        // iOS apps push few AX notifications; poll to keep the tree fresh.
        startContentRefresh()
    }

    /// Return to following whichever macOS app is frontmost.
    public func followFrontmost() {
        pinnedPID = nil
        targetLabel = "Frontmost app"
        refreshTimer?.invalidate()
        refreshTimer = nil
        retarget(to: NSWorkspace.shared.frontmostApplication)
    }

    private func startContentRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateContent()
        }
    }

    /// Stops monitoring and tears down all observers.
    public func stop() {
        if let token = workspaceToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceToken = nil
        trustTimer?.invalidate()
        trustTimer = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        teardownObserver()
    }

    private func startTrustPolling() {
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshTrust()
            guard self.isTrusted else { return }
            self.trustTimer?.invalidate()
            self.trustTimer = nil
            self.retarget(to: NSWorkspace.shared.frontmostApplication)
        }
    }

    public func refreshTrust() {
        isTrusted = AccessibilityPermissions.isTrusted
    }

    /// Forces an immediate re-read of the current target.
    public func refreshNow() {
        refreshSimulatorApps()
        updateContent()
    }

    // MARK: Targeting

    private func retarget(to app: NSRunningApplication?) {
        // Don't let app switches steal focus away from a pinned Simulator app.
        guard pinnedPID == nil else { return }
        // Ignore ourselves (e.g. when the menu bar popover takes focus) so the
        // last real target's description stays on screen.
        guard let app, app.processIdentifier != ownPID else { return }

        teardownObserver()
        frontmostAppName = app.localizedName ?? "Unknown"
        observedPID = app.processIdentifier
        observedApp = AXUIElementCreateApplication(app.processIdentifier)
        setupObserver(pid: app.processIdentifier)
        updateContent()
    }

    // MARK: AXObserver wiring

    private func setupObserver(pid: pid_t) {
        guard isTrusted, let app = observedApp else { return }

        var created: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &created) == .success,
              let created else { return }

        let notifications = [
            kAXFocusedUIElementChangedNotification,
            kAXValueChangedNotification,
            kAXSelectedTextChangedNotification,
            kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification,
        ]
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in notifications {
            AXObserverAddNotification(created, app, notification as CFString, refcon)
        }

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(created),
            .defaultMode
        )
        observer = created
    }

    private func teardownObserver() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observer = nil
        observedApp = nil
        observedPID = nil
    }

    fileprivate func handleNotification() {
        updateContent()
    }

    private func updateContent() {
        guard let pid = observedPID else { return }

        if pinnedPID != nil {
            // Pinned target (e.g. iOS Simulator app): show the whole app tree,
            // since iOS apps rarely expose a single macOS-style focused element.
            tree = AccessibilityReader.snapshotApplication(pid: pid)
            if let focused = AccessibilityReader.focusedElement(ofPID: pid) {
                focusedDescription = AccessibilityReader.voiceOverDescription(for: focused)
            } else {
                focusedDescription = "Showing full accessibility tree for \(targetLabel)."
            }
            return
        }

        // Frontmost macOS app: follow the focused element.
        guard let focused = AccessibilityReader.focusedElement(ofPID: pid) else {
            focusedDescription = "(nothing focused)"
            return
        }
        focusedDescription = AccessibilityReader.voiceOverDescription(for: focused)
        if let window = AccessibilityReader.focusedWindow(ofPID: pid) {
            tree = AccessibilityReader.snapshot(of: window)
        }
    }
}

/// C callback bridged back to the owning monitor via the `refcon` pointer.
/// Must not capture state so it converts to a `@convention(c)` function pointer.
private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let monitor = Unmanaged<ScreenAccessibilityMonitor>
        .fromOpaque(refcon)
        .takeUnretainedValue()
    monitor.handleNotification()
}
