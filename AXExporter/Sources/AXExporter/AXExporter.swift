import Foundation

/// Drop-in accessibility exporter for DeviceHub.
///
/// Add this package to your app and, in a DEBUG build, call
/// `AXExporter.shared.start()` once at launch. DeviceHub can then read the
/// current screen's accessibility tree from `http://<device>:8765/`.
///
/// On the iOS Simulator, `localhost` is shared with the Mac, so DeviceHub reads
/// `http://localhost:8765/`. On a physical device, use its LAN IP.
@MainActor
public final class AXExporter {

    public static let shared = AXExporter()

    private var server: AXExportServer?
    public private(set) var port: UInt16 = 8765

    private init() {}

    /// Starts serving the accessibility snapshot. Idempotent.
    public func start(port: UInt16 = 8765) {
        guard server == nil else { return }
        self.port = port
        do {
            let server = try AXExportServer(port: port) {
                Self.encodedSnapshot()
            }
            server.start()
            self.server = server
            NSLog("[AXExporter] serving accessibility tree on http://localhost:\(port)/")
        } catch {
            NSLog("[AXExporter] failed to start on port \(port): \(error)")
        }
    }

    public func stop() {
        server?.stop()
        server = nil
    }

    /// Encodes the current snapshot. The tree walk must run on the main thread;
    /// the server calls this from its main-queue handler.
    nonisolated private static func encodedSnapshot() -> Data {
        let snapshot = MainActor.assumeIsolated { AccessibilityWalker.snapshot() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return (try? encoder.encode(snapshot)) ?? Data("{}".utf8)
    }
}
