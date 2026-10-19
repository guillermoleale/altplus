import AppKit
import ApplicationServices

/// Registro de ventanas conocidas y de su orden de uso reciente.
///
/// Accesibilidad solo expone las ventanas del escritorio visible (y las minimizadas). Pero una
/// referencia AX obtenida cuando la ventana estaba a la vista sigue sirviendo después de cambiar
/// de escritorio. El registro guarda esas referencias por CGWindowID a medida que las ve: al abrir
/// el conmutador, al cambiar de escritorio, al crearse o enfocarse una ventana. Con eso, el modo
/// "todos los escritorios" puede listar y activar ventanas que ya no están a la vista.
///
/// Escritorios no visitados: al arrancar, al lanzarse una app y cuando aparecen ventanas desconocidas,
/// `RemoteWindowResolver` busca en segundo plano las referencias de las ventanas que no están a la
/// vista. Las que no se encuentran (ventanas internas, cerradas) se recuerdan para no buscarlas otra vez.
///
/// Ventanas "fantasma": una ventana cerrada que la app retiene (muchas ventanas de Preferencias)
/// sigue figurando en CGWindowList igual que una de otro escritorio. Para depurarlas se lleva una
/// "época" que avanza con cada cambio de escritorio: si una ventana se vio en la época actual y en
/// un recorrido posterior de la misma época ya no aparece, se da por cerrada y se olvida.
final class WindowRegistry {
    struct Known {
        let element: AXUIElement
        let pid: pid_t
        var title: String
        var epoch: Int
    }

    /// Época de las ventanas encontradas en escritorios no visitados: nunca se vieron a la vista, así que
    /// la depuración de fantasmas no las toca hasta que se visite su escritorio.
    static let neverOnScreen = -1

    /// Tamaño mínimo para buscar una ventana desconocida. Debajo de esto casi todo son ventanas internas.
    static let minimumCandidateSize = CGSize(width: 100, height: 50)

    private var known: [CGWindowID: Known] = [:]
    private var unresolvable = Set<CGWindowID>()
    private var recency: [AXElementKey: UInt64] = [:]
    private var counter: UInt64 = 0
    private var spaceEpoch = 0
    private let lock = NSLock()

    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private let learnQueue = DispatchQueue(label: "org.altplus.learn", qos: .utility)
    private let resolveQueue = DispatchQueue(label: "org.altplus.resolve", qos: .utility)
    private var learnScheduled = false
    private var resolveScheduled = false
    private(set) var isRunning = false
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let workspace = NSWorkspace.shared
        let center = workspace.notificationCenter

