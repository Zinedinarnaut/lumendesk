import AppKit
import SwiftUI

@MainActor
final class WallpaperWindowController {
    private let window: NSWindow
    let displayID: UInt32

    init<Content: View>(screen: NSScreen, displayID: UInt32, rootView: Content) {
        self.displayID = displayID

        let window = WallpaperWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.level = desktopLevel
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setFrame(screen.frame, display: true)
        window.contentView = NSHostingView(rootView: rootView)

        self.window = window
        show()
    }

    func show() {
        window.orderBack(nil)
    }

    func close() {
        window.orderOut(nil)
    }

    func updateFrame(for screen: NSScreen) {
        window.setFrame(screen.frame, display: true)
    }

    func updateRootView<Content: View>(_ rootView: Content) {
        window.contentView = NSHostingView(rootView: rootView)
    }
}

private final class WallpaperWindow: NSWindow {
    override var canBecomeMain: Bool { false }
    override var canBecomeKey: Bool { false }
}
