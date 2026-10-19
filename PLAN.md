# Plan de AltPlus

Conmutador de ventanas libre para macOS, escrito desde cero con las APIs documentadas de Apple. Sin funciones de pago. GPL-3.0.

## Decisiones tomadas

- **Nivel ventana con agrupación opcional por app.** Lo que distingue a un conmutador tipo AltTab de `⌘⇥` es cambiar entre ventanas. "Agrupar por aplicación" colapsa a un ítem por app.
- **Atajos por defecto:** `⌥⇥` para el escritorio actual, `⌥⌃⇥` para todos los escritorios. Configurables desde Preferencias. `⇧` retrocede.
- **"Escritorios"** significa los escritorios de Mission Control (Spaces).
- **Licencia GPL-3.0-or-later.**
- **Un permiso obligatorio:** Accesibilidad. Grabación de pantalla solo si el usuario activa las miniaturas.
- **Stack:** Swift 6 (modo de lenguaje 5), AppKit + SwiftUI para las vistas, Swift Package Manager. Compila con Command Line Tools, sin Xcode. Mínimo macOS 14.
- **Sin APIs privadas**, salvo dos funciones de Accesibilidad aisladas en `PrivateAX.swift`, resueltas por `dlsym` y con respaldo si faltan: `_AXUIElementGetWindow` y `_AXUIElementCreateWithRemoteToken`.

## Lo que se verificó antes de escribir código

Sonda de solo lectura en la Mac de desarrollo (macOS 26.6, tres o más escritorios por monitor):

- `CGWindowListCopyWindowInfo` con `.optionAll` lista las ventanas de otros escritorios, con `kCGWindowIsOnscreen = false` y su tamaño real.
- "Mismo escritorio" = ventanas con `kCGWindowIsOnscreen = true`. No hace falta ninguna API privada.
- La API pública no dice en qué escritorio está una ventana no visible, ni distingue minimizada de "en otro escritorio". Lo segundo lo resuelve Accesibilidad.
- En capa 0 hay mucha basura (ventanas de 1x1, barras de 1680x30, cuadros de 64x64). El filtro bueno es el subrol `AXStandardWindow` de Accesibilidad.
- Sin Grabación de pantalla, CGWindowList no trae títulos. Los títulos salen de Accesibilidad.
- **Accesibilidad solo expone las ventanas del escritorio visible** (más las minimizadas). Verificado con la app corriendo con permiso: en un escritorio con una sola ventana a la vista, `kAXWindowsAttribute` devolvió esa sola ventana en todas las apps, mientras CGWindowList contaba decenas en otros escritorios. Una referencia AX ya obtenida sigue funcionando después de cambiar de escritorio, y en eso se apoya el registro de ventanas conocidas.

- **Una ventana cerrada que la app retiene** (`isReleasedWhenClosed = false`, típico de Preferencias) sigue en CGWindowList con `.optionAll`, idéntica a una de otro escritorio: mismo `onscreen = false`, alfa y memoria. Verificado con una ventana de prueba. Por eso el registro lleva una época por cambio de escritorio y da por cerradas las ventanas vistas en la época actual que ya no aparecen.

## Arquitectura

| Pieza | Archivo | Qué hace |
|---|---|---|
| Entrada | `Input/HotkeyMonitor.swift` | Event tap de CoreGraphics. Detecta los atajos, se traga las teclas mientras el panel está abierto, detecta cuándo se sueltan los modificadores. |
| Atajos | `Input/Shortcut.swift`, `Input/KeyNames.swift` | Modelo tecla + modificadores, nombres legibles. |
| Inventario | `Windows/WindowEnumerator.swift`, `Windows/AX.swift` | Cruza CGWindowList con Accesibilidad. Corre en segundo plano con timeout de 0,3 s por app. |
| Registro | `Windows/WindowRegistry.swift` | Referencias AX por CGWindowID aprendidas al abrir el panel, al cambiar de escritorio y por AXObserver (ventana enfocada, app activada, creadas, destruidas). También lleva el orden de uso reciente. |
| Activación | `Windows/WindowActivator.swift` | Des-minimiza, `AXRaise`, `AXFrontmost`, `NSRunningApplication.activate`. |
| Conmutador | `Switcher/SwitcherController.swift` | Máquina de estados: idle → loading → showing. Acumula los Tab apretados mientras se enumera; si se soltó antes de mostrar, cambia sin mostrar el panel. |
| Panel | `Switcher/SwitcherPanel.swift`, `SwitcherView.swift` | `NSPanel` no activante, en todos los escritorios y sobre pantalla completa. SwiftUI adentro. |
| Preferencias | `Settings/` | UserDefaults, grabador de atajos, arranque al inicio. |
| Permisos | `Permissions/` | Ventana de onboarding que espera el permiso de Accesibilidad. |
| Diagnóstico | `Diagnostics.swift` | Informe de texto desde el menú o con `--diagnostics`. |

