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

    /// Draws all elements mapped onto the Simulator; `hoveredID` is emphasized.
    func showAll(elements: [AXElement], hoveredID: String?, iosSize: CGSize, contentRect: CGRect?) {
        guard let contentRect, iosSize.width > 0, iosSize.height > 0, !elements.isEmpty else {
            hide(); return
        }

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

        // Element rects in window-local (bottom-left origin) coordinates.
        let boxes = elements.enumerated().map { index, element -> OverlayBox in
            let width = element.frame.width * scaleX
            let height = element.frame.height * scaleY
            let x = element.frame.minX * scaleX
            let y = contentRect.height - (element.frame.minY * scaleY + height)
            return OverlayBox(
                rect: CGRect(x: x, y: y, width: width, height: height),
                color: palette[index % palette.count],
                hovered: element.id == hoveredID
            )
        }

        show(frame: windowFrame, boxes: boxes)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func show(frame: CGRect, boxes: [OverlayBox]) {
        let window = self.window ?? makeWindow()
        window.setFrame(frame, display: false)
        (window.contentView as? OverlayView)?.boxes = boxes
        window.contentView?.needsDisplay = true
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
