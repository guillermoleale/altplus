import Foundation

/// Textos en español e inglés sin archivos .strings: `tr("Hola", "Hello")`.
/// Se elige el idioma según la preferencia del sistema; cualquier idioma que no sea español usa inglés.
enum L10n {
    static let usesSpanish: Bool = {
        guard let lang = Locale.preferredLanguages.first else { return true }
        return lang.lowercased().hasPrefix("es")
    }()
}

@inline(__always)
func tr(_ es: String, _ en: String) -> String { L10n.usesSpanish ? es : en }
