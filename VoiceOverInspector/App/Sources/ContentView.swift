import SwiftUI
import AXCore

struct ContentView: View {
    @ObservedObject var monitor: ScreenAccessibilityMonitor
    @StateObject private var overlay = SimulatorOverlay()
    @State private var hoveredID: String?
    @State private var window: NSWindow?

    var body: some View {
        ZStack(alignment: .top) {
            VisualEffectView().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                if !monitor.isTrusted {
                    permissionBanner
                    Divider()
                }

                if monitor.modalPresented {
                    modalBanner
                    Divider()
                }

                if monitor.elements.isEmpty {
                    emptyState
                } else {
                    elementList
                }

                Divider()
                gestureBar
                Divider()
                footer
            }
        }
        .frame(width: 260)
        .frame(maxHeight: .infinity)
        .background(WindowAccessor { configureWindow($0) })
        .onAppear { monitor.startDeviceHub() }
        .onChange(of: monitor.simulatorContentRect) { _ in positionNearSimulator() }
        .onDisappear { overlay.hide() }
    }

    private func configureWindow(_ window: NSWindow) {
        self.window = window
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
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
        // Match the Simulator's device height; dock to its right, tops aligned.
        let width: CGFloat = 260
        let cocoaY = primaryHeight - (rect.minY + rect.height)
        window.setFrame(
            NSRect(x: rect.maxX + 48, y: cocoaY, width: width, height: rect.height),
            display: true
        )
    }

    // MARK: Sections

    private var elementList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(monitor.elements) { element in
                    ElementRow(
                        element: element,
                        hoverChanged: { hovering in
                            if hovering { hoveredID = element.id }
                            else if hoveredID == element.id { hoveredID = nil }
                        },
                        onTap: {
                            SimulatorInput.tap(
                                iosFrame: element.frame,
                                iosSize: monitor.iosScreenSize,
                                contentRect: monitor.simulatorContentRect
                            )
                        },
                        onIncrement: { monitor.increment(element) },
                        onDecrement: { monitor.decrement(element) },
                        onCustomAction: { name in monitor.performCustomAction(element, name: name) }
                    )
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

    private var gestureBar: some View {
        HStack(spacing: 6) {
            Button {
                monitor.magicTap()
            } label: {
                Label("Magic Tap", systemImage: "hand.tap")
            }
            Button {
                monitor.escape()
            } label: {
                Label("Scrub", systemImage: "scribble")
            }
            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private var modalBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.on.rectangle.angled")
            Text(monitor.modalLabel.map { "Popover: \($0)" } ?? "Popover presented")
                .font(.caption).bold()
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .foregroundStyle(.orange)
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
    let onTap: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onCustomAction: (String) -> Void
    @State private var hovering = false

    private var hasControls: Bool { element.isAdjustable || !element.customActions.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(element.primaryText)
                .font(.callout)
            if !element.traits.isEmpty {
                Text(element.traits.joined(separator: " · "))
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
            }
            ForEach(element.customContent, id: \.self) { content in
                Text(content)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if hasControls { controls }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(hovering ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0; hoverChanged($0) }
        .onTapGesture { onTap() }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if element.isAdjustable {
                Button { onDecrement() } label: { Image(systemName: "minus") }
                Button { onIncrement() } label: { Image(systemName: "plus") }
            }
            ForEach(element.customActions, id: \.self) { name in
                Button(name) { onCustomAction(name) }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
