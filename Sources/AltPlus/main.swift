import AppKit

// AltPlus — conmutador de ventanas libre para macOS.
// Copyright (C) 2026 Guillermo Leale. Licencia GPL-3.0-or-later (ver LICENSE).
//
// Punto de entrada. AltPlus es una app de barra de menú (LSUIElement) sin ventana principal.

AX.configureGlobalTimeout()

if CommandLine.arguments.contains("--diagnostics") {
    Diagnostics.runFromCommandLine(arguments: CommandLine.arguments)
    exit(0)
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
