import Combine
import Foundation

/// Preferencias persistidas en UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let sameDesktop = "shortcut.sameDesktop"
        static let allDesktops = "shortcut.allDesktops"
        static let groupByApp = "list.groupByApp"
        static let showMinimized = "list.showMinimized"
        static let minimizedLast = "list.minimizedLast"
        static let showHiddenApps = "list.showHiddenApps"
        static let showTitles = "list.showTitles"
        static let showThumbnails = "list.showThumbnails"
        static let ignoredBundleIDs = "list.ignoredBundleIDs"
    }

    private let defaults = UserDefaults.standard

    @Published var sameDesktopShortcut: Shortcut { didSet { store(sameDesktopShortcut, key: Key.sameDesktop) } }
    @Published var allDesktopsShortcut: Shortcut { didSet { store(allDesktopsShortcut, key: Key.allDesktops) } }
    @Published var groupByApp: Bool { didSet { defaults.set(groupByApp, forKey: Key.groupByApp) } }
    @Published var showMinimized: Bool { didSet { defaults.set(showMinimized, forKey: Key.showMinimized) } }
    @Published var minimizedLast: Bool { didSet { defaults.set(minimizedLast, forKey: Key.minimizedLast) } }
    @Published var showHiddenApps: Bool { didSet { defaults.set(showHiddenApps, forKey: Key.showHiddenApps) } }
    @Published var showTitles: Bool { didSet { defaults.set(showTitles, forKey: Key.showTitles) } }
    @Published var showThumbnails: Bool { didSet { defaults.set(showThumbnails, forKey: Key.showThumbnails) } }
    @Published var ignoredBundleIDs: [String] { didSet { defaults.set(ignoredBundleIDs, forKey: Key.ignoredBundleIDs) } }

    private init() {
        sameDesktopShortcut = Preferences.load(Key.sameDesktop) ?? .defaultSameDesktop
        allDesktopsShortcut = Preferences.load(Key.allDesktops) ?? .defaultAllDesktops
        groupByApp = defaults.object(forKey: Key.groupByApp) as? Bool ?? false
        showMinimized = defaults.object(forKey: Key.showMinimized) as? Bool ?? true
        minimizedLast = defaults.object(forKey: Key.minimizedLast) as? Bool ?? false
        showHiddenApps = defaults.object(forKey: Key.showHiddenApps) as? Bool ?? true
        showTitles = defaults.object(forKey: Key.showTitles) as? Bool ?? true
        showThumbnails = defaults.object(forKey: Key.showThumbnails) as? Bool ?? false
        ignoredBundleIDs = defaults.stringArray(forKey: Key.ignoredBundleIDs) ?? []
    }

    var shortcutsByMode: [SwitcherMode: Shortcut] {
        [.sameDesktop: sameDesktopShortcut, .allDesktops: allDesktopsShortcut]
    }

    private func store(_ shortcut: Shortcut, key: String) {
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load(_ key: String) -> Shortcut? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data) else { return nil }
        // Un atajo sin modificadores secuestraría una tecla en todo el sistema: se ignora y vale el de fábrica.
        return shortcut.isValid ? shortcut : nil
    }
}
