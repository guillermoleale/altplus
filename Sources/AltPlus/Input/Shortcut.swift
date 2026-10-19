import AppKit
import Carbon.HIToolbox

/// Un atajo global: una tecla más un conjunto de modificadores.
struct Shortcut: Codable, Equatable {
    struct Modifiers: OptionSet, Codable, Hashable {
        let rawValue: UInt8
        init(rawValue: UInt8) { self.rawValue = rawValue }

        static let shift   = Modifiers(rawValue: 1 << 0)
        static let control = Modifiers(rawValue: 1 << 1)
        static let option  = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        init(cgFlags: CGEventFlags) {
            var m: Modifiers = []
            if cgFlags.contains(.maskShift) { m.insert(.shift) }
            if cgFlags.contains(.maskControl) { m.insert(.control) }
            if cgFlags.contains(.maskAlternate) { m.insert(.option) }
            if cgFlags.contains(.maskCommand) { m.insert(.command) }
            self = m
        }

        init(nsFlags: NSEvent.ModifierFlags) {
            var m: Modifiers = []
            if nsFlags.contains(.shift) { m.insert(.shift) }
            if nsFlags.contains(.control) { m.insert(.control) }
            if nsFlags.contains(.option) { m.insert(.option) }
            if nsFlags.contains(.command) { m.insert(.command) }
            self = m
        }

        /// Símbolos en el orden que usa macOS en los menús.
        var symbols: String {
            var s = ""
            if contains(.control) { s += "⌃" }
            if contains(.option) { s += "⌥" }
            if contains(.shift) { s += "⇧" }
            if contains(.command) { s += "⌘" }
            return s
        }
    }

    var keyCode: UInt16
    var modifiers: Modifiers

    static let defaultSameDesktop = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.option])
    static let defaultAllDesktops = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: [.option, .control])

    /// Modificadores que hay que mantener apretados mientras el panel está abierto.
    /// Shift no cuenta: se usa para retroceder.
    var holdModifiers: Modifiers { modifiers.subtracting(.shift) }

    /// Un atajo necesita al menos un modificador distinto de Shift.
    var isValid: Bool { !holdModifiers.isEmpty }

    var displayString: String { modifiers.symbols + KeyNames.name(for: keyCode) }

    /// Compara con lo que se apretó. `reverse` indica que se agregó Shift para ir hacia atrás.
    func match(keyCode: UInt16, modifiers pressed: Modifiers) -> (matches: Bool, reverse: Bool) {
        guard keyCode == self.keyCode else { return (false, false) }
        if pressed == modifiers { return (true, false) }
        if !modifiers.contains(.shift), pressed == modifiers.union(.shift) { return (true, true) }
        return (false, false)
    }
}
