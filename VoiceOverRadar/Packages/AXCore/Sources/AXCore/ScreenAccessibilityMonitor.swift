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

    /// The current screen's accessible elements, flattened (for the overlay).
    @Published public private(set) var elements: [AXElement] = []
    /// The nested list (containers + cells with indent depth) for the list view.
    @Published public private(set) var rows: [AXRow] = []
    /// The iOS logical screen size (points) of the current DeviceHub snapshot.
    @Published public private(set) var iosScreenSize: CGSize = .zero
    /// The Simulator's on-screen device rect (global, top-left) for overlays.
    @Published public private(set) var simulatorContentRect: CGRect?
    /// True when a popover/sheet/alert is presented in the app.
    @Published public private(set) var modalPresented = false
    @Published public private(set) var modalLabel: String?

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

    /// When set, we poll an in-app AXExporter endpoint (iOS app) instead of the
    /// macOS AX API.
    private var deviceHubEndpoint: (host: String, port: Int)?
    private var deviceHubTimer: Timer?
    private var simulatorTrackTimer: Timer?

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
        let text: String
        if deviceHubEndpoint != nil {
            guard let tree else { return nil }
            text = "DeviceHub target: \(targetLabel)\n\n" + AccessibilityReader.dumpNode(tree)
        } else if let pid = observedPID {
            text = AccessibilityReader.debugDump(pid: pid)
        } else {
            return nil
        }
        let path = "/tmp/vo-inspector-dump.txt"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        lastDumpPath = path
        return path
    }

    /// Pin inspection to a specific process (e.g. an app inside the Simulator).
    public func inspect(_ process: RunningProcess) {
        pinnedPID = process.id
        deviceHubEndpoint = nil
        deviceHubTimer?.invalidate()
        deviceHubTimer = nil
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

    /// Entry point for the simplified DeviceHub-only inspector: begins polling
    /// the local exporter and ensures AX trust (needed for the Simulator overlay).
    public func startDeviceHub(host: String = "localhost", port: Int = 8765) {
        inspectDeviceHub(host: host, port: port)
        startSimulatorTracking()
    }

    /// Re-reads the Simulator's on-screen rect frequently (no Accessibility
    /// permission needed) so the panel stays attached and follows it promptly.
    private func startSimulatorTracking() {
        simulatorTrackTimer?.invalidate()
        simulatorTrackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AccessibilityPermissions.isTrusted
            if trusted != self.isTrusted { self.isTrusted = trusted }
            let rect = self.currentSimulatorRect()
            if rect != self.simulatorContentRect { self.simulatorContentRect = rect }
        }
    }

    /// Exact device rect from the AX `iOSContentGroup` when Accessibility is
    /// granted; otherwise the approximate rect from unprivileged window bounds.
    private func currentSimulatorRect() -> CGRect? {
        if AccessibilityPermissions.isTrusted, let exact = AccessibilityReader.simulatorContentRect() {
            return exact
        }
        return SimulatorLocator.deviceRect(iosSize: iosScreenSize)
    }


    /// Poll an in-app AXExporter endpoint (an iOS app running the exporter).
    public func inspectDeviceHub(host: String = "localhost", port: Int = 8765) {
        pinnedPID = nil
        teardownObserver()
        refreshTimer?.invalidate()
        refreshTimer = nil
        deviceHubEndpoint = (host, port)
        targetLabel = "DeviceHub \(host):\(port)"
        frontmostAppName = targetLabel
        fetchDeviceHub()
        deviceHubTimer?.invalidate()
        deviceHubTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.fetchDeviceHub()
        }
    }

    private func fetchDeviceHub() {
        guard let endpoint = deviceHubEndpoint else { return }
        Task { [weak self] in
            do {
                let snapshot = try await DeviceHubExporterClient.fetch(host: endpoint.host, port: endpoint.port)
                await MainActor.run { [weak self] in
                    guard let self, self.deviceHubEndpoint?.host == endpoint.host else { return }
                    self.applySnapshot(snapshot)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.deviceHubEndpoint != nil else { return }
                    self.focusedDescription = "No response from \(endpoint.host):\(endpoint.port). "
                        + "Is the app running with AXExporter started?"
                    self.tree = nil
                    self.elements = []
                }
            }
        }
    }

    private func applySnapshot(_ snapshot: RemoteAXSnapshot) {
        frontmostAppName = snapshot.appName
        tree = snapshot.rootNode()
        elements = snapshot.flatElements()
        rows = snapshot.rows()
        iosScreenSize = snapshot.iosScreenSize
        simulatorContentRect = SimulatorLocator.deviceRect(iosSize: snapshot.iosScreenSize)
        modalPresented = snapshot.modalPresented ?? false
        modalLabel = snapshot.modalLabel
        focusedDescription = "DeviceHub: \(snapshot.appName), \(elements.count) element(s)."
    }

    /// Activate an element (VoiceOver single-tap) by id.
    public func activate(id: String) { sendAction(id: id, type: "activate") }
    /// Increment an adjustable element by id.
    public func increment(id: String) { sendAction(id: id, type: "increment") }
    /// Decrement an adjustable element by id.
    public func decrement(id: String) { sendAction(id: id, type: "decrement") }
    /// Invoke a named custom action on an element by id.
    public func performCustomAction(id: String, name: String) {
        sendAction(id: id, type: "custom", name: name)
    }

    /// VoiceOver escape (scrub) — dismisses the presented popover/sheet.
    public func escape() { sendAction(type: "escape") }
    /// VoiceOver magic tap — the app's primary action.
    public func magicTap() { sendAction(type: "magictap") }

    private func sendAction(id: String? = nil, type: String, name: String? = nil) {
        guard let endpoint = deviceHubEndpoint else { return }
        Task { [weak self] in
            guard let snapshot = try? await DeviceHubExporterClient.sendAction(
                host: endpoint.host, port: endpoint.port, id: id, type: type, name: name
            ) else { return }
            await MainActor.run { [weak self] in
                guard let self, self.deviceHubEndpoint != nil else { return }
                self.applySnapshot(snapshot)
            }
        }
    }

    /// Return to following whichever macOS app is frontmost.
    public func followFrontmost() {
        pinnedPID = nil
        deviceHubEndpoint = nil
        deviceHubTimer?.invalidate()
        deviceHubTimer = nil
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
        deviceHubTimer?.invalidate()
        deviceHubTimer = nil
        simulatorTrackTimer?.invalidate()
        simulatorTrackTimer = nil
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
        // Don't let app switches steal focus from a pinned or DeviceHub target.
        guard pinnedPID == nil, deviceHubEndpoint == nil else { return }
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
