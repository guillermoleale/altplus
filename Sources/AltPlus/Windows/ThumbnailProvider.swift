import AppKit
import ScreenCaptureKit

/// Captura miniaturas de ventanas con ScreenCaptureKit y las cachea por CGWindowID.
///
/// Requiere el permiso de Grabación de pantalla. Las capturas corren en segundo plano, de a pocas
/// por vez, y cada miniatura lista se entrega por `onUpdate` en el hilo principal. Una miniatura
/// vieja se muestra hasta que llega la nueva, así el panel aparece sin esperar.
final class ThumbnailProvider {
    static let maxWindows = 40

    private var cache: [CGWindowID: NSImage] = [:]
    private var generation = 0
    private let lock = NSLock()

    func cached(for ids: [CGWindowID]) -> [CGWindowID: NSImage] {
        lock.lock()
        defer { lock.unlock() }
        var result: [CGWindowID: NSImage] = [:]
        for id in ids { if let image = cache[id] { result[id] = image } }
        return result
    }

    func prune(keeping ids: Set<CGWindowID>) {
        lock.lock()
        cache = cache.filter { ids.contains($0.key) }
        lock.unlock()
    }

    /// Invalida las capturas en curso: sus resultados se guardan en caché pero no se notifican.
    func cancel() {
        lock.lock()
        generation += 1
        lock.unlock()
    }

    func refresh(ids: [CGWindowID], targetSize: CGSize, onUpdate: @escaping (CGWindowID, NSImage) -> Void) {
        lock.lock()
        generation += 1
        let myGeneration = generation
        lock.unlock()

        let wanted = Array(ids.prefix(Self.maxWindows))
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let content: SCShareableContent
            do {
                content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            } catch {
                Log.windows.error("ScreenCaptureKit no devolvió ventanas: \(error.localizedDescription, privacy: .public)")
                return
            }
            var byID: [CGWindowID: SCWindow] = [:]
            for window in content.windows { byID[window.windowID] = window }
            // Las miniaturas de ventanas que ya no existen se descartan; si no, la caché crece sin límite.
            self.prune(keeping: Set(byID.keys))

            for chunk in wanted.chunked(into: 4) {
                guard self.isCurrent(myGeneration) else { return }
                await withTaskGroup(of: Void.self) { group in
                    for id in chunk {
                        guard let window = byID[id] else { continue }
                        group.addTask {
                            guard let image = await Self.capture(window, targetSize: targetSize, scale: scale) else { return }
                            self.store(id, image)
                            await MainActor.run {
                                if self.isCurrent(myGeneration) { onUpdate(id, image) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func isCurrent(_ value: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == value
    }

    private func store(_ id: CGWindowID, _ image: NSImage) {
        lock.lock()
        cache[id] = image
        lock.unlock()
    }

    private static func capture(_ window: SCWindow, targetSize: CGSize, scale: CGFloat) async -> NSImage? {
        let frame = window.frame
        guard frame.width > 0, frame.height > 0 else { return nil }
        let fit = min(targetSize.width / frame.width, targetSize.height / frame.height)
        let pixelsPerPoint = min(fit * scale, scale)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(frame.width * pixelsPerPoint))
        configuration.height = max(1, Int(frame.height * pixelsPerPoint))
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .automatic
        let filter = SCContentFilter(desktopIndependentWindow: window)
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
        } catch {
            return nil
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
