import AppKit
import CoreGraphics

/// Permiso de Grabación de pantalla. Solo hace falta para las miniaturas; es opcional.
/// macOS lo aplica recién al volver a abrir la app después de concederlo.
enum ScreenCapturePermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Muestra el diálogo del sistema y agrega la app a la lista (desactivada).
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
