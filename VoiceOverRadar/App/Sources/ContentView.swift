import SwiftUI
import AXCore

struct ContentView: View {
    @ObservedObject var monitor: ScreenAccessibilityMonitor
    @StateObject private var overlay = SimulatorOverlay()
    @State private var hoveredID: String?
    @State private var hoveredFrame: CGRect?
    @State private var window: NSWindow?

    var body: some View {
        ZStack(alignment: .top) {
            VisualEffectView().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                if monitor.modalPresented {
                    modalBanner
                    Divider()
                }

                if monitor.rows.isEmpty {
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
        // Sane default until the Simulator is located and we dock/resize to it.
        window.setContentSize(NSSize(width: 260, height: 600))
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
                ForEach(monitor.rows) { row in
                    RowView(
                        row: row,
                        hoverChanged: { hovering in
                            if hovering { hoveredID = row.id; hoveredFrame = row.frame }
                            else if hoveredID == row.id { hoveredID = nil; hoveredFrame = nil }
                        },
                        onActivate: { monitor.activate(id: row.id) },
                        onIncrement: { monitor.increment(id: row.id) },
                        onDecrement: { monitor.decrement(id: row.id) },
                        onCustomAction: { name in monitor.performCustomAction(id: row.id, name: name) }
                    )
                    Divider()
                }
            }
        }
        .onChange(of: hoveredID) { _ in refreshOverlay() }
        .onChange(of: monitor.elements) { _ in if hoveredID != nil { refreshOverlay() } }
    }

    private func refreshOverlay() {
        guard hoveredID != nil else { overlay.hide(); return }
        overlay.showAll(
            elements: monitor.elements,
            hoveredFrame: hoveredFrame,
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

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(monitor.simulatorContentRect == nil ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            Text(simulatorStatus)
                .font(.caption2).foregroundStyle(.secondary)
            if !monitor.isTrusted {
                // Optional: grant AX for exact outlines when device bezels are on.
                Button("Exact") { AccessibilityPermissions.requestIfNeeded() }
                    .controlSize(.mini)
                    .help("Grant Accessibility for pixel-exact outlines with device bezels shown")
            }
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

/// A nested row: a named container (bold + type) or an element (label + traits),
/// indented by depth. Elements carry adjustable/custom-action controls.
private struct RowView: View {
    let row: AXRow
    let hoverChanged: (Bool) -> Void
    let onActivate: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onCustomAction: (String) -> Void
    @State private var hovering = false

    private var hasControls: Bool { row.isAdjustable || !row.customActions.isEmpty }
    private var indent: CGFloat { 12 + CGFloat(row.depth) * 14 }

    var body: some View {
        Group {
            if row.isContainer { container } else { element }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, indent).padding(.trailing, 12).padding(.vertical, 6)
        .background(background)
        .contentShape(Rectangle())
        .onHover { hovering = $0; hoverChanged($0) }
        .onTapGesture { onActivate() }
    }

    private var background: some ShapeStyle {
        hovering ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                 : AnyShapeStyle(row.isContainer ? Color.secondary.opacity(0.06) : Color.clear)
    }

    private var container: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up").font(.caption2).foregroundStyle(.secondary)
            Text(row.primaryText).font(.callout).bold()
            if let type = row.containerType {
                Text(type).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var element: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.primaryText).font(.callout)
            if !row.traits.isEmpty {
                Text(row.traits.joined(separator: " · "))
                    .font(.caption).bold().foregroundStyle(.secondary)
            }
            ForEach(row.customContent, id: \.self) { content in
                Text(content).font(.caption2).foregroundStyle(.secondary)
            }
            if hasControls { controls }
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            if row.isAdjustable {
                Button { onDecrement() } label: { Image(systemName: "minus") }
                Button { onIncrement() } label: { Image(systemName: "plus") }
            }
            ForEach(row.customActions, id: \.self) { name in
                Button(name) { onCustomAction(name) }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
