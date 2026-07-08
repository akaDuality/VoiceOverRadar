import Foundation

/// Decodes the JSON served by the in-app `AXExporter` (running inside an iOS
/// app in the Simulator or on-device) and maps it into the same `Node` model
/// the inspector renders for macOS AX trees.
///
/// The shapes here mirror `AXExporter`'s `AXSnapshot`/`AXNode`. They're
/// duplicated rather than shared because that package is iOS-only (UIKit).

/// A single accessible element, flattened out of the tree for a simple list.
public struct AXElement: Identifiable, Sendable, Equatable {
    /// Exporter-assigned, stable per process — also used to target actions.
    public let id: String
    public let label: String?
    public let value: String?
    public let traits: [String]
    /// Frame in iOS points (top-left origin), from the app's screen space.
    public let frame: CGRect
    public let customActions: [String]
    public let customContent: [String]

    public var isAdjustable: Bool { traits.contains("adjustable") }

    /// The non-trait text (label, then value).
    public var primaryText: String {
        let parts = [label, value].compactMap { $0 }
        return parts.isEmpty ? "(no label)" : parts.joined(separator: ", ")
    }
}

/// A row in the nested list: a container or an element, with an indent depth.
public struct AXRow: Identifiable, Sendable, Equatable {
    public let id: String
    public let depth: Int
    public let isContainer: Bool
    public let containerType: String?
    public let label: String?
    public let value: String?
    public let traits: [String]
    public let frame: CGRect
    public let customActions: [String]
    public let customContent: [String]

    public var isAdjustable: Bool { traits.contains("adjustable") }

    public var primaryText: String {
        let parts = [label, value].compactMap { $0 }
        if parts.isEmpty { return isContainer ? (containerType.map { "(\($0))" } ?? "(group)") : "(no label)" }
        return parts.joined(separator: ", ")
    }
}

public struct RemoteAXSnapshot: Codable, Sendable {
    public var appName: String
    public var screenSize: [Double]
    public var roots: [RemoteAXNode]
    public var modalPresented: Bool?
    public var modalLabel: String?

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

    /// The accessible elements as a flat list, in VoiceOver reading order
    /// (top-to-bottom, then left-to-right). Sorting globally — rather than only
    /// within each container — keeps deeply nested elements from preceding a
    /// later, shallower sibling. Used for the Simulator overlay.
    public func flatElements() -> [AXElement] {
        var result: [AXElement] = []
        for root in roots { root.collect(into: &result) }
        return result.sorted { a, b in
            if abs(a.frame.minY - b.frame.minY) > 10 { return a.frame.minY < b.frame.minY }
            return a.frame.minX < b.frame.minX
        }
    }

    /// The tree as a nested list (containers with their cells inset), in the
    /// exporter's per-container reading order — used for the list view.
    public func rows() -> [AXRow] {
        var result: [AXRow] = []
        for root in roots { root.appendRows(into: &result, depth: 0) }
        return result
    }
}

public struct RemoteAXNode: Codable, Sendable {
    public var id: String
    public var label: String?
    public var value: String?
    public var hint: String?
    public var identifier: String?
    public var traits: [String]
    public var isElement: Bool
    public var isContainer: Bool?
    public var containerType: String?
    public var frame: [Double]
    public var voiceOver: String
    public var customActions: [String]
    public var customContent: [String]
    public var children: [RemoteAXNode]

    private var frameRect: CGRect {
        frame.count == 4 ? CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3]) : .zero
    }

    /// Appends nested rows: containers and elements, with an indent depth.
    func appendRows(into rows: inout [AXRow], depth: Int) {
        // Only surface named groups; unnamed groupings pass their cells through.
        let container = (isContainer ?? false) && label != nil
        let show = isElement || container
        if show {
            rows.append(AXRow(
                id: id, depth: depth, isContainer: container, containerType: containerType,
                label: label, value: value, traits: traits, frame: frameRect,
                customActions: customActions, customContent: customContent
            ))
        }
        let childDepth = show ? depth + 1 : depth
        // Sort siblings into reading order by their TOPMOST element (not their
        // bounding box, which is ambiguous for containers that span the screen),
        // so top-of-screen navigation isn't pushed below content by an authored
        // accessibilityElements order.
        let ordered = children.sorted { a, b in
            let ka = a.firstLeafKey(), kb = b.firstLeafKey()
            if abs(ka.y - kb.y) > 10 { return ka.y < kb.y }
            return ka.x < kb.x
        }
        for child in ordered { child.appendRows(into: &rows, depth: childDepth) }
    }

    /// The (y, x) of the topmost-leftmost element in this subtree — used to
    /// order containers by where their content actually begins.
    func firstLeafKey() -> (y: Double, x: Double) {
        var keys: [(Double, Double)] = []
        collectLeafKeys(into: &keys)
        guard let best = keys.min(by: { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }) else {
            return (frame.count > 1 ? frame[1] : .greatestFiniteMagnitude, frame.first ?? 0)
        }
        return best
    }

    private func collectLeafKeys(into keys: inout [(Double, Double)]) {
        if isElement, frame.count == 4 { keys.append((frame[1], frame[0])) }
        for child in children { child.collectLeafKeys(into: &keys) }
    }

    /// Appends this node (if it's an accessible element) and its descendants.
    func collect(into result: inout [AXElement]) {
        if isElement, frame.count == 4 {
            result.append(AXElement(
                id: id,
                label: label,
                value: value,
                traits: traits,
                frame: CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3]),
                customActions: customActions,
                customContent: customContent
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

    /// Triggers an action on an element and returns the resulting snapshot.
    /// `type` is "increment", "decrement", or "custom" (with `name`).
    public static func sendAction(
        host: String, port: Int, id: String? = nil, type: String, name: String? = nil
    ) async throws -> RemoteAXSnapshot {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/action"
        var items = [URLQueryItem(name: "type", value: type)]
        if let id { items.append(URLQueryItem(name: "id", value: id)) }
        if let name { items.append(URLQueryItem(name: "name", value: name)) }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(RemoteAXSnapshot.self, from: data)
    }
}
