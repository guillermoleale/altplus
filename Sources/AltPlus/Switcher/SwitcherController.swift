import AppKit

/// Máquina de estados del conmutador: recibe las acciones del teclado y del mouse, enumera ventanas
/// en segundo plano, muestra el panel, pide miniaturas y activa la ventana elegida.
final class SwitcherController: HotkeyMonitorDelegate {
    private enum State {
        case idle
        /// Se disparó el atajo y se están enumerando ventanas. `steps` acumula los Tab apretados
        /// mientras tanto; `commit` y `cancelled` registran si el usuario ya soltó o canceló.
        case loading(mode: SwitcherMode, steps: Int, commit: Bool, cancelled: Bool)
        case showing(mode: SwitcherMode)
    }

    private let monitor: HotkeyMonitor
    private let registry: WindowRegistry
    private let prefs: Preferences
    private let thumbnails = ThumbnailProvider()
    private let model = SwitcherModel()
    private let panel: SwitcherPanel
    private let queue = DispatchQueue(label: "org.altplus.enumerate", qos: .userInteractive)

    private var state: State = .idle
    private var generation = 0
    private var mouseLocationAtShow = NSPoint.zero
    private var screen: NSScreen?

    init(monitor: HotkeyMonitor, registry: WindowRegistry, prefs: Preferences) {
        self.monitor = monitor
        self.registry = registry
        self.prefs = prefs
        self.panel = SwitcherPanel(model: model)
        model.onHover = { [weak self] index in self?.hover(index) }
        model.onClick = { [weak self] index in
            guard let self else { return }
            self.select(index)
            self.switcherCommit()
        }
        model.onAction = { [weak self] index, action in self?.perform(action, on: index) }
    }

    // MARK: - HotkeyMonitorDelegate (hilo principal)

    func hotkeyTriggered(mode: SwitcherMode, reverse: Bool) {
        guard case .idle = state else { return }
        state = .loading(mode: mode, steps: reverse ? -1 : 1, commit: false, cancelled: false)
        enumerate(mode: mode) { [weak self] generation, items in
            self?.loaded(generation: generation, mode: mode, items: items)
        }
    }

    func switcherStep(reverse: Bool) {
        switch state {
        case .loading(let mode, let steps, let commit, let cancelled):
            state = .loading(mode: mode, steps: steps + (reverse ? -1 : 1), commit: commit, cancelled: cancelled)
        case .showing:
            guard !model.items.isEmpty else { return }
            select(wrap(model.selectedIndex + (reverse ? -1 : 1)))
        case .idle:
            break
        }
    }

    func switcherCancel() {
        switch state {
        case .loading(let mode, let steps, let commit, _):
            state = .loading(mode: mode, steps: steps, commit: commit, cancelled: true)
        case .showing:
            finish()
        case .idle:
            break
        }
    }

    func switcherCommit() {
        switch state {
        case .loading(let mode, let steps, _, let cancelled):
            state = .loading(mode: mode, steps: steps, commit: true, cancelled: cancelled)
        case .showing:
            commitNow()
        case .idle:
            break
        }
    }

    func switcherAction(_ action: WindowAction) {
        guard case .showing = state else { return }
        perform(action, on: model.selectedIndex)
    }

    // MARK: - Enumeración

    private func enumerate(mode: SwitcherMode, completion: @escaping (Int, [SwitcherItem]) -> Void) {
        generation += 1
        let currentGeneration = generation
        let registry = self.registry
        let frontmost = NSWorkspace.shared.frontmostApplication
        let options = EnumerationOptions(includeMinimized: prefs.showMinimized,
                                         includeHiddenApps: prefs.showHiddenApps,
                                         ignoredBundleIDs: Set(prefs.ignoredBundleIDs))
        let group = prefs.groupByApp
        let minimizedLast = prefs.minimizedLast

        queue.async {
            // La ventana actual va primera aunque nunca se haya registrado su foco (app recién lanzada,
            // app sin observador AX): si no, el cambio rápido iría a la ventana equivocada.
            if let frontmost { registry.touchFocusedWindow(of: frontmost) }
            let recency = registry.recencySnapshot()
            var windows = WindowEnumerator.enumerate(options, registry: registry)
            if mode == .sameDesktop {
                // No se puede saber en qué escritorio está una ventana minimizada o de una app oculta,
                // así que esas se muestran en los dos modos.
                windows = windows.filter { $0.isOnScreen || $0.isMinimized || $0.isHiddenApp }
            }
            windows = Self.sortedByRecency(windows, recency: recency)
            if minimizedLast {
                windows = windows.filter { !$0.isMinimized } + windows.filter { $0.isMinimized }
            }
            let items = Self.makeItems(windows, groupByApp: group)
            DispatchQueue.main.async { completion(currentGeneration, items) }
        }
    }

