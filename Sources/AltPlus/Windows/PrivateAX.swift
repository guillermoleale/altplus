import ApplicationServices
import Darwin

/// Las dos funciones no documentadas que usa AltPlus, resueltas en tiempo de ejecución con `dlsym`.
/// Si alguna desaparece en una versión futura de macOS, AltPlus sigue funcionando con menos alcance.
///
/// - `_AXUIElementGetWindow` devuelve el CGWindowID de una ventana AX. Permite cruzar sin ambigüedad
///   la lista de Accesibilidad con la de CGWindowList. Sin ella, el enumerador empareja por proceso
///   y marco de ventana.
/// - `_AXUIElementCreateWithRemoteToken` construye una referencia AX a partir de un identificador de
///   elemento de otra app. Accesibilidad solo entrega las ventanas del escritorio visible; con esta
///   función se obtienen las de los escritorios que no se visitaron (ver `RemoteWindowResolver`).
///   Sin ella, esas ventanas aparecen recién después de visitar su escritorio.
///
/// Ambas las usan desde hace años gestores de ventanas como yabai y Hammerspoon.
enum PrivateAX {
    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias CreateWithRemoteTokenFunction = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) // RTLD_DEFAULT
    }

    private static let getWindow: GetWindowFunction? = {
        symbol("_AXUIElementGetWindow").map { unsafeBitCast($0, to: GetWindowFunction.self) }
    }()

    private static let createWithRemoteToken: CreateWithRemoteTokenFunction? = {
        symbol("_AXUIElementCreateWithRemoteToken").map { unsafeBitCast($0, to: CreateWithRemoteTokenFunction.self) }
    }()

    static var isAvailable: Bool { getWindow != nil }

    /// `true` si se pueden buscar ventanas de escritorios no visitados.
    static var canResolveRemoteWindows: Bool { getWindow != nil && createWithRemoteToken != nil }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        let (id, _) = lookupWindowID(of: element)
        return id
    }

    /// Como `windowID(of:)`, pero devuelve también el error para distinguir "no es una ventana"
    /// de "la app no responde".
    static func lookupWindowID(of element: AXUIElement) -> (CGWindowID?, AXError) {
        guard let getWindow else { return (nil, .apiDisabled) }
        var id: CGWindowID = 0
        let error = getWindow(element, &id)
        return (error == .success && id != 0 ? id : nil, error)
    }

    /// Referencia al elemento `elementID` de la app `pid`. El token es de 20 bytes: pid (32 bits),
    /// cero (32 bits), la marca 0x636f636f (32 bits) y el identificador del elemento (64 bits).
    /// Crear la referencia no consulta a la app; recién la primera consulta dice si el elemento existe.
    static func element(pid: pid_t, remoteElementID elementID: UInt64) -> AXUIElement? {
        guard let createWithRemoteToken else { return nil }
        var token = Data(count: 20)
        token.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: Int32(pid).littleEndian, toByteOffset: 0, as: Int32.self)
            raw.storeBytes(of: Int32(0), toByteOffset: 4, as: Int32.self)
            raw.storeBytes(of: Int32(0x636f636f).littleEndian, toByteOffset: 8, as: Int32.self)
            raw.storeBytes(of: elementID.littleEndian, toByteOffset: 12, as: UInt64.self)
        }
        return createWithRemoteToken(token as CFData)?.takeRetainedValue()
    }
}
