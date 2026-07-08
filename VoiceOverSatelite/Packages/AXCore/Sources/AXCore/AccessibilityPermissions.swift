import AppKit
import ApplicationServices

/// Gatekeeper for the macOS Accessibility (AX) permission.
///
/// Reading another application's on-screen elements requires the process to be
/// listed under **System Settings → Privacy & Security → Accessibility**. This
/// is the exact same trust VoiceOver relies on.
public enum AccessibilityPermissions {

    /// Whether this process is currently trusted to use the Accessibility API.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility access if not already granted.
    ///
    /// The first call surfaces the system dialog that deep-links into Settings.
    /// - Returns: `true` if already trusted, `false` if the prompt was shown.
    @discardableResult
    public static func requestIfNeeded() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    /// Opens the Accessibility pane in System Settings.
    public static func openSettings() {
        let path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: path) {
            NSWorkspace.shared.open(url)
        }
    }
}
