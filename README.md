# AltPlus

Conmutador de ventanas libre y mínimo para macOS. Dos atajos:

| Atajo | Qué muestra |
|---|---|
| `⌥ ⇥` | Las ventanas del escritorio actual |
| `⌥ ⌃ ⇥` | Las ventanas de todos los escritorios |

Mantén el modificador, pulsa `⇥` para avanzar y suelta para cambiar a la ventana elegida. Es como `⌘ ⇥`, pero por ventana y con filtro por escritorio. Los atajos se cambian en Preferencias.

AltPlus se escribió desde cero. Solo es obligatorio el permiso de Accesibilidad; las miniaturas, opcionales, piden además Grabación de pantalla. No tiene funciones de pago ni las va a tener. Licencia GPL-3.0.

## Funciones

- Ventanas en orden de uso reciente, con ícono, título y miniatura opcional.
- Modo "este escritorio" y modo "todos los escritorios", incluidos los escritorios que no visitaste desde que abriste AltPlus. Las ventanas de otro escritorio, minimizadas o de apps ocultas llevan una marca.
- Agrupar por aplicación, para ver un ítem por app.
- Incluir o no las ventanas minimizadas y las de apps ocultas, y mandar las minimizadas al final de la lista. Estos interruptores están en Preferencias y en el menú de la barra.
- Minimizar, cerrar una ventana o salir de su app desde el panel, con el mouse o con el teclado.
- Funciona sobre apps a pantalla completa y con varios monitores. El panel aparece en el monitor donde está el puntero.
- Arranque al iniciar sesión, en español o inglés según el idioma del sistema.

## Uso

Con el panel abierto y el modificador apretado:

| Tecla | Acción |
|---|---|
| `⇥` o la tecla del atajo | Siguiente ventana |
| `⇧ ⇥` | Ventana anterior |
| Flechas | Moverse por la grilla |
| Soltar el modificador, `↩` o clic | Cambiar a la ventana elegida |
| `⎋` | Cancelar |
| `M` | Minimizar la ventana elegida |
| `W` | Cerrar la ventana elegida |
| `Q` | Salir de su aplicación |
| `H` | Ocultar su aplicación |

Al pasar el mouse por una ventana aparecen botones para minimizarla, cerrarla o salir de su app.

## Instalar

Hay tres maneras. Las tres dejan la app en Aplicaciones.

**1. Script de instalación, la recomendada.** Descarga la última versión desde GitHub Releases, verifica su suma SHA-256, la copia a Aplicaciones, le quita la cuarentena y la abre. No pide contraseña. Para actualizar, se usa el mismo comando.

```bash
curl -fsSL https://raw.githubusercontent.com/guillermoleale/altplus/main/install.sh | bash
```

**2. Homebrew.** El cask vive en este mismo repositorio. Se instala con el nombre completo porque Homebrew 6 y posteriores solo cargan casks de terceros en los que confiaste; así se confía solo en este.

```bash
brew tap guillermoleale/altplus https://github.com/guillermoleale/altplus
brew install --cask guillermoleale/altplus/altplus
```

Para actualizar, `brew upgrade --cask altplus`. Para desinstalar, `brew uninstall --cask altplus`.

