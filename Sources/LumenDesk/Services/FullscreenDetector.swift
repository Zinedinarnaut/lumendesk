import AppKit
import CoreGraphics
import Foundation

struct FullscreenDetector {
    func hasLikelyFullscreenForegroundWindow(excludingOwners excludedOwners: Set<String>) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
            !raw.isEmpty
        else {
            return false
        }

        let screens = NSScreen.screens.map(\.frame)
        guard !screens.isEmpty else { return false }

        for info in raw {
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 { continue }

            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            if excludedOwners.contains(owner) { continue }

            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
            if alpha <= 0.01 { continue }

            guard let boundsMap = info[kCGWindowBounds as String] as? [String: Any] else {
                continue
            }

            guard
                let bounds = CGRect(dictionaryRepresentation: boundsMap as CFDictionary),
                bounds.width > 0,
                bounds.height > 0
            else {
                continue
            }

            if coversAnyScreen(windowBounds: bounds, screens: screens) {
                return true
            }
        }

        return false
    }

    private func coversAnyScreen(windowBounds: CGRect, screens: [CGRect]) -> Bool {
        for screen in screens {
            let intersection = windowBounds.intersection(screen)
            if intersection.isNull { continue }
            let coverage = (intersection.width * intersection.height) / max(1, (screen.width * screen.height))
            if coverage >= 0.96 {
                return true
            }
        }
        return false
    }
}
