import SwiftUI
import AXCore

struct ContentView: View {
    @ObservedObject var monitor: ScreenAccessibilityMonitor
    @StateObject private var overlay = SimulatorOverlay()
    @State private var hoveredID: String?
    @State private var window: NSWindow?
    @State private var didPosition = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

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
        .frame(width: 200, height: 560)
        .background(WindowAccessor { window = $0; positionNearSimulator() })
        .onAppear { monitor.startDeviceHub() }
        .onChange(of: monitor.simulatorContentRect) { _ in positionNearSimulator() }
        .onDisappear { overlay.hide() }
    }

    /// Dock the window just to the right of the Simulator, once, as a companion.
    private func positionNearSimulator() {
        guard !didPosition, let window, let rect = monitor.simulatorContentRect else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        // setFrameTopLeftPoint uses Cocoa (bottom-left origin) screen coords.
        let topLeft = NSPoint(x: rect.maxX + 48, y: primaryHeight - rect.minY)
        window.setFrameTopLeftPoint(topLeft)
        didPosition = true
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.viewfinder")
            Text(monitor.frontmostAppName).font(.headline)
            Spacer()
        }
        .padding(12)
    }

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
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var simulatorStatus: String {
        guard let r = monitor.simulatorContentRect else { return "Simulator not located" }
        return "Sim \(Int(r.width))×\(Int(r.height)) @(\(Int(r.minX)),\(Int(r.minY)))"
    }
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
