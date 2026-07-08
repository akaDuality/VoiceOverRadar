import AppKit

/// Finds the iOS Simulator's on-screen device rect **without** Accessibility
/// permission, using the public window list (`CGWindowListCopyWindowInfo`).
///
/// Window bounds and owner name are available with no special permission (only
/// window *titles* and *contents* would need Screen Recording). The device
/// screen fills the Simulator window's width and sits at its bottom (below the
/// title bar), so its height follows the iOS aspect ratio.
public enum SimulatorLocator {

    public static func deviceRect(iosSize: CGSize) -> CGRect? {
        guard iosSize.width > 0, iosSize.height > 0 else { return nil }
        guard let windowRect = simulatorWindowRect() else { return nil }

        let width = windowRect.width
        let height = width * iosSize.height / iosSize.width
        return CGRect(
            x: windowRect.minX,
            y: windowRect.maxY - height,   // device sits at the window's bottom
            width: width,
            height: height
        )
    }

    /// Bounds (global, top-left origin) of the largest on-screen Simulator window.
    private static func simulatorWindowRect() -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        var best: CGRect?
        var bestArea: CGFloat = 0
        for info in list {
            guard info[kCGWindowOwnerName as String] as? String == "Simulator" else { continue }
            guard (info[kCGWindowLayer as String] as? Int) ?? 0 == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary),
                  rect.width > 100, rect.height > 100 else { continue }
            let area = rect.width * rect.height
            if area > bestArea { bestArea = area; best = rect }
        }
        return best
    }
}
