import SwiftUI

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        VStack(spacing: SwitcherLayout.headerGap) {
            Text(headerText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(height: SwitcherLayout.headerHeight)

            if model.items.isEmpty {
                Text(tr("No hay ventanas", "No windows"))
                    .foregroundStyle(.secondary)
                    .frame(width: model.layout.itemWidth, height: model.layout.itemHeight)
            } else {
                // Si hay más filas de las que entran en la pantalla, el panel se limita y la grilla se desplaza
                // para mantener visible la selección.
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: SwitcherLayout.spacing) {
                            ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: SwitcherLayout.spacing) {
                                    ForEach(row) { item in
                                        SwitcherItemView(
                                            item: item,
                                            selected: item.id == model.selectedIndex,
                                            layout: model.layout,
                                            thumbnail: model.thumbnail(for: item),
                                            onHover: { inside in if inside { model.onHover?(item.id) } },
                                            onClick: { model.onClick?(item.id) },
                                            onAction: { action in model.onAction?(item.id, action) }
                                        )
                                        .id(item.id)
                                    }
                                }
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: model.selectedIndex) { _, index in proxy.scrollTo(index) }
                    .onReceive(model.$items) { _ in
                        // Al abrir o recargar, la selección se fija después de la lista.
                        DispatchQueue.main.async { proxy.scrollTo(model.selectedIndex) }
                    }
                }
            }
        }
        .padding(SwitcherLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var headerText: String {
        switch model.mode {
        case .sameDesktop: return tr("Este escritorio", "This desktop")
        case .allDesktops: return tr("Todos los escritorios", "All desktops")
        }
    }
}

struct SwitcherItemView: View {
    let item: SwitcherItem
    let selected: Bool
    let layout: SwitcherLayout
    let thumbnail: NSImage?
    let onHover: (Bool) -> Void
    let onClick: () -> Void
    let onAction: (WindowAction) -> Void

    @State private var hovered = false

    var body: some View {
        VStack(spacing: 6) {
            visual
            texts
        }
        .padding(.horizontal, 4)
        .frame(width: layout.itemWidth, height: layout.itemHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.16) : Color.clear)
        )
        .overlay(alignment: .topTrailing) {
            if hovered { actionBar.padding(5) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClick)
        .onHover { inside in
            hovered = inside
            onHover(inside)
        }
    }

    // MARK: - Partes

    @ViewBuilder
    private var visual: some View {
        if layout.showThumbnails {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: SwitcherLayout.thumbnailSize.width - 4,
                               height: SwitcherLayout.thumbnailSize.height - 4)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    appIcon(size: 44)
                }
            }
            .frame(width: SwitcherLayout.thumbnailSize.width, height: SwitcherLayout.thumbnailSize.height)
            .overlay(alignment: .bottomLeading) {
                if thumbnail != nil {
                    appIcon(size: 28).shadow(radius: 2).offset(x: -6, y: 6)
                }
            }
            .overlay(alignment: .bottomTrailing) { badgeView.offset(x: 6, y: 6) }
        } else {
            appIcon(size: SwitcherLayout.iconSize)
                .overlay(alignment: .bottomTrailing) { badgeView.offset(x: 4, y: 4) }
        }
    }

    @ViewBuilder
    private var texts: some View {
        if layout.showTitles {
            Text(item.window.displayTitle)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)
                .frame(height: 28, alignment: .top)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text(subtitle)
                .font(.system(size: 10))
                .lineLimit(1)
        }
    }

    private func appIcon(size: CGFloat) -> some View {
        Image(nsImage: item.window.app.icon ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            Image(systemName: badge)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 2) {
            actionButton("minus.circle.fill", tr("Minimizar (M)", "Minimize (M)")) { onAction(.minimize) }
            actionButton("xmark.circle.fill", tr("Cerrar ventana (W)", "Close window (W)")) { onAction(.close) }
            actionButton("power.circle.fill", tr("Salir de la aplicación (Q)", "Quit application (Q)")) { onAction(.quit) }
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
    }

    private func actionButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var badge: String? {
        if item.window.isMinimized { return "minus.circle.fill" }
        if item.window.isHiddenApp { return "eye.slash.circle.fill" }
        if item.window.isOnOtherDesktop { return "rectangle.on.rectangle.circle.fill" }
        return nil
    }

    private var subtitle: String {
        if item.windowCount > 1 {
            return tr("\(item.window.appName) · \(item.windowCount) ventanas", "\(item.window.appName) · \(item.windowCount) windows")
        }
        return item.window.appName
    }
}
