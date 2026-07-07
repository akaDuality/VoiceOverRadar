import SwiftUI
import AXCore

struct ContentView: View {
    @ObservedObject var monitor: ScreenAccessibilityMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if monitor.isTrusted {
                trustedContent
            } else {
                permissionPrompt
            }
            Divider()
            footer
        }
        .padding()
        .frame(width: 380)
        .onAppear { monitor.start() }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Image(systemName: "text.viewfinder")
            Text("VoiceOver Inspector").font(.headline)
            Spacer()
        }
    }

    private var targetPicker: some View {
        HStack(spacing: 6) {
            Menu {
                Button("Frontmost app (auto)") { monitor.followFrontmost() }
                if !monitor.simulatorHosts.isEmpty {
                    Divider()
                    Section("Simulator host") {
                        ForEach(monitor.simulatorHosts) { host in
                            Button("Simulator.app (pid \(host.id))") { monitor.inspect(host) }
                        }
                    }
                }
                if !monitor.simulatorApps.isEmpty {
                    Divider()
                    Section("iOS Simulator apps") {
                        ForEach(monitor.simulatorApps) { app in
                            Button(app.name) { monitor.inspect(app) }
                        }
                    }
                }
            } label: {
                Label(monitor.targetLabel, systemImage: "scope")
            }
            Button {
                monitor.refreshSimulatorApps()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Rescan for Simulator apps")
        }
    }

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accessibility access needed", systemImage: "lock.shield")
                .font(.subheadline).bold()
            Text("Grant access so the inspector can read on-screen elements, "
               + "just like VoiceOver does.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Grant Access…") {
                    AccessibilityPermissions.requestIfNeeded()
                }
                Button("Open Settings") {
                    AccessibilityPermissions.openSettings()
                }
                Button("Re-check") {
                    monitor.refreshTrust()
                    if monitor.isTrusted { monitor.start() }
                }
            }
        }
    }

    private var trustedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            targetPicker

            LabeledContent("Inspecting", value: monitor.frontmostAppName)
                .font(.subheadline)

            Text("Focused element")
                .font(.caption).foregroundStyle(.secondary)
            Text(monitor.focusedDescription.isEmpty
                 ? "(waiting for focus…)"
                 : monitor.focusedDescription)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            if let tree = monitor.tree {
                DisclosureGroup("Screen tree") {
                    ScrollView {
                        NodeView(node: tree)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 220)
                }
                .font(.caption)
            }

            HStack {
                Button("Refresh now") { monitor.refreshNow() }
                Button("Dump AX to file") { monitor.dumpTargetTree() }
            }
            if let path = monitor.lastDumpPath {
                Text("Wrote \(path)")
                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(monitor.isTrusted ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(monitor.isTrusted ? "Accessibility: trusted" : "Accessibility: not trusted")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            Text(Bundle.main.bundlePath)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
        }
    }
}

/// Recursive, indented rendering of the accessibility subtree.
struct NodeView: View {
    let node: AccessibilityReader.Node
    var depth: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(node.description)
                .font(.caption)
                .padding(.leading, CGFloat(depth) * 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(node.children) { child in
                NodeView(node: child, depth: depth + 1)
            }
        }
    }
}
