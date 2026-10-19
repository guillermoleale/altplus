import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences.shared
    private let monitor = HotkeyMonitor()
    private let registry = WindowRegistry()
    private var signalSource: DispatchSourceSignal?
    private var controller: SwitcherController!
    private var statusItem: StatusItemController!
    private var preferencesWindow: PreferencesWindowController?
    private var onboardingWindow: OnboardingWindowController?
    private var permissionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var engineStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = SwitcherController(monitor: monitor, registry: registry, prefs: prefs)
        monitor.delegate = controller
        syncShortcuts()

        prefs.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange llega antes del cambio: se lee el valor nuevo en el próximo ciclo.
                DispatchQueue.main.async { self?.syncShortcuts() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: .shortcutRecordingDidChange, object: nil, queue: .main) { [weak self] note in
            self?.monitor.isSuspended = (note.userInfo?["recording"] as? Bool) ?? false
        }

        statusItem = StatusItemController(prefs: prefs, actions: StatusItemController.Actions(
            openPreferences: { [weak self] in self?.showPreferences() },
            saveDiagnostics: { [weak self] in self?.saveDiagnostics() },
            openAccessibilitySettings: { AccessibilityPermission.openSystemSettings() },
            quit: { NSApp.terminate(nil) }
        ))

        if AccessibilityPermission.isGranted {
            startEngine()
        } else {
            AccessibilityPermission.requestWithPrompt()
            showOnboarding()
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }
        installSignalHandler()
        if prefs.showThumbnails && !ScreenCapturePermission.isGranted {
            // El usuario pidió miniaturas pero falta el permiso: se pide una vez por arranque.
            ScreenCapturePermission.request()
        }
        Log.app.info("AltPlus \(AppInfo.version, privacy: .public) iniciado")
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    private func syncShortcuts() {
        monitor.shortcuts = prefs.shortcutsByMode
    }

    private func startEngine() {
        guard !engineStarted else { return }
        guard monitor.start() else { return }
        engineStarted = true
        registry.start()
    }

    private func checkPermission() {
        guard AccessibilityPermission.isGranted else {
            if engineStarted {
                // Se revocó el permiso con la app abierta: un event tap sin permiso deja de recibir
                // (o retiene) el teclado. Se apaga y se vuelve a encender cuando se conceda otra vez.
                Log.app.warning("Se revocó el permiso de Accesibilidad; se detiene el event tap")
                controller.switcherCancel()
                monitor.stop()
                engineStarted = false
            }
            return
        }
        startEngine()
        if engineStarted, let onboarding = onboardingWindow {
            // Se deja ver el "listo" un instante antes de cerrar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onboarding.close()
            }
            onboardingWindow = nil
        }
    }

    private func showOnboarding() {
        if onboardingWindow == nil { onboardingWindow = OnboardingWindowController() }
        onboardingWindow?.show()
    }

    private func showPreferences() {
        if preferencesWindow == nil { preferencesWindow = PreferencesWindowController(prefs: prefs) }
        preferencesWindow?.show()
    }

    private func saveDiagnostics(reveal: Bool = true) {
        do {
            let url = try Diagnostics.save(prefs: prefs, registry: registry)
            if reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        } catch {
            if reveal { NSAlert(error: error).runModal() }
        }
    }

    /// `kill -USR1 <pid>` guarda un diagnóstico sin tocar la interfaz. Útil para depurar desde la terminal.
    private func installSignalHandler() {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in self?.saveDiagnostics(reveal: false) }
        source.resume()
        signalSource = source
    }
}