**3. A mano.** Descarga `AltPlus-x.y.z.dmg` o `.zip` desde [Releases](https://github.com/guillermoleale/altplus/releases), arrastra AltPlus a Aplicaciones y ábrela. La primera vez macOS la bloquea con "Apple no pudo verificar que AltPlus no contiene software malicioso". Para abrirla, ve a Ajustes del Sistema › Privacidad y seguridad, baja hasta el aviso sobre AltPlus y pulsa "Abrir de todos modos". Solo hace falta una vez.

### Permisos

Al primer arranque AltPlus pide el permiso de Accesibilidad y espera a que lo actives en Ajustes del Sistema › Privacidad y seguridad › Accesibilidad. Sirve para ver las ventanas de las demás apps, traerlas al frente y capturar el atajo.

Para ver miniaturas, activa "Mostrar miniaturas de las ventanas" en Preferencias y concede Grabación de pantalla cuando macOS lo pida. macOS aplica ese permiso al volver a abrir la app. Desde macOS 15 el sistema recuerda cada tanto que la app puede ver la pantalla: es un aviso de macOS, no de AltPlus.

### Por qué no está notarizada

Notarizar exige una cuenta de desarrollador de Apple de pago anual, y AltPlus es software libre sin fines de lucro. Las releases se firman con un certificado propio del proyecto. Eso no quita el aviso de Gatekeeper, pero hace que los permisos se conserven al actualizar.

## Compilar desde el código

Hace falta macOS 14 o posterior y las Command Line Tools de Xcode (`xcode-select --install`). No hace falta Xcode.

```bash
git clone https://github.com/guillermoleale/altplus.git
cd altplus
scripts/build-app.sh
open build/AltPlus.app
```

`ALTPLUS_UNIVERSAL=1 scripts/build-app.sh` compila para Apple Silicon e Intel. `scripts/package.sh` genera después el zip, el dmg y las sumas en `build/dist/`.

### Para desarrollar

macOS ata los permisos a la firma del binario. Con la firma ad hoc por defecto, cada compilación es "otra app" y hay que volver a conceder Accesibilidad. Crea una vez un certificado de desarrollo y compila con él:

```bash
scripts/make-dev-cert.sh
ALTPLUS_SIGN_IDENTITY="AltPlus Dev" scripts/build-app.sh
```

Para depurar, el menú de la barra tiene "Guardar diagnóstico…", que escribe en `~/Library/Logs/AltPlus/` la lista de ventanas tal como la ve AltPlus. Con la app abierta, `kill -USR1 $(pgrep -x AltPlus)` guarda el mismo informe. `build/AltPlus.app/Contents/MacOS/AltPlus --diagnostics` lo imprime desde un proceso nuevo, incluida la búsqueda en escritorios no visitados; ejecutado desde la terminal, es la terminal la que necesita el permiso de Accesibilidad.

### Publicar una versión

1. Una sola vez, `scripts/setup-release-signing.sh` crea el certificado "AltPlus Release" y lo carga como secrets del repositorio con `gh`. Sin esos secrets, la release se firma ad hoc y quien actualice tendrá que conceder los permisos de nuevo.
2. `scripts/release.sh 0.2.0` actualiza la versión en `Resources/Info.plist`, crea el commit y la etiqueta `v0.2.0`, y los empuja.
3. GitHub Actions compila para Apple Silicon e Intel, firma, genera el zip, el dmg y `SHA256SUMS.txt`, publica la release y actualiza `Casks/altplus.rb` en `main`.

## Cómo funciona

- Un event tap de CoreGraphics captura los atajos y las teclas mientras el panel está abierto.
- La lista combina dos fuentes. `CGWindowListCopyWindowInfo` ve las ventanas de todos los escritorios y dice cuáles están en pantalla. La API de Accesibilidad aporta títulos, el tipo de ventana, el estado minimizado y la posibilidad de traerlas al frente.
- Accesibilidad solo entrega las ventanas del escritorio visible. Una referencia obtenida mientras la ventana estaba a la vista sigue sirviendo después, así que AltPlus las registra a medida que las ve. Para las ventanas de escritorios no visitados, busca en segundo plano sus referencias con `_AXUIElementCreateWithRemoteToken`: al arrancar, al abrirse una app, al cambiar de escritorio y cuando aparece una ventana desconocida.
- El orden de uso reciente sale de notificaciones de Accesibilidad: ventana enfocada y app activada.
- Las miniaturas se capturan con ScreenCaptureKit en segundo plano. El panel aparece primero con íconos y las miniaturas van llegando.
- Para activar una ventana, Accesibilidad la levanta y pone su app al frente. Si está en otro escritorio, macOS cambia de escritorio solo, siempre que esté activa la opción de Mission Control "Al cambiar a una aplicación, cambiar a un espacio con ventanas abiertas de la aplicación", que viene activada.
- AltPlus usa dos funciones no documentadas de Accesibilidad, aisladas en `PrivateAX.swift` y resueltas al arrancar. `_AXUIElementGetWindow` cruza las dos listas de ventanas. `_AXUIElementCreateWithRemoteToken` encuentra ventanas de escritorios no visitados. Si Apple quitara alguna, AltPlus sigue funcionando: sin la segunda, las ventanas de otro escritorio aparecen después de visitarlo una vez.

## Limitaciones conocidas

- Recién abierto, AltPlus tarda unos segundos en encontrar las ventanas de los demás escritorios.
- macOS no dice en qué escritorio está una ventana minimizada. Por eso, si incluyes las minimizadas, aparecen en los dos modos.
- Una ventana minimizada o en otro escritorio muestra la última miniatura capturada, o el ícono si nunca se capturó.
- No reemplaza a `⌘ ⇥`.

## Licencia

GPL-3.0-or-later. Ver `LICENSE`.

---

## English

AltPlus is a small, free window switcher for macOS. `⌥ ⇥` cycles the windows on the current desktop and `⌥ ⌃ ⇥` cycles the windows on all desktops, including desktops you have not visited yet. Hold the modifier, press `⇥` to move forward and `⇧ ⇥` to go back, then release to switch. While the panel is open, `M`, `W`, `Q` and `H` minimize, close, quit or hide. Shortcuts are configurable. It needs the Accessibility permission; optional thumbnails also need Screen Recording. GPL-3.0.

Install with:

```bash
curl -fsSL https://raw.githubusercontent.com/guillermoleale/altplus/main/install.sh | bash
```

Or build it with `scripts/build-app.sh`. Command Line Tools are enough; Xcode is not needed.