        for app in workspace.runningApplications where app.activationPolicy == .regular {
            observe(app)
        }

        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            // Recién lanzada, la app todavía no responde por Accesibilidad.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self?.observe(app)
                self?.scheduleLearn(after: 0.5)
                // Una app que restaura ventanas en otros escritorios: se buscan cuando terminó de abrirlas.
                self?.scheduleResolve(after: 2.0)
            }
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.unobserve(pid: app.processIdentifier)
        })
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            self.touchFocusedWindow(of: app)
            if self.observers[app.processIdentifier] == nil { self.observe(app) }
        })
        // Al cambiar de escritorio avanza la época y se aprenden las ventanas del escritorio nuevo.
        workspaceTokens.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.spaceEpoch += 1
            self.lock.unlock()
            self.scheduleLearn(after: 0.4)
            self.scheduleResolve(after: 1.0)
        })

        if let front = workspace.frontmostApplication, front.activationPolicy == .regular {
            touchFocusedWindow(of: front)
        }
        scheduleLearn(after: 0.3)
        scheduleResolve(after: 1.0)
    }

    // MARK: - Uso reciente

    func touch(_ element: AXUIElement) {
        lock.lock()
        counter += 1
        recency[AXElementKey(element)] = counter
        lock.unlock()
    }

    func forget(_ element: AXUIElement) {
        lock.lock()
        recency.removeValue(forKey: AXElementKey(element))
        known = known.filter { !CFEqual($0.value.element, element) }
        lock.unlock()
    }

    /// Copia del orden reciente, segura para usar desde otro hilo.
    func recencySnapshot() -> [AXElementKey: UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return recency
    }

    func touchFocusedWindow(of app: NSRunningApplication) {
        guard app.activationPolicy == .regular, app.processIdentifier != ownPID else { return }
        let appElement = AX.application(pid: app.processIdentifier)
        if let window = AX.element(appElement, kAXFocusedWindowAttribute) {
            touch(window)
            rememberElement(window, pid: app.processIdentifier)
        }
    }

    // MARK: - Ventanas conocidas

    func currentEpoch() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return spaceEpoch
    }

    /// `epoch` es la época en que se vio la ventana; por defecto, la actual. Un recorrido pasa la época
    /// en que empezó, para no marcar como "vista en este escritorio" algo que vio antes de un cambio.
    func remember(id: CGWindowID, element: AXUIElement, pid: pid_t, title: String, epoch: Int? = nil) {
        guard pid != ownPID else { return }
        lock.lock()
        known[id] = Known(element: element, pid: pid, title: title, epoch: epoch ?? spaceEpoch)
        lock.unlock()
    }

    func knownSnapshot() -> [CGWindowID: Known] {
        lock.lock()
        defer { lock.unlock() }
        return known
    }

    var knownCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return known.count
    }

    var unresolvableCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return unresolvable.count
    }

    /// Olvida las ventanas que ya no existen (no figuran en CGWindowList), también en el orden reciente.
    func prune(keeping ids: Set<CGWindowID>) {
        lock.lock()
        defer { lock.unlock() }
        unresolvable.formIntersection(ids)
        for (id, entry) in known where !ids.contains(id) {
            known.removeValue(forKey: id)
            recency.removeValue(forKey: AXElementKey(entry.element))
        }
    }

    /// Después de un recorrido de Accesibilidad: las ventanas de apps recorridas que se habían visto
    /// en esta misma época y ahora no aparecen se dan por cerradas. Solo si no cambió el escritorio
    /// durante el recorrido: ni la época (notificación de cambio) ni el conjunto de ventanas en pantalla
    /// (la notificación llega al final de la animación y el recorrido pudo cruzarse con ella).
    func reconcile(seen: Set<CGWindowID>, scannedPIDs: Set<pid_t>, epoch: Int, onScreenAtStart: Set<CGWindowID>) {
        guard WindowEnumerator.onScreenWindowIDs() == onScreenAtStart else { return }
        lock.lock()
        defer { lock.unlock() }
        guard epoch == spaceEpoch else { return }
        let before = known.count
        known = known.filter { id, entry in
            !(scannedPIDs.contains(entry.pid) && entry.epoch == epoch && !seen.contains(id))
        }
        if known.count != before {
            Log.windows.debug("Registro: \(before - self.known.count) ventanas dadas por cerradas")
        }
    }

    /// Resuelve el CGWindowID de una ventana AX y la registra si es una ventana estándar de una app normal.
    func rememberElement(_ element: AXUIElement, pid: pid_t? = nil) {
        guard let pid = pid ?? AX.pid(of: element), pid != ownPID,
              let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { return }
        guard AX.string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole else { return }
        var id = PrivateAX.windowID(of: element)
        if id == nil, let frame = AX.frame(of: element) {
            id = WindowEnumerator.cgWindows().first { $0.pid == pid && WindowEnumerator.approximatelyEqual($0.bounds, frame) }?.id
        }
        guard let id else { return }
        remember(id: id, element: element, pid: pid, title: AX.string(element, kAXTitleAttribute) ?? "")
    }

    // MARK: - Escritorios no visitados

    /// Ventanas fuera de pantalla de apps normales sin referencia conocida y que no se buscaron antes.
    func unresolvedCandidates(in entries: [WindowEnumerator.CGEntry]) -> [pid_t: Set<CGWindowID>] {
        let minimum = Self.minimumCandidateSize
        lock.lock()
        defer { lock.unlock() }
        var candidates: [pid_t: Set<CGWindowID>] = [:]
        for entry in entries where !entry.onScreen && entry.pid != ownPID
            && entry.bounds.width >= minimum.width && entry.bounds.height >= minimum.height
            && known[entry.id] == nil && !unresolvable.contains(entry.id) {
            candidates[entry.pid, default: []].insert(entry.id)
        }
        return candidates
    }

    /// Programa una búsqueda de ventanas de escritorios no visitados. Se puede llamar desde cualquier hilo.
    func scheduleResolve(after delay: TimeInterval) {
        guard PrivateAX.canResolveRemoteWindows else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.scheduleResolve(after: delay) }
            return
        }
        guard !resolveScheduled else { return }
        resolveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.resolveScheduled = false
            self.resolveQueue.async { self.resolveUnknownWindows() }
        }
    }

    /// Busca las referencias de las ventanas candidatas. Bloquea: llamar en segundo plano.
    func resolveUnknownWindows() {
        let entries = WindowEnumerator.cgWindows()
        prune(keeping: Set(entries.map(\.id)))
        let candidates = unresolvedCandidates(in: entries)
        guard !candidates.isEmpty else { return }

        let start = Date()
        var resolved = 0
        var discarded = 0
        for (pid, wanted) in candidates {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
                  app.activationPolicy == .regular else { continue }
            let result = RemoteWindowResolver.resolve(pid: pid, wanted: wanted)
            var notWindows = wanted
            for (id, element) in result.found {
                guard AX.string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole else { continue }
                notWindows.remove(id)
                remember(id: id, element: element, pid: pid,
                         title: AX.string(element, kAXTitleAttribute) ?? "", epoch: Self.neverOnScreen)
                resolved += 1
            }
            // Si la app no respondió se vuelve a intentar más adelante; si no, lo que no apareció como
            // ventana estándar no se busca más (cada búsqueda fallida recorre todo el rango).
            if result.outcome != .unresponsive {
                lock.lock()
                unresolvable.formUnion(notWindows)
                lock.unlock()
                discarded += notWindows.count
            }
        }
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        Log.windows.info("Escritorios no visitados: \(resolved) ventanas encontradas, \(discarded) descartadas, \(elapsed) ms")
    }

    // MARK: - Recorridos

    /// Programa un recorrido de Accesibilidad en segundo plano para registrar lo que está a la vista.
    func scheduleLearn(after delay: TimeInterval) {
        guard !learnScheduled else { return }
        learnScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.learnScheduled = false
            self.learnQueue.async { self.learnVisibleWindows() }
        }
    }

    func learnVisibleWindows() {
        let cg = WindowEnumerator.CGIndex(WindowEnumerator.cgWindows())
        _ = WindowEnumerator.scanAccessibility(EnumerationOptions(), cg: cg, registry: self)
        Log.windows.debug("Registro: \(self.knownCount) ventanas conocidas")
    }

    // MARK: - Observadores AX

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil, !app.isTerminated, pid != ownPID else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, registryObserverCallback, &observer) == .success, let observer else {
            Log.windows.debug("No se pudo crear AXObserver para \(app.localizedName ?? "?", privacy: .public)")
            return
        }
        let appElement = AX.application(pid: pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notifications = [
            kAXFocusedWindowChangedNotification,
            kAXApplicationActivatedNotification,
            kAXWindowCreatedNotification,
            kAXUIElementDestroyedNotification,
        ]
        var registered = 0
        for name in notifications {
            let error = AXObserverAddNotification(observer, appElement, name as CFString, refcon)
            if error == .success { registered += 1 }
            // La app no responde: no se espera el timeout de cada notificación en el hilo principal.
            if error == .cannotComplete { break }
        }
        // Una app recién lanzada (o colgada) todavía no acepta notificaciones. No se guarda el observador
        // para volver a intentarlo cuando la app se active.
        guard registered > 0 else {
            Log.windows.debug("\(app.localizedName ?? "?", privacy: .public) no aceptó notificaciones AX; se reintenta al activarse")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
    }

    private func unobserve(pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        lock.lock()
        known = known.filter { $0.value.pid != pid }
        recency = recency.filter { AX.pid(of: $0.key.element) != pid }
        lock.unlock()
    }

    fileprivate func handle(notification: String, element: AXUIElement) {
        switch notification {
        case kAXFocusedWindowChangedNotification:
            touch(element)
            rememberElement(element)
        case kAXWindowCreatedNotification:
            // Crearse no es usarse: si la ventana toma el foco, llega también FocusedWindowChanged.
            rememberElement(element)
        case kAXApplicationActivatedNotification:
            if let window = AX.element(element, kAXFocusedWindowAttribute) {
                touch(window)
                rememberElement(window)
            }
        case kAXUIElementDestroyedNotification:
            forget(element)
        default:
            break
        }
    }
}

private let registryObserverCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let registry = Unmanaged<WindowRegistry>.fromOpaque(refcon).takeUnretainedValue()
    registry.handle(notification: notification as String, element: element)
}
