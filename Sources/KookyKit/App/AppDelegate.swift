import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        KookyFonts.registerOnce()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "kooky"
        window.titlebarAppearsTransparent = true
        // Force dark chrome regardless of system appearance — the terminal
        // surface and our sidebar are always dark, and SwiftUI's .primary /
        // .secondary need a dark context to resolve to readable colors.
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: ContentView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        KookyShellIntegration.cleanup()
    }
}
