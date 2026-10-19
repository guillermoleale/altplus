import AppKit

struct EnumerationOptions {
    var includeMinimized = true
    var includeHiddenApps = true
    var ignoredBundleIDs: Set<String> = []
}

/// Arma la lista de ventanas combinando CGWindowList (orden y visibilidad, todos los escritorios)
/// con Accesibilidad (títulos, subrol, minimizado; solo el escritorio visible) y el registro de
/// ventanas conocidas (referencias AX de ventanas vistas antes en otros escritorios).
/// Puede llamarse desde un hilo secundario.
enum WindowEnumerator {
    struct CGEntry {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect
        let onScreen: Bool
        let order: Int
    }

    struct CGIndex {
        let entries: [CGEntry]
        let byPID: [pid_t: [CGEntry]]
        let byID: [CGWindowID: CGEntry]

        init(_ entries: [CGEntry]) {
            self.entries = entries
            var byPID: [pid_t: [CGEntry]] = [:]
            var byID: [CGWindowID: CGEntry] = [:]
            for entry in entries {
                byPID[entry.pid, default: []].append(entry)
                byID[entry.id] = entry
            }
            self.byPID = byPID
            self.byID = byID
        }
    }

    static func enumerate(_ options: EnumerationOptions, registry: WindowRegistry?) -> [WindowInfo] {
        let cg = CGIndex(cgWindows())
        var result = scanAccessibility(options, cg: cg, registry: registry)
        guard let registry else { return result }

        let seen = Set(result.compactMap(\.windowID))
        let known = registry.knownSnapshot()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var apps: [pid_t: NSRunningApplication] = [:]

        for entry in cg.entries where !seen.contains(entry.id) && entry.pid != ownPID {
            guard let cached = known[entry.id] else { continue }
            let app: NSRunningApplication
            if let cachedApp = apps[entry.pid] {
                app = cachedApp
            } else if let found = NSRunningApplication(processIdentifier: entry.pid), !found.isTerminated,
                      found.activationPolicy == .regular {
                app = found
                apps[entry.pid] = found
            } else {
                continue
            }
            if let bundleID = app.bundleIdentifier, options.ignoredBundleIDs.contains(bundleID) { continue }
            if app.isHidden && !options.includeHiddenApps { continue }
            let minimized = AX.bool(cached.element, kAXMinimizedAttribute) ?? false
            if minimized && !options.includeMinimized { continue }
            let title = AX.string(cached.element, kAXTitleAttribute) ?? cached.title

            result.append(WindowInfo(
                key: AXElementKey(cached.element),
                windowID: entry.id,
                pid: entry.pid,
                app: app,
                appName: app.localizedName ?? app.bundleIdentifier ?? "?",
                bundleID: app.bundleIdentifier,
                title: title,
                isMinimized: minimized,
                isHiddenApp: app.isHidden,
                isOnScreen: entry.onScreen,
                frame: entry.bounds,
                zOrder: entry.order,
                isRemembered: true
            ))
        }
        registry.prune(keeping: Set(cg.entries.map(\.id)))
        // Ventanas fuera de pantalla que nunca se vieron: se buscan en segundo plano para la próxima vez.
        if !registry.unresolvedCandidates(in: cg.entries).isEmpty {
            registry.scheduleResolve(after: 0.2)
        }
        return result
    }

    /// Ventanas estándar que Accesibilidad expone ahora: las del escritorio visible y las minimizadas.
    /// De paso las registra en `registry`.
    static func scanAccessibility(_ options: EnumerationOptions, cg: CGIndex, registry: WindowRegistry?) -> [WindowInfo] {
        var used = Set<CGWindowID>()
        var result: [WindowInfo] = []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let epoch = registry?.currentEpoch() ?? 0
        let onScreenAtStart = Set(cg.entries.filter(\.onScreen).map(\.id))
        var scannedPIDs = Set<pid_t>()
        var seen = Set<CGWindowID>()

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, !app.isTerminated, app.processIdentifier != ownPID else { continue }
            if let bundleID = app.bundleIdentifier, options.ignoredBundleIDs.contains(bundleID) { continue }
            let hidden = app.isHidden
            if hidden && !options.includeHiddenApps { continue }

            let pid = app.processIdentifier
            let appElement = AX.application(pid: pid)
            guard let windows = AX.elementsIfAvailable(appElement, kAXWindowsAttribute) else { continue }
            // Una app oculta no expone sus ventanas: no sirve para dar por cerradas las conocidas.
            if !hidden { scannedPIDs.insert(pid) }
            if windows.isEmpty { continue }
            let appName = app.localizedName ?? app.bundleIdentifier ?? "?"

            for window in windows {
                guard AX.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole else { continue }
                let minimized = AX.bool(window, kAXMinimizedAttribute) ?? false
                guard let frame = AX.frame(of: window), frame.width > 1, frame.height > 1 else { continue }
                let title = AX.string(window, kAXTitleAttribute) ?? ""

                var entry: CGEntry?
                if let id = PrivateAX.windowID(of: window), let e = cg.byID[id], !used.contains(id) {
                    entry = e
                } else if let candidates = cg.byPID[pid] {
                    entry = candidates.first { !used.contains($0.id) && approximatelyEqual($0.bounds, frame) }
                }
                if let entry {
                    used.insert(entry.id)
                    seen.insert(entry.id)
                    registry?.remember(id: entry.id, element: window, pid: pid, title: title, epoch: epoch)
                }
                if minimized && !options.includeMinimized { continue }

                result.append(WindowInfo(
                    key: AXElementKey(window),
                    windowID: entry?.id,
                    pid: pid,
                    app: app,
                    appName: appName,
                    bundleID: app.bundleIdentifier,
                    title: title,
                    isMinimized: minimized,
                    isHiddenApp: hidden,
                    // Accesibilidad solo expone las ventanas del escritorio visible (y las minimizadas):
                    // si no se pudo cruzar con CGWindowList, una ventana no minimizada está a la vista.
                    isOnScreen: entry?.onScreen ?? !minimized,
                    frame: frame,
                    zOrder: entry?.order ?? Int.max,
                    isRemembered: false
                ))
            }
        }
        registry?.reconcile(seen: seen, scannedPIDs: scannedPIDs, epoch: epoch, onScreenAtStart: onScreenAtStart)
        return result
    }

    /// Ventanas de capa 0 de todos los escritorios. `order` es la posición en el apilamiento de las
    /// ventanas en pantalla (0 = adelante de todo); las que no están en pantalla no tienen orden.
    static func cgWindows() -> [CGEntry] {
        let all = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let onScreen = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        var order: [CGWindowID: Int] = [:]
        for (index, info) in onScreen.enumerated() {
            if let number = info[kCGWindowNumber as String] as? Int { order[CGWindowID(number)] = index }
        }
        var entries: [CGEntry] = []
        entries.reserveCapacity(all.count)
        for info in all {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            let id = CGWindowID(number)
            let position = order[id]
            entries.append(CGEntry(id: id, pid: pid_t(pid), bounds: bounds, onScreen: position != nil, order: position ?? Int.max))
        }
        return entries
    }

    /// IDs de las ventanas de capa 0 que están en pantalla ahora. Cambia de golpe al cambiar de escritorio.
    static func onScreenWindowIDs() -> Set<CGWindowID> {
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        var ids = Set<CGWindowID>()
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            if let number = info[kCGWindowNumber as String] as? Int { ids.insert(CGWindowID(number)) }
        }
        return ids
    }

    static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance &&
            abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
