import UIKit

/// Walks the running app's `UIAccessibility` tree and turns it into `AXNode`s.
///
/// Mirrors how VoiceOver discovers elements: it prefers an object's
/// `accessibilityElements` when present, otherwise descends the view hierarchy,
/// capturing anything that is an accessibility element or carries a label.
private final class WeakRef {
    weak var object: NSObject?
    init(_ object: NSObject) { self.object = object }
}

@MainActor
public enum AccessibilityWalker {

    /// Maps element ids (from the last snapshot) to live objects, so DeviceHub
    /// can trigger actions (increment/decrement/custom action) on them.
    private static var registry: [String: WeakRef] = [:]

    public static func snapshot() -> AXSnapshot {
        registry.removeAll(keepingCapacity: true)
        let windows = activeWindows()
        let screen = UIScreen.main.bounds.size

        // A presented popover/sheet/alert marks its container modal; VoiceOver
        // then reads only that subtree, so we scope the export to it.
        let modal = windows.lazy.compactMap { findModal(in: $0) }.first
        let roots: [AXNode]
        if let modal, let node = buildNode(modal, depth: 0) {
            roots = [node]
        } else {
            roots = windows.compactMap { buildNode($0, depth: 0) }
        }

        return AXSnapshot(
            appName: appName(),
            screenSize: [Double(screen.width), Double(screen.height)],
            roots: roots,
            modalPresented: modal != nil,
            modalLabel: modal.flatMap { nonEmpty($0.accessibilityLabel) }
        )
    }

    /// Finds the first view marked `accessibilityViewIsModal` (a presented
    /// popover/sheet/alert), searching accessibility elements then subviews.
    private static func findModal(in object: NSObject, depth: Int = 0) -> NSObject? {
        guard depth < 200 else { return nil }
        if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return nil }
        if object.accessibilityViewIsModal { return object }

        var children: [NSObject] = []
        if let elements = object.accessibilityElements as? [NSObject] {
            children = elements
        } else if let view = object as? UIView {
            children = view.subviews
        }
        for child in children {
            if let modal = findModal(in: child, depth: depth + 1) { return modal }
        }
        return nil
    }

    // MARK: Traversal

    private static func buildNode(_ object: NSObject, depth: Int) -> AXNode? {
        guard depth < 200 else { return nil }

        if let view = object as? UIView {
            if view.isHidden || view.alpha < 0.01 || view.accessibilityElementsHidden {
                return nil
            }
        }

        let isElement = object.isAccessibilityElement
        let label = nonEmpty(object.accessibilityLabel)
        let value = nonEmpty(object.accessibilityValue)
        let hint = nonEmpty(object.accessibilityHint)
        let identifier = nonEmpty((object as? UIAccessibilityIdentification)?.accessibilityIdentifier)
        let traits = decodeTraits(object.accessibilityTraits)

        // Children: explicit accessibility elements win; otherwise subviews.
        // Authored `accessibilityElements` already carry VoiceOver's read order;
        // subview order is z-order, so we sort those into reading order below.
        var childObjects: [NSObject] = []
        var fromExplicitOrder = false
        if let elements = object.accessibilityElements as? [NSObject], !elements.isEmpty {
            childObjects = elements
            fromExplicitOrder = true
        } else if !isElement, let view = object as? UIView {
            childObjects = view.subviews
        }
        var children = childObjects.compactMap { buildNode($0, depth: depth + 1) }
        if !fromExplicitOrder {
            children.sort(by: readingOrderBefore)
        }

        let meaningful = isElement || label != nil || value != nil || !traits.isEmpty
        if !meaningful {
            // A structural container: drop it, but keep its content. Collapse a
            // single-child chain to reduce noise.
            if children.isEmpty { return nil }
            if children.count == 1 { return children[0] }
        }

        let frame = object.accessibilityFrame
        let id = "\(UInt(bitPattern: ObjectIdentifier(object).hashValue))"
        registry[id] = WeakRef(object)

        return AXNode(
            id: id,
            label: label,
            value: value,
            hint: hint,
            identifier: identifier,
            traits: traits,
            isElement: isElement,
            frame: [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)],
            voiceOver: compose(label: label, value: value, traits: traits, hint: hint),
            customActions: (object.accessibilityCustomActions ?? []).map(\.name),
            customContent: customContent(of: object),
            children: children
        )
    }

    private static func customContent(of object: NSObject) -> [String] {
        guard let provider = object as? AXCustomContentProvider else { return [] }
        return provider.accessibilityCustomContent.map { entry in
            let value = entry.value
            return value.isEmpty ? entry.label : "\(entry.label): \(value)"
        }
    }

    // MARK: Actions (triggered by DeviceHub)

    /// Increment/decrement an adjustable element by id. Returns success.
    @discardableResult
    static func adjust(id: String, increment: Bool) -> Bool {
        guard let object = registry[id]?.object else { return false }
        if increment { object.accessibilityIncrement() } else { object.accessibilityDecrement() }
        return true
    }

    /// Invoke a named custom action on an element by id. Returns success.
    @discardableResult
    static func performCustomAction(id: String, name: String) -> Bool {
        guard let object = registry[id]?.object,
              let action = (object.accessibilityCustomActions ?? []).first(where: { $0.name == name })
        else { return false }
        if let handler = action.actionHandler { return handler(action) }
        if let target = action.target as? NSObject, target.responds(to: action.selector) {
            _ = target.perform(action.selector, with: action)
            return true
        }
        return false
    }

    // MARK: Helpers

    private static func activeWindows() -> [UIWindow] {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden && $0.windowLevel == .normal }
        // Key window first so the visible screen leads the snapshot.
        return windows.sorted { ($0.isKeyWindow ? 0 : 1) < ($1.isKeyWindow ? 0 : 1) }
    }

    private static func appName() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "App"
    }

    /// VoiceOver-style reading order: top-to-bottom, then left-to-right, with a
    /// tolerance so items on the same visual row aren't split by a few points.
    private static func readingOrderBefore(_ a: AXNode, _ b: AXNode) -> Bool {
        let ay = a.frame.count > 1 ? a.frame[1] : 0
        let by = b.frame.count > 1 ? b.frame[1] : 0
        if abs(ay - by) > 10 { return ay < by }
        let ax = a.frame.first ?? 0
        let bx = b.frame.first ?? 0
        return ax < bx
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }

    private static func compose(label: String?, value: String?, traits: [String], hint: String?) -> String {
        let roleWord = traits.first { ["button", "link", "header", "image", "adjustable"].contains($0) }
        let parts = [label, value, roleWord, hint].compactMap { $0 }
        return parts.isEmpty ? "(no description)" : parts.joined(separator: ", ")
    }

    private static func decodeTraits(_ traits: UIAccessibilityTraits) -> [String] {
        let table: [(UIAccessibilityTraits, String)] = [
            (.button, "button"), (.link, "link"), (.header, "header"),
            (.searchField, "searchField"), (.image, "image"), (.selected, "selected"),
            (.staticText, "staticText"), (.summaryElement, "summaryElement"),
            (.notEnabled, "notEnabled"), (.updatesFrequently, "updatesFrequently"),
            (.startsMediaSession, "startsMediaSession"), (.adjustable, "adjustable"),
            (.allowsDirectInteraction, "allowsDirectInteraction"),
            (.causesPageTurn, "causesPageTurn"), (.keyboardKey, "keyboardKey"),
            (.playsSound, "playsSound"), (.tabBar, "tabBar"),
        ]
        return table.filter { traits.contains($0.0) }.map(\.1)
    }
}
