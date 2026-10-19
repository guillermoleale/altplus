import AppKit

/// Una ventana estándar de una app en ejecución, con lo que se necesita para listarla y activarla.
struct WindowInfo {
    let key: AXElementKey
    let windowID: CGWindowID?
    let pid: pid_t
    let app: NSRunningApplication
    let appName: String
    let bundleID: String?
    let title: String
    let isMinimized: Bool
    let isHiddenApp: Bool
    /// `true` si la ventana está en un escritorio visible ahora mismo (en cualquier monitor).
    let isOnScreen: Bool
    let frame: CGRect
    /// Posición en el orden de apilamiento de CGWindowList (0 = adelante de todo). `Int.max` si no se encontró.
    let zOrder: Int
    /// `true` si salió del registro de ventanas conocidas y no de la lista actual de Accesibilidad.
    let isRemembered: Bool

    var element: AXUIElement { key.element }

    /// Ni visible, ni minimizada, ni de una app oculta: está en otro escritorio.
    var isOnOtherDesktop: Bool { !isOnScreen && !isMinimized && !isHiddenApp }

    var displayTitle: String { title.isEmpty ? appName : title }
}
