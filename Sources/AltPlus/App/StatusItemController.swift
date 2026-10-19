import AppKit

/// Ícono en la barra de menú con el menú de la app.
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var openPreferences: () -> Void
        var saveDiagnostics: () -> Void
        var openAccessibilitySettings: () -> Void
        var quit: () -> Void
    }

    private let item: NSStatusItem
    private let menu = NSMenu()
    private let prefs: Preferences
    private let actions: Actions
    private var handlers: [Int: () -> Void] = [:]

    init(prefs: Preferences, actions: Actions) {
        self.prefs = prefs
        self.actions = actions
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = item.button {
            let image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: AppInfo.name)
            image?.isTemplate = true
            button.image = image
            button.toolTip = AppInfo.name
        }
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        handlers.removeAll()

        addDisabled("\(AppInfo.name) \(AppInfo.version)")
        menu.addItem(.separator())

        if !AccessibilityPermission.isGranted {
            add(tr("⚠️ Falta el permiso de Accesibilidad…", "⚠️ Accessibility permission missing…"), action: actions.openAccessibilitySettings)
            menu.addItem(.separator())
        }

        addDisabled(tr("Este escritorio: \(prefs.sameDesktopShortcut.displayString)", "This desktop: \(prefs.sameDesktopShortcut.displayString)"))
        addDisabled(tr("Todos los escritorios: \(prefs.allDesktopsShortcut.displayString)", "All desktops: \(prefs.allDesktopsShortcut.displayString)"))
        menu.addItem(.separator())

        addToggle(tr("Agrupar por aplicación", "Group by application"), isOn: prefs.groupByApp) { [prefs] in prefs.groupByApp.toggle() }
        addToggle(tr("Mostrar ventanas minimizadas", "Show minimized windows"), isOn: prefs.showMinimized) { [prefs] in prefs.showMinimized.toggle() }
        addToggle(tr("Mostrar apps ocultas", "Show hidden apps"), isOn: prefs.showHiddenApps) { [prefs] in prefs.showHiddenApps.toggle() }
        addToggle(tr("Mostrar miniaturas", "Show thumbnails"), isOn: prefs.showThumbnails) { [prefs] in
            prefs.showThumbnails.toggle()
            if prefs.showThumbnails && !ScreenCapturePermission.isGranted { ScreenCapturePermission.request() }
        }
        menu.addItem(.separator())

        add(tr("Preferencias…", "Preferences…"), key: ",", action: actions.openPreferences)
        add(tr("Guardar diagnóstico…", "Save diagnostics…"), action: actions.saveDiagnostics)
        menu.addItem(.separator())
        add(tr("Salir de AltPlus", "Quit AltPlus"), key: "q", action: actions.quit)
    }

    private func addDisabled(_ title: String) {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        menu.addItem(menuItem)
    }

    private func addToggle(_ title: String, isOn: Bool, action: @escaping () -> Void) {
        let menuItem = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.state = isOn ? .on : .off
        menuItem.tag = handlers.count + 1
        handlers[menuItem.tag] = action
        menu.addItem(menuItem)
    }

    private func add(_ title: String, key: String = "", action: @escaping () -> Void) {
        let menuItem = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: key)
        menuItem.target = self
        menuItem.tag = handlers.count + 1
        handlers[menuItem.tag] = action
        menu.addItem(menuItem)
    }

    @objc private func run(_ sender: NSMenuItem) {
        handlers[sender.tag]?()
    }
}
