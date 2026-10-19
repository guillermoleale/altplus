import SwiftUI

struct SwitcherItem: Identifiable {
    let id: Int
    let window: WindowInfo
    /// Mayor que 1 cuando se agrupa por app y la app tiene varias ventanas.
    let windowCount: Int
}

/// Medidas del panel según las opciones activas.
struct SwitcherLayout: Equatable {
    var showTitles = true
    var showThumbnails = false

    static let thumbnailSize = CGSize(width: 160, height: 100)
    static let iconSize: CGFloat = 64
    static let spacing: CGFloat = 6
    static let padding: CGFloat = 14
    static let headerHeight: CGFloat = 18
    static let headerGap: CGFloat = 8

    var itemWidth: CGFloat { showThumbnails ? 176 : 112 }

    var itemHeight: CGFloat {
        let visual = showThumbnails ? Self.thumbnailSize.height : Self.iconSize
        let text: CGFloat = showTitles ? 46 : 16
        return visual + 6 + text + 16
    }

    func columns(fitting screenWidth: CGFloat) -> Int {
        let usable = screenWidth * 0.9 - Self.padding * 2
        return max(1, Int((usable + Self.spacing) / (itemWidth + Self.spacing)))
    }

    func size(items: Int, columns: Int) -> CGSize {
        let count = max(items, 1)
        let cols = max(1, min(columns, count))
        let rows = Int(ceil(Double(count) / Double(cols)))
        let width = CGFloat(cols) * itemWidth + CGFloat(cols - 1) * Self.spacing + Self.padding * 2
        let height = Self.headerHeight + Self.headerGap
            + CGFloat(rows) * itemHeight + CGFloat(rows - 1) * Self.spacing
            + Self.padding * 2
        return CGSize(width: width, height: height)
    }
}

/// Estado observable del panel.
final class SwitcherModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var selectedIndex: Int = 0
    @Published var mode: SwitcherMode = .sameDesktop
    @Published var columns: Int = 1
    @Published var layout = SwitcherLayout()
    @Published var thumbnails: [CGWindowID: NSImage] = [:]

    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?
    var onAction: ((Int, WindowAction) -> Void)?

    var rows: [[SwitcherItem]] {
        let cols = max(columns, 1)
        return stride(from: 0, to: items.count, by: cols).map { start in
            Array(items[start ..< min(start + cols, items.count)])
        }
    }

    func thumbnail(for item: SwitcherItem) -> NSImage? {
        guard let id = item.window.windowID else { return nil }
        return thumbnails[id]
    }
}
