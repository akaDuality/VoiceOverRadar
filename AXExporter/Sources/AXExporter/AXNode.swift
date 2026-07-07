import Foundation

/// A serialized accessibility element from an iOS app's `UIAccessibility` tree —
/// the same information VoiceOver consumes to describe the screen.
public struct AXNode: Codable, Sendable, Equatable {
    /// Stable-per-process ref used to target actions back at this element.
    public var id: String
    public var label: String?
    public var value: String?
    public var hint: String?
    public var identifier: String?
    public var traits: [String]
    public var isElement: Bool
    /// [x, y, width, height] in screen coordinates.
    public var frame: [Double]
    /// A VoiceOver-style composed phrase for convenience.
    public var voiceOver: String
    /// Names of `accessibilityCustomActions`.
    public var customActions: [String]
    /// `accessibilityCustomContent` entries, formatted "label: value".
    public var customContent: [String]
    public var children: [AXNode]
}

/// The full payload served to DeviceHub.
public struct AXSnapshot: Codable, Sendable, Equatable {
    public var appName: String
    public var screenSize: [Double]   // [width, height] in points
    public var roots: [AXNode]
    /// True when a modal (popover/sheet/alert) is presented; `roots` is then
    /// scoped to that modal, mirroring what VoiceOver reads.
    public var modalPresented: Bool
    public var modalLabel: String?
}
