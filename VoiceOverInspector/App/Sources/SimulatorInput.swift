import AppKit

/// Sends a synthetic click to the Simulator at an element's location. The
/// Simulator turns a Mac mouse click into an iOS touch, so clicking the mapped
/// on-screen point taps the corresponding control inside the app.
///
/// The Simulator only accepts clicks from the global event stream, which moves
/// the pointer. We decouple the hardware mouse, warp to the target just for the
/// click, then warp back, so the cursor ends where it started.
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

        let restore = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .combinedSessionState)

        // Detach the visible cursor from the hardware mouse while we click.
        CGAssociateMouseAndMouseCursorPosition(0)
        CGWarpMouseCursorPosition(point)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        if let restore { CGWarpMouseCursorPosition(restore) }
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
