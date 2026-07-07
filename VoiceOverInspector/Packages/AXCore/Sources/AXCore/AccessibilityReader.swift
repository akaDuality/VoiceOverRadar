import AppKit
import ApplicationServices

/// Reads accessibility attributes from `AXUIElement`s and reconstructs the
/// description VoiceOver would announce.
///
/// Note: macOS exposes no public API for VoiceOver's *actual* spoken string.
/// Instead we read the same underlying attributes VoiceOver reads
/// (label, value, role, hint) and compose a VoiceOver-equivalent phrase.
public enum AccessibilityReader {

    // MARK: Attribute access

    /// Reads a single attribute as a human-readable string, or `nil` if the
    /// attribute is absent or empty.
    public static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        return readableString(from: value)
    }

    static func readableString(from value: CFTypeRef) -> String? {
        let typeID = CFGetTypeID(value)
        if typeID == CFStringGetTypeID() {
            let string = value as! String
            return string.isEmpty ? nil : string
        }
        if typeID == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean)) ? "true" : "false"
        }
        if typeID == CFNumberGetTypeID() {
            return (value as! NSNumber).stringValue
        }
        // AXValue (ranges, points, sizes…) and everything else.
        let described = String(describing: value)
        return described.isEmpty ? nil : described
    }

    /// The direct children of an element, or an empty array.
    public static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    // MARK: Screen anchors

    /// The element currently holding keyboard/VoiceOver focus in the given app.
    public static func focusedElement(ofPID pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        return (focused as! AXUIElement)
    }

    /// The attribute names an element exposes (useful for diagnostics).
    public static func attributeNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    /// Asks a process that lazily vends accessibility (Chromium/Electron, and
    /// apps inside the iOS Simulator) to activate its accessibility tree.
    @discardableResult
    public static func enableManualAccessibility(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        // AXManualAccessibility: Chromium/Electron activation switch.
        // AXEnhancedUserInterface: AppKit flag signalling an assistive tech is
        // active — the iOS Simulator may only bridge its screen when this is set.
        let manual = AXUIElementSetAttributeValue(
            app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let enhanced = AXUIElementSetAttributeValue(
            app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        return manual == .success || enhanced == .success
    }

    /// The windows of an application element.
    public static func windows(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    /// The frontmost/focused window of the given app — the "current screen".
    public static func focusedWindow(ofPID pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return nil }
        return (window as! AXUIElement)
    }

    // MARK: VoiceOver-style description

    /// Composes a VoiceOver-equivalent description for a single element by
    /// combining, in the order VoiceOver announces them:
    /// label → value → role description → hint.
    public static func voiceOverDescription(for element: AXUIElement) -> String {
        let label = string(element, kAXTitleAttribute)
                 ?? string(element, kAXDescriptionAttribute)
        let value = string(element, kAXValueAttribute)
        let roleDescription = string(element, kAXRoleDescriptionAttribute)
        let hint = string(element, kAXHelpAttribute)

        let parts = [label, value, roleDescription, hint].compactMap { $0 }
        return parts.isEmpty ? "(no accessibility description)" : parts.joined(separator: ", ")
    }

    // MARK: Tree snapshot

    /// A lightweight, `Identifiable` snapshot of an element and its subtree,
    /// suitable for rendering in SwiftUI.
    public struct Node: Identifiable, Sendable {
        public let id = UUID()
        public let description: String
        public let role: String?
        public let children: [Node]
    }

    /// Snapshots an entire application's tree from its top-level element.
    /// Use this for iOS Simulator apps, which expose their view hierarchy under
    /// windows rather than through a single focused element.
    public static func snapshotApplication(pid: pid_t, maxDepth: Int = 40) -> Node {
        let app = AXUIElementCreateApplication(pid)
        var roots = children(of: app)
        if roots.isEmpty { roots = windows(of: app) }

        if roots.isEmpty {
            // Nothing vended yet — surface what the app element DOES expose so we
            // can see what's available (attribute names + values).
            let diagnostics = attributeNames(of: app).map { name -> Node in
                Node(description: "\(name) = \(string(app, name) ?? "—")", role: nil, children: [])
            }
            return Node(
                description: "Application (pid \(pid)) — no child elements vended",
                role: "AXApplication",
                children: diagnostics
            )
        }

        let childNodes = maxDepth <= 0
            ? []
            : roots.map { snapshot(of: $0, maxDepth: maxDepth - 1) }
        return Node(description: "Application (pid \(pid))", role: "AXApplication", children: childNodes)
    }

    /// A text dump of an already-built `Node` tree (e.g. from DeviceHub).
    public static func dumpNode(_ node: Node, depth: Int = 0) -> String {
        let indent = String(repeating: "  ", count: depth)
        var out = "\(indent)• \(node.description)\n"
        for child in node.children { out += dumpNode(child, depth: depth + 1) }
        return out
    }

    /// A verbose text dump of a process's AX tree for diagnostics.
    public static func debugDump(pid: pid_t, maxDepth: Int = 60) -> String {
        let app = AXUIElementCreateApplication(pid)
        var out = "PID \(pid)\n"
        out += "app attributes: \(attributeNames(of: app).joined(separator: ", "))\n"
        out += "children=\(children(of: app).count) windows=\(windows(of: app).count)\n\n"

        func walk(_ element: AXUIElement, _ depth: Int) {
            guard depth <= maxDepth else { return }
            let indent = String(repeating: "  ", count: depth)
            let role = string(element, kAXRoleAttribute) ?? "?"
            let subrole = string(element, kAXSubroleAttribute).map { " (\($0))" } ?? ""
            out += "\(indent)[\(role)\(subrole)] \(voiceOverDescription(for: element))\n"
            for child in children(of: element) { walk(child, depth + 1) }
        }

        var roots = children(of: app)
        if roots.isEmpty { roots = windows(of: app) }
        for root in roots { walk(root, 0) }
        return out
    }

    /// Recursively snapshots an element into `Node`s.
    /// - Parameter maxDepth: guards against pathological/deep trees.
    public static func snapshot(of element: AXUIElement, maxDepth: Int = 25) -> Node {
        let role = string(element, kAXRoleAttribute)
        let children: [Node] = maxDepth <= 0
            ? []
            : children(of: element).map { snapshot(of: $0, maxDepth: maxDepth - 1) }
        return Node(
            description: voiceOverDescription(for: element),
            role: role,
            children: children
        )
    }
}
