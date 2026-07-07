import SwiftUI
import AXCore

struct ContentView: View {
    @ObservedObject var monitor: ScreenAccessibilityMonitor
    @StateObject private var overlay = SimulatorOverlay()

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
        .frame(width: 380, height: 560)
        .onAppear { monitor.startDeviceHub() }
        .onDisappear { overlay.hide() }
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
                        if hovering {
                            overlay.highlight(
                                iosFrame: element.frame,
                                iosSize: monitor.iosScreenSize,
                                contentRect: monitor.simulatorContentRect
                            )
                        } else {
                            overlay.hide()
                        }
                    }
                    Divider()
                }
            }
        }
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

/// One accessible element: label/value in normal weight, traits in bold.
private struct ElementRow: View {
    let element: AXElement
    let hoverChanged: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(element.primaryText)
                .font(.callout)
            if !element.traits.isEmpty {
                Text(element.traits.joined(separator: " · "))
                    .font(.callout).bold()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0; hoverChanged($0) }
    }
}
