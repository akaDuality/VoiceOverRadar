import AppKit
import AXCore

/// Sends a synthetic click to the Simulator at an element's location. The
/// Simulator turns a Mac mouse click into an iOS touch, so clicking the mapped
/// on-screen point taps the corresponding control inside the app.
enum SimulatorInput {

    /// Taps the center of `iosFrame`, mapped through the Simulator device rect.
    static func tap(iosFrame: CGRect, iosSize: CGSize, contentRect: CGRect?) {
        guard let contentRect, iosSize.width > 0, iosSize.height > 0 else { return }

        let scaleX = contentRect.width / iosSize.width
        let scaleY = contentRect.height / iosSize.height
        // CGEvent uses global display coordinates (top-left origin) — same space
        // as the AX-derived device rect, so no flip is needed here.
        let point = CGPoint(
            x: contentRect.origin.x + iosFrame.midX * scaleX,
            y: contentRect.origin.y + iosFrame.midY * scaleY
        )

        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                         mouseCursorPosition: point, mouseButton: .left)

        if let pid = HostProcesses.simulatorHosts().first?.id {
            // Deliver straight to the Simulator process so the real cursor
            // never moves.
            down?.postToPid(pid)
            up?.postToPid(pid)
        } else {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