## Fases

1. **Spike** — compilar, conceder Accesibilidad y validar en la Mac real: enumeración por Accesibilidad, activación de una ventana de otro escritorio, captura de `⌥⇥`. *Código listo; falta la validación manual.*
2. **MVP** — dos atajos, panel, orden reciente, filtro por escritorio, barra de menú, onboarding, arranque al inicio. *Código escrito en la fase 1; se pule con lo que salga de la validación.*
3. **Pulido** — ajustes de aspecto, multimonitor, "toque rápido" sin panel, release 0.1 con workflow de GitHub Actions.

## Extras por valor sobre costo

- [ ] Tercer atajo: ventanas de la app actual.
- [x] Acciones desde el panel: cerrar (W), minimizar (M), ocultar (H), salir (Q), también con botones al pasar el mouse.
- [x] Miniaturas opcionales con ScreenCaptureKit (segundo permiso, Grabación de pantalla, solo si se activan).
- [ ] Buscar escribiendo para filtrar por título o app.
- [ ] Saltar con 1 a 9.
- [ ] Lista de apps ignoradas con interfaz (el dato ya existe en Preferencias).
- [ ] Atajos directos por app (una tecla que siempre lleva a la terminal).
- [ ] Retraso configurable antes de mostrar el panel.
- [ ] Tap de Homebrew.
- [x] Ventanas de escritorios no visitados con `_AXUIElementCreateWithRemoteToken`, en segundo plano (`RemoteWindowResolver`). Probado en macOS 26.6: las ventanas reales aparecen en menos de 60 ms por app; las que no son ventanas reales recorren todo el rango (de 0,5 a 3,8 s por app) y se recuerdan para no buscarlas otra vez.
- Fuera, al menos por ahora: etiqueta de número de escritorio (APIs privadas), reemplazo de `⌘⇥` (frágil).

## Distribución

- Sin cuenta de desarrollador de Apple: no hay notarización, Gatekeeper avisa la primera vez. Se mitiga con el script de instalación y el cask (quitan la cuarentena) y con instrucciones claras para la descarga manual.
- Firma de releases con el certificado autofirmado "AltPlus Release", distinto del de desarrollo, creado y cargado en secrets por `scripts/setup-release-signing.sh`. CI lo importa en un llavero temporal; no hace falta marcarlo como confiable. Sin secrets, el workflow firma ad hoc.
- Canales: `install.sh` (curl | bash), cask de Homebrew dentro del mismo repo (se instala con el nombre completo por la confianza de taps de Homebrew 6), zip y dmg en Releases.
- Automatización: `scripts/release.sh X.Y.Z` etiqueta; el workflow compila universal (arm64 + x86_64 con lipo), empaqueta, publica y actualiza el cask.
- Pendiente: actualizaciones automáticas dentro de la app (Sparkle con claves EdDSA propias, no requiere cuenta de Apple).

## Revisión previa al primer lanzamiento (19/10/2026)

Se corrigieron: timeout de Accesibilidad global de 0,3 s, sesión que quedaba abierta si se perdía el evento de soltar el modificador, repetición de W/M/Q/H al mantener la tecla, exportación de todas las identidades del llavero en el script del certificado, grabador de atajos que dejaba el event tap suspendido, observadores AX que no se reintentaban, orden reciente sin la ventana actual, errores silenciosos en install.sh, permiso revocado con la app abierta, panel más alto que la pantalla, ventanas visibles marcadas como de otro escritorio, ventanas nuevas tomadas como recientes, fugas en el orden reciente y en la caché de miniaturas, errores ocultos en "abrir al iniciar sesión", carrera entre un recorrido y un cambio de escritorio que podía olvidar ventanas, atajos guardados sin modificador, texto del onboarding, columnas del diagnóstico y código muerto.

Queda conocido: el event tap corre en el hilo principal junto con llamadas AX (acotadas a 0,3 s). La solución de fondo es un hilo propio para el tap.

## Riesgos

- Apps Electron o Java que reportan mal sus ventanas por Accesibilidad.
- macOS desactiva el event tap si la callback tarda: se reactiva solo, y la enumeración va en otro hilo.
- Ventanas en escritorios a pantalla completa: figuran como fuera de pantalla pero se activan igual.
- Activación cooperativa en macOS 14+: si `NSRunningApplication.activate` fuera rechazado, queda `AXFrontmost`, que va por dentro de la app destino.
- Permiso de Accesibilidad atado a la firma: con firma ad hoc se pierde en cada build. Solución: certificado autofirmado (ver README).