    private func loaded(generation: Int, mode: SwitcherMode, items: [SwitcherItem]) {
        guard generation == self.generation,
              case .loading(_, let steps, let commit, let cancelled) = state else { return }
        if cancelled {
            finish()
            return
        }
        model.items = items
        model.mode = mode
        model.selectedIndex = items.isEmpty ? 0 : wrap(steps)

        if commit {
            commitNow()
            return
        }

        let showThumbnails = prefs.showThumbnails && ScreenCapturePermission.isGranted
        model.layout = SwitcherLayout(showTitles: prefs.showTitles, showThumbnails: showThumbnails)
        let ids = items.compactMap(\.window.windowID)
        model.thumbnails = showThumbnails ? thumbnails.cached(for: ids) : [:]

        let screen = targetScreen()
        self.screen = screen
        mouseLocationAtShow = NSEvent.mouseLocation
        state = .showing(mode: mode)
        layoutAndPresent()
        if showThumbnails { refreshThumbnails(ids) }
    }

    /// Vuelve a enumerar sin cerrar el panel (después de cerrar, minimizar o salir de una app).
    private func reload() {
        guard case .showing(let mode) = state else { return }
        let selectedKey = model.items.indices.contains(model.selectedIndex) ? model.items[model.selectedIndex].window.key : nil
        let previousIndex = model.selectedIndex
        enumerate(mode: mode) { [weak self] generation, items in
            guard let self, generation == self.generation, case .showing = self.state else { return }
            self.model.items = items
            if let selectedKey, let index = items.firstIndex(where: { $0.window.key == selectedKey }) {
                self.model.selectedIndex = index
            } else {
                self.model.selectedIndex = items.isEmpty ? 0 : min(previousIndex, items.count - 1)
            }
            let ids = items.compactMap(\.window.windowID)
            self.model.thumbnails = self.model.layout.showThumbnails ? self.thumbnails.cached(for: ids) : [:]
            self.layoutAndPresent()
            if self.model.layout.showThumbnails { self.refreshThumbnails(ids) }
        }
    }

    private func layoutAndPresent() {
        let screen = self.screen ?? targetScreen()
        model.columns = min(max(model.items.count, 1), model.layout.columns(fitting: screen.visibleFrame.width))
        var size = model.layout.size(items: model.items.count, columns: model.columns)
        // Con muchas ventanas la grilla no entra en la pantalla: el panel se limita y la grilla se desplaza.
        size.height = min(size.height, (screen.visibleFrame.height * 0.9).rounded(.down))
        panel.present(size: size, on: screen)
    }

    private func refreshThumbnails(_ ids: [CGWindowID]) {
        thumbnails.refresh(ids: ids, targetSize: SwitcherLayout.thumbnailSize) { [weak self] id, image in
            guard let self, case .showing = self.state else { return }
            self.model.thumbnails[id] = image
        }
    }

    // MARK: - Acciones

    private func perform(_ action: WindowAction, on index: Int) {
        guard case .showing = state, model.items.indices.contains(index) else { return }
        let window = model.items[index].window
        WindowActions.perform(action, on: window)
        if action == .close {
            // Aunque la app retenga la ventana cerrada, no debe volver a listarse.
            registry.forget(window.element)
        }
        // La app necesita un instante para cerrar, minimizar o salir antes de volver a listar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.reload() }
    }

    private func commitNow() {
        let selected = model.items.indices.contains(model.selectedIndex) ? model.items[model.selectedIndex] : nil
        finish()
        guard let selected else { return }
        WindowActivator.activate(selected.window)
        registry.touch(selected.window.element)
    }

    private func finish() {
        thumbnails.cancel()
        panel.dismiss()
        state = .idle
        monitor.endSession()
    }

    private func select(_ index: Int) {
        guard model.items.indices.contains(index), model.selectedIndex != index else { return }
        model.selectedIndex = index
    }

    private func hover(_ index: Int) {
        guard case .showing = state else { return }
        // El panel suele aparecer debajo del puntero: se ignora el hover hasta que el mouse se mueva de verdad.
        let now = NSEvent.mouseLocation
        if hypot(now.x - mouseLocationAtShow.x, now.y - mouseLocationAtShow.y) < 4 { return }
        select(index)
    }

    private func wrap(_ index: Int) -> Int {
        let count = model.items.count
        guard count > 0 else { return 0 }
        return ((index % count) + count) % count
    }

    private func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - Orden y agrupación

    static func sortedByRecency(_ windows: [WindowInfo], recency: [AXElementKey: UInt64]) -> [WindowInfo] {
        windows.sorted { a, b in
            switch (recency[a.key], recency[b.key]) {
            case let (x?, y?):
                return x > y
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                if a.isOnScreen != b.isOnScreen { return a.isOnScreen }
                return a.zOrder < b.zOrder
            }
        }
    }

    static func makeItems(_ windows: [WindowInfo], groupByApp: Bool) -> [SwitcherItem] {
        guard groupByApp else {
            return windows.enumerated().map { SwitcherItem(id: $0.offset, window: $0.element, windowCount: 1) }
        }
        var counts: [pid_t: Int] = [:]
        for window in windows { counts[window.pid, default: 0] += 1 }
        var seen = Set<pid_t>()
        var items: [SwitcherItem] = []
        for window in windows where seen.insert(window.pid).inserted {
            items.append(SwitcherItem(id: items.count, window: window, windowCount: counts[window.pid] ?? 1))
        }
        return items
    }
}
