import SwiftUI
import AXCore

struct ContentView: View {
    @ObservedObject var monitor: ScreenAccessibilityMonitor
    @StateObject private var overlay = SimulatorOverlay()
    @State private var hoveredID: String?
    @State private var window: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !monitor.isTrusted {
                permissionBanner
                Divider()
            }

            if monitor.elements.isEmpty {
                emptyState
            } else {
                elementList
            }

            Divider()
            footer
        }
        .frame(width: 260, height: 560)
        .background(VisualEffectView().ignoresSafeArea())
        .background(WindowAccessor { configureWindow($0) })
        .onAppear { monitor.startDeviceHub() }
        .onChange(of: monitor.simulatorContentRect) { _ in positionNearSimulator() }
        .onDisappear { overlay.hide() }
    }

    private func configureWindow(_ window: NSWindow) {
        self.window = window
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        positionNearSimulator()
    }

    /// Keep the window docked just right of the Simulator; follows it when the
    /// Simulator is moved (fires whenever the device rect changes).
    private func positionNearSimulator() {
        guard let window, let rect = monitor.simulatorContentRect else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        // setFrameTopLeftPoint uses Cocoa (bottom-left origin) screen coords.
        let topLeft = NSPoint(x: rect.maxX + 48, y: primaryHeight - rect.minY)
        window.setFrameTopLeftPoint(topLeft)
    }

    // MARK: Sections

    private var elementList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(monitor.elements) { element in
                    ElementRow(element: element) { hovering in
                        if hovering { hoveredID = element.id }
                        else if hoveredID == element.id { hoveredID = nil }
                    }
                    Divider()
                }
            }
        }
        .onChange(of: hoveredID) { _ in refreshOverlay() }
        .onChange(of: monitor.elements) { _ in if hoveredID != nil { refreshOverlay() } }
    }

    private func refreshOverlay() {
        guard let hoveredID else { overlay.hide(); return }
        overlay.showAll(
            elements: monitor.elements,
            hoveredID: hoveredID,
            iosSize: monitor.iosScreenSize,
            contentRect: monitor.simulatorContentRect
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
            Text("Waiting for the app on localhost:8765…")
                .font(.callout).foregroundStyle(.secondary)
            Text("Run the app with AXExporter started.")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield").foregroundStyle(.orange)
            Text("Grant Accessibility to enable Simulator outlines")
                .font(.caption)
            Spacer()
            Button("Grant") { AccessibilityPermissions.requestIfNeeded() }
                .controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(monitor.simulatorContentRect == nil ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            Text(simulatorStatus)
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text("\(monitor.elements.count) elements")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var simulatorStatus: String {
        guard let r = monitor.simulatorContentRect else { return "Simulator not located" }
        return "Sim \(Int(r.width))×\(Int(r.height)) @(\(Int(r.minX)),\(Int(r.minY)))"
    }
}

/// A behind-window vibrancy blur for the inspector background.
private struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Grabs the hosting `NSWindow` so we can position it programmatically.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onResolve(window) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// One accessible element: label/value in normal weight, traits in bold.
private struct ElementRow: View {
    let element: AXElement
    let hoverChanged: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(element.primaryText)
                .font(.callout)
            if !element.traits.isEmpty {
                Text(element.traits.joined(separator: " · "))
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0; hoverChanged($0) }
    }
}
