import AppKit
import Carbon.HIToolbox
import SwiftUI

extension Notification.Name {
    /// `userInfo["recording"]` es `true` mientras se graba un atajo; el event tap se suspende en ese lapso.
    static let shortcutRecordingDidChange = Notification.Name("org.altplus.shortcutRecordingDidChange")
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut

    func makeCoordinator() -> Coordinator { Coordinator(binding: $shortcut) }

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.shortcut = shortcut
        view.onChange = { [coordinator = context.coordinator] newValue in
            coordinator.binding.wrappedValue = newValue
        }
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        context.coordinator.binding = $shortcut
        if view.shortcut != shortcut { view.shortcut = shortcut }
    }

    final class Coordinator {
        var binding: Binding<Shortcut>
        init(binding: Binding<Shortcut>) { self.binding = binding }
    }
}

/// Botón que, al hacer clic, captura la siguiente combinación de teclas.
final class ShortcutRecorderView: NSView {
    var shortcut: Shortcut = .defaultSameDesktop { didSet { needsDisplay = true } }
    var onChange: ((Shortcut) -> Void)?

    private var isRecording = false {
        didSet {
            needsDisplay = true
            NotificationCenter.default.post(name: .shortcutRecordingDidChange, object: self,
                                            userInfo: ["recording": isRecording])
        }
    }
    private var liveModifiers: Shortcut.Modifiers = []
    private var resignKeyObserver: NSObjectProtocol?

    deinit {
        if let resignKeyObserver { NotificationCenter.default.removeObserver(resignKeyObserver) }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 26) }

    /// Si la ventana se cierra o deja de ser la activa mientras se graba, se corta la grabación:
    /// si no, el event tap queda suspendido y los atajos globales dejan de funcionar.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        stopRecording()
        if let resignKeyObserver { NotificationCenter.default.removeObserver(resignKeyObserver) }
        resignKeyObserver = nil
        guard let newWindow else { return }
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: newWindow, queue: .main
        ) { [weak self] _ in self?.stopRecording() }
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            window?.makeFirstResponder(self)
            startRecording()
        }
    }

    override func becomeFirstResponder() -> Bool { true }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        handle(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return false }
        handle(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { super.flagsChanged(with: event); return }
        liveModifiers = Shortcut.Modifiers(nsFlags: event.modifierFlags)
        needsDisplay = true
    }

    private func startRecording() {
        liveModifiers = []
        isRecording = true
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        let modifiers = Shortcut.Modifiers(nsFlags: event.modifierFlags)
        if Int(event.keyCode) == kVK_Escape && modifiers.isEmpty {
            stopRecording()
            return
        }
        guard !KeyNames.isModifierKey(event.keyCode) else { return }
        let candidate = Shortcut(keyCode: event.keyCode, modifiers: modifiers)
        guard candidate.isValid else {
            NSSound.beep()
            return
        }
        shortcut = candidate
        onChange?(candidate)
        stopRecording()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text: String
        if isRecording {
            text = liveModifiers.isEmpty ? tr("Pulsa el atajo…", "Press shortcut…") : liveModifiers.symbols + "…"
        } else {
            text = shortcut.displayString
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}
