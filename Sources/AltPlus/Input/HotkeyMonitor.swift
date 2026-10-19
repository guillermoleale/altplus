import AppKit
import Carbon.HIToolbox

enum SwitcherMode: String, Codable, CaseIterable {
    case sameDesktop
    case allDesktops
}

protocol HotkeyMonitorDelegate: AnyObject {
    func hotkeyTriggered(mode: SwitcherMode, reverse: Bool)
    func switcherStep(reverse: Bool)
    func switcherCancel()
    func switcherCommit()
    func switcherAction(_ action: WindowAction)
}

/// Escucha el teclado con un event tap de CoreGraphics y traduce los eventos a acciones del conmutador.
///
/// Requiere el permiso de Accesibilidad. El tap se agrega al run loop principal, así que
/// `handle` corre en el hilo principal. Tiene que volver rápido: si la callback tarda,
/// macOS desactiva el tap y hay que volver a habilitarlo.
final class HotkeyMonitor {
    weak var delegate: HotkeyMonitorDelegate?
    var shortcuts: [SwitcherMode: Shortcut] = [:]

    /// Mientras se graba un atajo en Preferencias, el tap deja pasar todo.
    var isSuspended = false

    private(set) var isRunning = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// Atajo que abrió la sesión en curso. `nil` cuando no hay sesión.
    private var activeShortcut: Shortcut?
    /// Modificadores que el usuario mantiene apretados mientras hay una sesión abierta.
    private var activeHold: Shortcut.Modifiers? { activeShortcut?.holdModifiers }
    /// Teclas cuyo keyDown nos tragamos; también nos tragamos su keyUp para no dejar eventos sueltos.
    private var swallowedKeys = Set<UInt16>()

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        let mask: CGEventMask =
            (CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)) |
            (CGEventMask(1) << CGEventMask(CGEventType.keyUp.rawValue)) |
            (CGEventMask(1) << CGEventMask(CGEventType.flagsChanged.rawValue))
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.input.error("No se pudo crear el event tap. ¿Falta el permiso de Accesibilidad?")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isRunning = true
        Log.input.info("Event tap activo")
        return true
    }

    func stop() {
        guard isRunning else { return }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        activeShortcut = nil
        swallowedKeys.removeAll()
        isRunning = false
    }

    /// El controlador avisa cuando la sesión termina (commit o cancelación) para volver a escuchar atajos.
    func endSession() {
        activeShortcut = nil
    }

    fileprivate func reenable() {
        guard let tap else { return }
        Log.input.warning("macOS desactivó el event tap; se vuelve a habilitar")
        CGEvent.tapEnable(tap: tap, enable: true)
        // Mientras el tap estuvo desactivado se pudo perder el evento de soltar los modificadores.
        let current = Shortcut.Modifiers(cgFlags: CGEventSource.flagsState(.combinedSessionState))
        if let hold = activeHold, current.isDisjoint(with: hold) {
            delegate?.switcherCommit()
        }
    }

    /// Devuelve `true` si hay que tragarse el evento (no pasarlo a la app de adelante).
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if isSuspended { return false }
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let pressed = Shortcut.Modifiers(cgFlags: event.flags)

        switch type {
        case .keyDown:
            if let hold = activeHold {
                swallowedKeys.insert(keyCode)
                if pressed.isDisjoint(with: hold) {
                    // Se perdió el evento de soltar los modificadores (tap desactivado, entrada segura):
                    // se confirma en vez de tomar la tecla como una acción (Q saldría de una app).
                    delegate?.switcherCommit()
                } else {
                    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                    handleKeyWhileActive(keyCode: keyCode, pressed: pressed, isRepeat: isRepeat)
                }
                return true
            }
            for mode in SwitcherMode.allCases {
                guard let shortcut = shortcuts[mode] else { continue }
                let result = shortcut.match(keyCode: keyCode, modifiers: pressed)
                if result.matches {
                    activeShortcut = shortcut
                    swallowedKeys.insert(keyCode)
                    delegate?.hotkeyTriggered(mode: mode, reverse: result.reverse)
                    return true
                }
            }
            return false

        case .keyUp:
            return swallowedKeys.remove(keyCode) != nil

        case .flagsChanged:
            if let hold = activeHold, pressed.isDisjoint(with: hold) {
                // Se soltaron todos los modificadores del atajo: se confirma la selección.
                delegate?.switcherCommit()
            }
            return false

        default:
            return false
        }
    }

    private func handleKeyWhileActive(keyCode: UInt16, pressed: Shortcut.Modifiers, isRepeat: Bool) {
        // La tecla del propio atajo avanza (y retrocede con Shift), sea Tab, "<" o cualquier otra.
        if let active = activeShortcut, keyCode == active.keyCode {
            let reverse = pressed.contains(.shift) && !active.modifiers.contains(.shift)
            delegate?.switcherStep(reverse: reverse)
            return
        }
        // Mantener apretada una tecla repite solo la navegación: repetir W o Q cerraría o saldría
        // de las ventanas siguientes a medida que la lista se recarga.
        let isNavigation = [kVK_Tab, kVK_RightArrow, kVK_DownArrow, kVK_LeftArrow, kVK_UpArrow].contains(Int(keyCode))
        if isRepeat && !isNavigation { return }
        switch Int(keyCode) {
        case kVK_Tab:
            delegate?.switcherStep(reverse: pressed.contains(.shift))
        case kVK_RightArrow, kVK_DownArrow:
            delegate?.switcherStep(reverse: false)
        case kVK_LeftArrow, kVK_UpArrow:
            delegate?.switcherStep(reverse: true)
        case kVK_Escape:
            delegate?.switcherCancel()
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space:
            delegate?.switcherCommit()
        case kVK_ANSI_W:
            delegate?.switcherAction(.close)
        case kVK_ANSI_M:
            delegate?.switcherAction(.minimize)
        case kVK_ANSI_Q:
            delegate?.switcherAction(.quit)
        case kVK_ANSI_H:
            delegate?.switcherAction(.hide)
        default:
            // Cualquier otra tecla se ignora pero no llega a la app de adelante.
            break
        }
    }
}

private let hotkeyTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        monitor.reenable()
        return Unmanaged.passUnretained(event)
    }
    return monitor.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
