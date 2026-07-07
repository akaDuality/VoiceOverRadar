import AppKit

/// A borderless, click-through window that draws a red outline over a rect on
/// the Simulator's device screen. Driven by hovering elements in the list.
@MainActor
final class SimulatorOverlay: ObservableObject {

    private var window: NSWindow?

    /// Outlines an element given its iOS-point frame, the iOS screen size, and
    /// the Simulator's on-screen device rect (global, top-left origin).
    func highlight(iosFrame: CGRect, iosSize: CGSize, contentRect: CGRect?) {
        guard let contentRect, iosSize.width > 0, iosSize.height > 0 else { hide(); return }

        let scaleX = contentRect.width / iosSize.width
        let scaleY = contentRect.height / iosSize.height

        // Map iOS point-space (top-left) into the device rect (global top-left).
        let topLeftX = contentRect.origin.x + iosFrame.origin.x * scaleX
        let topLeftY = contentRect.origin.y + iosFrame.origin.y * scaleY
        let width = iosFrame.width * scaleX
        let height = iosFrame.height * scaleY

        // AX is top-left origin from the primary screen; Cocoa is bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaY = primaryHeight - (topLeftY + height)
        let rect = CGRect(x: topLeftX, y: cocoaY, width: width, height: height)

        show(rect)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func show(_ rect: CGRect) {
        let window = self.window ?? makeWindow()
        window.setFrame(rect, display: true)
        window.orderFront(nil)
        self.window = window
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = OutlineView()
        return window
    }
}

private final class OutlineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.withAlphaComponent(0.12).setFill()
        bounds.fill()
        NSColor.systemRed.setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        path.lineWidth = 2
        path.stroke()
    }
}
