import Foundation

/// Decodes the JSON served by the in-app `AXExporter` (running inside an iOS
/// app in the Simulator or on-device) and maps it into the same `Node` model
/// the inspector renders for macOS AX trees.
///
/// The shapes here mirror `AXExporter`'s `AXSnapshot`/`AXNode`. They're
/// duplicated rather than shared because that package is iOS-only (UIKit).

public struct RemoteAXSnapshot: Codable, Sendable {
    public var appName: String
    public var screenSize: [Double]
    public var roots: [RemoteAXNode]

    /// A single root node summarizing the screen, for the tree view.
    public func rootNode() -> AccessibilityReader.Node {
        let w = Int(screenSize.first ?? 0)
        let h = Int(screenSize.last ?? 0)
        return AccessibilityReader.Node(
            description: "\(appName) — \(w)×\(h)",
            role: "screen",
            children: roots.map { $0.asNode() }
        )
    }
}

public struct RemoteAXNode: Codable, Sendable {
    public var label: String?
    public var value: String?
    public var hint: String?
    public var identifier: String?
    public var traits: [String]
    public var isElement: Bool
    public var frame: [Double]
    public var voiceOver: String
    public var children: [RemoteAXNode]

    func asNode() -> AccessibilityReader.Node {
        var text = voiceOver
        if frame.count == 4 {
            text += "  @(\(Int(frame[0])),\(Int(frame[1])) \(Int(frame[2]))×\(Int(frame[3])))"
        }
        return AccessibilityReader.Node(
            description: text,
            role: traits.first,
            children: children.map { $0.asNode() }
        )
    }
}

public enum DeviceHubExporterClient {
    /// Fetches and decodes the current snapshot from an exporter endpoint.
    public static func fetch(host: String, port: Int) async throws -> RemoteAXSnapshot {
        guard let url = URL(string: "http://\(host):\(port)/") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(RemoteAXSnapshot.self, from: data)
    }
}
