import ApplicationServices
import Foundation

/// Busca las referencias AX de ventanas que Accesibilidad no entrega porque están en escritorios
/// que no se visitaron.
///
/// Cada app numera sus elementos AX. Se prueban los identificadores en orden, se pregunta a cada uno
/// su CGWindowID y se guardan los que coinciden con los buscados. Las ventanas reales aparecen pronto
/// (en las pruebas, en menos de 60 ms por app). Lo caro es lo que no existe como ventana: una ventana
/// interna o cerrada obliga a recorrer todo el rango, de medio segundo a unos 4 segundos por app.
/// Por eso esto corre siempre en segundo plano y el registro recuerda lo que no se encontró.
enum RemoteWindowResolver {
    enum Outcome {
        /// Se recorrió todo el rango o se encontró todo lo buscado.
        case complete
        /// Se agotó el tiempo asignado antes de terminar.
        case timeBudgetExceeded
        /// La app no responde por Accesibilidad.
        case unresponsive
    }

    struct Result {
        var found: [CGWindowID: AXUIElement] = [:]
        var outcome: Outcome = .complete
    }

    static let elementIDLimit: UInt64 = 0x7fff

    static func resolve(pid: pid_t, wanted: Set<CGWindowID>, timeBudget: TimeInterval = 5) -> Result {
        var result = Result()
        guard PrivateAX.canResolveRemoteWindows, !wanted.isEmpty else { return result }

        // Una app colgada haría esperar el timeout en cada uno de los miles de intentos.
        if AX.copy(AX.application(pid: pid), kAXRoleAttribute) == nil {
            result.outcome = .unresponsive
            return result
        }

        let deadline = Date().addingTimeInterval(timeBudget)
        var consecutiveTimeouts = 0
        for elementID in UInt64(0) ..< elementIDLimit {
            if elementID % 256 == 0, Date() > deadline {
                result.outcome = .timeBudgetExceeded
                return result
            }
            guard let element = PrivateAX.element(pid: pid, remoteElementID: elementID) else { continue }
            let (windowID, error) = PrivateAX.lookupWindowID(of: element)
            if error == .cannotComplete {
                consecutiveTimeouts += 1
                if consecutiveTimeouts >= 3 {
                    result.outcome = .unresponsive
                    return result
                }
                continue
            }
            consecutiveTimeouts = 0
            guard let windowID, wanted.contains(windowID), result.found[windowID] == nil else { continue }
            result.found[windowID] = element
            if result.found.count == wanted.count { break }
        }
        return result
    }
}
