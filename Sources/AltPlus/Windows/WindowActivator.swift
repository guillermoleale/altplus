import AppKit

/// Trae una ventana al frente. Si está en otro escritorio, macOS cambia de escritorio
/// (requiere la opción de Mission Control "Al cambiar a una aplicación, cambiar a un espacio
/// con ventanas abiertas de la aplicación", activa por defecto).
enum WindowActivator {
    static func activate(_ window: WindowInfo) {
        let element = window.element
        if window.isMinimized {
            AX.set(element, kAXMinimizedAttribute, kCFBooleanFalse)
        }
        if window.app.isHidden {
            window.app.unhide()
        }
        // Primero la ventana: así pasa a ser la ventana principal de la app y la activación la muestra.
        AX.perform(element, kAXRaiseAction)
        let appElement = AX.application(pid: window.pid)
        AX.set(appElement, kAXFrontmostAttribute, kCFBooleanTrue)
        if !window.app.isActive {
            window.app.activate(options: [])
        }
        // Segundo intento corto después de la activación, por si la app reordenó sus ventanas.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            AX.perform(element, kAXRaiseAction)
        }
        Log.windows.info("Activada: \(window.appName, privacy: .public) — \(window.title, privacy: .public)")
    }
}
