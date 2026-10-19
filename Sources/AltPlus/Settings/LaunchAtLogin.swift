import ServiceManagement

enum LaunchAtLogin {
    /// `.requiresApproval` cuenta como activado: está registrado y solo falta que el usuario lo apruebe.
    static var isEnabled: Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            // macOS pide aprobarlo en Ajustes del Sistema › General › Ítems de inicio.
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
