// Genera el ícono de la app (PNG de 1024x1024) sin recursos binarios en el repo.
// Uso: swift scripts/make-icon.swift salida.png
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Fondo: cuadrado redondeado con degradado, con el margen que usa macOS.
let inset = size * 0.09
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let background = NSBezierPath(roundedRect: rect, xRadius: size * 0.2, yRadius: size * 0.2)
let gradient = NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.98, alpha: 1),
                          ending: NSColor(calibratedRed: 0.42, green: 0.20, blue: 0.88, alpha: 1))!
gradient.draw(in: background, angle: -65)

// Dos ventanas superpuestas.
func window(_ r: NSRect, alpha: CGFloat) {
    let path = NSBezierPath(roundedRect: r, xRadius: size * 0.04, yRadius: size * 0.04)
    NSColor(calibratedWhite: 1, alpha: alpha).setFill()
    path.fill()
    let bar = NSRect(x: r.minX, y: r.maxY - size * 0.07, width: r.width, height: size * 0.07)
    let barPath = NSBezierPath(roundedRect: bar, xRadius: size * 0.04, yRadius: size * 0.04)
    NSColor(calibratedWhite: 1, alpha: min(1, alpha + 0.25)).setFill()
    barPath.fill()
}
window(NSRect(x: size * 0.22, y: size * 0.32, width: size * 0.42, height: size * 0.34), alpha: 0.35)
window(NSRect(x: size * 0.36, y: size * 0.22, width: size * 0.42, height: size * 0.34), alpha: 0.9)

// Glifo ⌥ arriba a la derecha.
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: size * 0.24, weight: .heavy),
    .foregroundColor: NSColor.white,
]
let glyph = NSAttributedString(string: "⌥", attributes: attributes)
let glyphSize = glyph.size()
glyph.draw(at: NSPoint(x: size * 0.78 - glyphSize.width / 2, y: size * 0.66))

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("No se pudo renderizar el ícono\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: output))
print("Ícono escrito en \(output)")
