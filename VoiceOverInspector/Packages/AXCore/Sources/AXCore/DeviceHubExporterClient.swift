import Foundation

/// Decodes the JSON served by the in-app `AXExporter` (running inside an iOS
/// app in the Simulator or on-device) and maps it into the same `Node` model
/// the inspector renders for macOS AX trees.
///
/// The shapes here mirror `AXExporter`'s `AXSnapshot`/`AXNode`. They're
/// duplicated rather than shared because that package is iOS-only (UIKit).

/// A single accessible element, flattened out of the tree for a simple list.
public struct AXElement: Identifiable, Sendable {
    public let id = UUID()
    public let label: String?
    public let value: String?
    public let traits: [String]
    /// Frame in iOS points (top-left origin), from the app's screen space.
    public let frame: CGRect

    /// The non-trait text (label, then value).
    public var primaryText: String {
        let parts = [label, value].compactMap { $0 }
        return parts.isEmpty ? "(no label)" : parts.joined(separator: ", ")
    }
}

public struct RemoteAXSnapshot: Codable, Sendable {
    public var appName: String
    public var screenSize: [Double]
    public var roots: [RemoteAXNode]

    /// The iOS logical screen size in points.
    public var iosScreenSize: CGSize {
        CGSize(width: screenSize.first ?? 0, height: screenSize.last ?? 0)
    }

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

    /// The accessible elements, depth-first, as a flat list.
    public func flatElements() -> [AXElement] {
        var result: [AXElement] = []
        for root in roots { root.collect(into: &result) }
        return result
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

    /// Appends this node (if it's an accessible element) and its descendants.
    func collect(into result: inout [AXElement]) {
        if isElement, frame.count == 4 {
            result.append(AXElement(
                label: label,
                value: value,
                traits: traits,
                frame: CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
            ))
        }
        for child in children { child.collect(into: &result) }
    }

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
