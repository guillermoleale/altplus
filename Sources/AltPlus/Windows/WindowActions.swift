import AppKit

enum WindowAction {
    case minimize
    case close
    case quit
    case hide
}

/// Acciones sobre una ventana desde el panel, por Accesibilidad. Funcionan también para ventanas
/// de otros escritorios gracias a la referencia guardada en el registro.
enum WindowActions {
    static func perform(_ action: WindowAction, on window: WindowInfo) {
        switch action {
        case .minimize:
            AX.set(window.element, kAXMinimizedAttribute, kCFBooleanTrue)
        case .close:
            // No hay acción "cerrar" en AX: se pulsa el botón de cerrar, que dispara la lógica normal
            // de la app (por ejemplo, preguntar si guardar).
            if let button = AX.element(window.element, kAXCloseButtonAttribute) {
                AX.perform(button, kAXPressAction)
            }
        case .quit:
            window.app.terminate()
        case .hide:
            window.app.hide()
        }
        Log.windows.info("Acción \(String(describing: action), privacy: .public) sobre \(window.appName, privacy: .public)")
    }
}
