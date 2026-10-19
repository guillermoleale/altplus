import AppKit

/// Informe de texto con lo que AltPlus ve: permisos, atajos y la lista de ventanas.
/// Sirve para depurar sin herramientas: menú › "Guardar diagnóstico…" o `AltPlus --diagnostics`.
enum Diagnostics {
    static func report(prefs: Preferences, registry: WindowRegistry?) -> String {
        var out = ""
        let formatter = ISO8601DateFormatter()
        out += "\(AppInfo.name) \(AppInfo.version) — \(formatter.string(from: Date()))\n"
        out += "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        out += "Accesibilidad concedida: \(AccessibilityPermission.isGranted)\n"
        out += "Grabación de pantalla concedida: \(ScreenCapturePermission.isGranted) (miniaturas: \(prefs.showThumbnails ? "activadas" : "desactivadas"))\n"
        out += "_AXUIElementGetWindow disponible: \(PrivateAX.isAvailable)\n"
        out += "Búsqueda en escritorios no visitados disponible: \(PrivateAX.canResolveRemoteWindows)\n"
        out += "Atajo mismo escritorio: \(prefs.sameDesktopShortcut.displayString)\n"
        out += "Atajo todos los escritorios: \(prefs.allDesktopsShortcut.displayString)\n"
        out += "Agrupar por app: \(prefs.groupByApp)  minimizadas: \(prefs.showMinimized)  apps ocultas: \(prefs.showHiddenApps)\n"
        out += "Pantallas: \(NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" }.joined(separator: ", "))\n\n"

        let windows = WindowEnumerator.enumerate(EnumerationOptions(), registry: registry)
        let fromAX = windows.filter { !$0.isRemembered }.count
        out += "Ventanas conocidas en el registro: \(registry?.knownCount ?? 0)"
        out += " (descartadas por no ser ventanas reales: \(registry?.unresolvableCount ?? 0))\n"
        out += "Ventanas listadas: \(windows.count) (\(fromAX) a la vista por Accesibilidad, \(windows.count - fromAX) del registro)\n"
        out += "idx  id      fuente    enPantalla  minimizada  oculta  z      app — título\n"
        for (index, w) in windows.enumerated() {
            let id = w.windowID.map(String.init) ?? "-"
            let z = w.zOrder == Int.max ? "-" : String(w.zOrder)
            let columns = [pad(id, 7), pad(w.isRemembered ? "registro" : "AX", 9), pad("\(w.isOnScreen)", 11),
                           pad("\(w.isMinimized)", 11), pad("\(w.isHiddenApp)", 7), pad(z, 6)].joined(separator: " ")
            out += String(format: "%3d  ", index) + columns + " \(w.appName) — \(w.title)"
                + String(format: "  [%.0fx%.0f @ %.0f,%.0f]\n", w.frame.width, w.frame.height, w.frame.minX, w.frame.minY)
        }
        let regularPIDs = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
        let pending = registry.map { $0.unresolvedCandidates(in: WindowEnumerator.cgWindows()) } ?? [:]
        let pendingCount = pending.filter { regularPIDs.contains($0.key) }.values.reduce(0) { $0 + $1.count }
        out += "Ventanas fuera de pantalla pendientes de búsqueda: \(pendingCount)\n"

        out += "\nCGWindowList (capa 0) por app:\n"
        var perApp: [String: (total: Int, onScreen: Int)] = [:]
        let apps = NSWorkspace.shared.runningApplications
        for entry in WindowEnumerator.cgWindows() {
            let name = apps.first { $0.processIdentifier == entry.pid }?.localizedName ?? "pid \(entry.pid)"
            var stats = perApp[name] ?? (0, 0)
            stats.total += 1
            if entry.onScreen { stats.onScreen += 1 }
            perApp[name] = stats
        }
        for name in perApp.keys.sorted() {
            let stats = perApp[name]!
            out += "  " + pad(name, 30) + String(format: " total=%3d  enPantalla=%3d\n", stats.total, stats.onScreen)
        }
        return out
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    static func save(prefs: Preferences, registry: WindowRegistry?) throws -> URL {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AltPlus", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let url = logs.appendingPathComponent("diagnostico-\(stamp.string(from: Date())).txt")
        try report(prefs: prefs, registry: registry).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// `AltPlus --diagnostics [--activate N]`: imprime el informe y, opcionalmente, activa la ventana N
    /// tres segundos después, para probar el cambio de escritorio desde la terminal.
    static func runFromCommandLine(arguments: [String]) {
        let prefs = Preferences.shared
        // Un registro sin observadores: aprende lo visible y busca en los escritorios no visitados.
        let registry = WindowRegistry()
        registry.learnVisibleWindows()
        if !arguments.contains("--no-resolve") { registry.resolveUnknownWindows() }
        print(report(prefs: prefs, registry: registry))
        guard let flag = arguments.firstIndex(of: "--activate"), flag + 1 < arguments.count,
              let index = Int(arguments[flag + 1]) else { return }
        let windows = WindowEnumerator.enumerate(EnumerationOptions(), registry: registry)
        guard windows.indices.contains(index) else {
            print("Índice fuera de rango")
            return
        }
        let target = windows[index]
        print("Activando en 3 s: \(target.appName) — \(target.displayTitle)")
        Thread.sleep(forTimeInterval: 3)
        WindowActivator.activate(target)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
    }
}
