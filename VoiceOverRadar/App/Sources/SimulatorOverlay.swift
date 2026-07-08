import AppKit
import AXCore

/// A borderless, click-through window covering the Simulator's device screen.
/// It fills every accessible element with a translucent color; the hovered one
/// is filled more strongly and outlined.
@MainActor
final class SimulatorOverlay: ObservableObject {

    private var window: NSWindow?

    private let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue,
        .systemPurple, .systemTeal, .systemPink, .systemIndigo, .systemBrown,
        .systemCyan, .systemMint,
    ]

    /// Fills all elements on the Simulator; the `hoveredFrame` (an element or a
    /// container) is outlined on top.
    func showAll(elements: [AXElement], hoveredFrame: CGRect?, iosSize: CGSize, contentRect: CGRect?) {
        guard let contentRect, iosSize.width > 0, iosSize.height > 0 else { hide(); return }

        let scaleX = contentRect.width / iosSize.width
        let scaleY = contentRect.height / iosSize.height

        // Window covers the device rect; convert AX top-left → Cocoa bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let windowFrame = CGRect(
            x: contentRect.origin.x,
            y: primaryHeight - (contentRect.origin.y + contentRect.height),
            width: contentRect.width,
            height: contentRect.height
        )

        // Map an iOS-point frame to window-local (bottom-left origin) coordinates.
        func local(_ frame: CGRect) -> CGRect {
            let w = frame.width * scaleX
            let h = frame.height * scaleY
            return CGRect(x: frame.minX * scaleX, y: contentRect.height - (frame.minY * scaleY + h), width: w, height: h)
        }

        var boxes = elements.enumerated().map { index, element in
            OverlayBox(rect: local(element.frame), color: palette[index % palette.count], hovered: false)
        }
        if let hoveredFrame {
            boxes.append(OverlayBox(rect: local(hoveredFrame), color: .systemYellow, hovered: true))
        }
        guard !boxes.isEmpty else { hide(); return }
        show(frame: windowFrame, boxes: boxes)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func show(frame: CGRect, boxes: [OverlayBox]) {
        let window = self.window ?? makeWindow()
        window.setFrame(frame, display: true)
        if let view = window.contentView as? OverlayView {
            // Keep the view's bounds in sync so boxes aren't clipped to zero.
            view.frame = CGRect(origin: .zero, size: frame.size)
            view.boxes = boxes
            view.needsDisplay = true
        }
        window.orderFrontRegardless()
        self.window = window
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = OverlayView()
        return window
    }
}

struct OverlayBox {
    let rect: CGRect
    let color: NSColor
    let hovered: Bool
}

private final class OverlayView: NSView {
    var boxes: [OverlayBox] = []

    override func draw(_ dirtyRect: NSRect) {
        // Draw non-hovered first so the hovered box's border sits on top.
        for box in boxes where !box.hovered { fill(box) }
        for box in boxes where box.hovered {
            fill(box)
            box.color.setStroke()
            let path = NSBezierPath(rect: box.rect.insetBy(dx: 1, dy: 1))
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func fill(_ box: OverlayBox) {
        box.color.withAlphaComponent(box.hovered ? 0.45 : 0.16).setFill()
        NSBezierPath(rect: box.rect).fill()
    }
}
