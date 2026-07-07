import UIKit

/// Walks the running app's `UIAccessibility` tree and turns it into `AXNode`s.
///
/// Mirrors how VoiceOver discovers elements: it prefers an object's
/// `accessibilityElements` when present, otherwise descends the view hierarchy,
/// capturing anything that is an accessibility element or carries a label.
@MainActor
public enum AccessibilityWalker {

    public static func snapshot() -> AXSnapshot {
        let windows = activeWindows()
        let roots = windows.compactMap { buildNode($0, depth: 0) }
        let screen = UIScreen.main.bounds.size
        return AXSnapshot(
            appName: appName(),
            screenSize: [Double(screen.width), Double(screen.height)],
            roots: roots
        )
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
        return AXNode(
            label: label,
            value: value,
            hint: hint,
            identifier: identifier,
            traits: traits,
            isElement: isElement,
            frame: [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)],
            voiceOver: compose(label: label, value: value, traits: traits, hint: hint),
            children: children
        )
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
