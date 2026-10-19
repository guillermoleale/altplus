import AppKit
import ApplicationServices

/// Envoltorios finos sobre la API de Accesibilidad (AX).
enum AX {
    /// Tiempo máximo de espera por llamada AX. El de macOS es de 6 segundos: una app colgada bloquearía todo.
    static let messagingTimeout: Float = 0.3

    /// Fija el timeout para todos los elementos AX del proceso. El timeout de un elemento no lo heredan
    /// los que se obtienen a partir de él (ventanas, botones, los que llegan en notificaciones), así que
    /// hay que fijarlo en el elemento de todo el sistema. Llamar una vez al arrancar.
    static func configureGlobalTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
    }

    static func application(pid: pid_t, timeout: Float = messagingTimeout) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return error == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        guard let value = copy(element, attribute) else { return nil }
        if let b = value as? Bool { return b }
        return (value as? NSNumber)?.boolValue
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        elementsIfAvailable(element, attribute) ?? []
    }

    /// `nil` si la app no respondió (timeout, sin permiso); `[]` si respondió que no tiene elementos.
    static func elementsIfAvailable(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == CFArrayGetTypeID() else { return nil }
        let array = value as! NSArray
        var result: [AXUIElement] = []
        result.reserveCapacity(array.count)
        for item in array {
            let object = item as AnyObject
            if CFGetTypeID(object) == AXUIElementGetTypeID() {
                result.append(object as! AXUIElement)
            }
        }
        return result
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }

    /// Marco de la ventana en coordenadas de pantalla con origen arriba a la izquierda
    /// (el mismo sistema que usa CGWindowList).
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute),
              let size = size(window, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }
}

/// Identidad estable de un elemento AX para usarlo como clave de diccionario.
/// Dos referencias a la misma ventana son `CFEqual` aunque se hayan obtenido por caminos distintos.
struct AXElementKey: Hashable {
    let element: AXUIElement

    init(_ element: AXUIElement) { self.element = element }

    static func == (lhs: AXElementKey, rhs: AXElementKey) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}
