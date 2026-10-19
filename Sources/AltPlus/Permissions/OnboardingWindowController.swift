import AppKit
import Combine
import SwiftUI

struct OnboardingView: View {
    var onOpenSettings: () -> Void
    var onQuit: () -> Void
    @State private var granted = AccessibilityPermission.isGranted
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                Text(tr("AltPlus necesita el permiso de Accesibilidad", "AltPlus needs the Accessibility permission"))
                    .font(.title3.weight(.semibold))
            }
            Text(tr("Es el único permiso obligatorio. Sirve para ver las ventanas de las demás apps, traerlas al frente y capturar el atajo de teclado. Las miniaturas, opcionales, piden además Grabación de pantalla.",
                    "It is the only required permission. It lets AltPlus list other apps' windows, bring them to the front and capture the keyboard shortcut. Optional thumbnails also need Screen Recording."))
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("1. Abre Ajustes del Sistema › Privacidad y seguridad › Accesibilidad.", "1. Open System Settings › Privacy & Security › Accessibility."))
                Text(tr("2. Activa AltPlus en la lista.", "2. Turn on AltPlus in the list."))
                Text(tr("3. Si ya figura activado pero no funciona, quítalo con − y vuelve a agregarlo con +.", "3. If it is already on but does not work, remove it with − and add it again with +."))
            }
            .font(.callout)
            HStack {
                if granted {
                    Label(tr("Permiso concedido. ¡Listo!", "Permission granted. Done!"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ProgressView().controlSize(.small)
                    Text(tr("Esperando el permiso…", "Waiting for permission…")).foregroundStyle(.secondary)
                }
                Spacer()
                Button(tr("Salir", "Quit"), action: onQuit)
                Button(tr("Abrir Ajustes del Sistema", "Open System Settings"), action: onOpenSettings)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onReceive(refresh) { _ in granted = AccessibilityPermission.isGranted }
    }
}

final class OnboardingWindowController: NSWindowController {
    convenience init() {
        let view = OnboardingView(
            onOpenSettings: { AccessibilityPermission.openSystemSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = AppInfo.name
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
