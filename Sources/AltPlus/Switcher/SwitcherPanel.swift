import AppKit
import SwiftUI

/// Panel flotante que no activa a AltPlus: la app de adelante sigue siendo la activa
/// hasta que el usuario confirma. Se puede mostrar en cualquier escritorio y sobre apps a pantalla completa.
final class SwitcherPanel: NSPanel {
    private let hosting: FirstMouseHostingView<SwitcherView>

    init(model: SwitcherModel) {
        hosting = FirstMouseHostingView(rootView: SwitcherView(model: model))
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        isMovableByWindowBackground = false
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present(size: CGSize, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let origin = NSPoint(x: (visible.midX - size.width / 2).rounded(),
                             y: (visible.midY - size.height / 2).rounded())
        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFrontRegardless()
        invalidateShadow()
    }

    func dismiss() {
        orderOut(nil)
    }
}

/// Acepta el primer clic aunque la app no esté activa, para poder elegir con el mouse.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
