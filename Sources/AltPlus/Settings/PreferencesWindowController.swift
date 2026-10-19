import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {
    convenience init(prefs: Preferences) {
        let hosting = NSHostingController(rootView: PreferencesView(prefs: prefs))
        let window = NSWindow(contentViewController: hosting)
        window.title = tr("Preferencias de AltPlus", "AltPlus Preferences")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
