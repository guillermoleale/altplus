import Combine
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var accessibilityGranted = AccessibilityPermission.isGranted
    @State private var screenCaptureGranted = ScreenCapturePermission.isGranted
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section(tr("Atajos", "Shortcuts")) {
                LabeledContent(tr("Ventanas de este escritorio", "Windows on this desktop")) {
                    ShortcutRecorder(shortcut: $prefs.sameDesktopShortcut)
                }
                LabeledContent(tr("Ventanas de todos los escritorios", "Windows on all desktops")) {
                    ShortcutRecorder(shortcut: $prefs.allDesktopsShortcut)
                }
                Text(tr("Mantén el modificador apretado, pulsa la tecla para avanzar y agrega ⇧ para retroceder. Suelta el modificador para cambiar de ventana.",
                        "Hold the modifier, press the key to move forward and add ⇧ to go back. Release the modifier to switch."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if prefs.sameDesktopShortcut == prefs.allDesktopsShortcut {
                    Label(tr("Los dos atajos son iguales: solo funcionará el primero.", "Both shortcuts are the same: only the first one will work."),
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section(tr("Lista", "List")) {
                Toggle(tr("Agrupar por aplicación", "Group by application"), isOn: $prefs.groupByApp)
                Toggle(tr("Mostrar títulos de ventana", "Show window titles"), isOn: $prefs.showTitles)
                Toggle(tr("Incluir ventanas minimizadas", "Include minimized windows"), isOn: $prefs.showMinimized)
                Toggle(tr("Ponerlas al final de la lista", "Put them at the end of the list"), isOn: $prefs.minimizedLast)
                    .disabled(!prefs.showMinimized)
                    .padding(.leading, 20)
                Toggle(tr("Incluir ventanas de apps ocultas", "Include windows of hidden apps"), isOn: $prefs.showHiddenApps)
                Toggle(tr("Mostrar miniaturas de las ventanas", "Show window thumbnails"), isOn: Binding(
                    get: { prefs.showThumbnails },
                    set: { value in
                        prefs.showThumbnails = value
                        if value && !ScreenCapturePermission.isGranted { ScreenCapturePermission.request() }
                    }
                ))
                if prefs.showThumbnails && !screenCaptureGranted {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(tr("Falta el permiso de Grabación de pantalla.", "Screen Recording permission is missing."), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(tr("Actívalo en Ajustes del Sistema › Privacidad y seguridad › Grabación de pantalla y después cierra y vuelve a abrir AltPlus. Sin él, el panel sigue funcionando con íconos.",
                                "Enable it in System Settings › Privacy & Security › Screen Recording, then quit and reopen AltPlus. Without it the panel keeps working with icons."))
                            .foregroundStyle(.secondary)
                        Button(tr("Abrir Ajustes", "Open Settings")) { ScreenCapturePermission.openSystemSettings() }
                    }
                    .font(.caption)
                }
                Text(tr("Con el panel abierto: pasa el mouse por una ventana para minimizarla, cerrarla o salir de su app. Con el teclado: M, W, Q y H (ocultar).",
                        "While the panel is open: hover a window to minimize it, close it or quit its app. Keyboard: M, W, Q and H (hide)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(tr("General", "General")) {
                Toggle(tr("Abrir al iniciar sesión", "Launch at login"), isOn: Binding(
                    get: { launchAtLogin },
                    set: { value in
                        do {
                            try LaunchAtLogin.set(value)
                        } catch {
                            Log.app.error("No se pudo cambiar el arranque al iniciar sesión: \(error.localizedDescription, privacy: .public)")
                            NSSound.beep()
                        }
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                LabeledContent(tr("Permiso de Accesibilidad", "Accessibility permission")) {
                    HStack {
                        if accessibilityGranted {
                            Label(tr("Concedido", "Granted"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label(tr("Falta", "Missing"), systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Button(tr("Abrir Ajustes", "Open Settings")) {
                                AccessibilityPermission.openSystemSettings()
                            }
                        }
                    }
                }
            }

            Section {
                HStack {
                    Text("\(AppInfo.name) \(AppInfo.version) · GPL-3.0")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Link(tr("Código fuente", "Source code"), destination: AppInfo.repositoryURL)
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onReceive(refresh) { _ in
            accessibilityGranted = AccessibilityPermission.isGranted
            screenCaptureGranted = ScreenCapturePermission.isGranted
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
