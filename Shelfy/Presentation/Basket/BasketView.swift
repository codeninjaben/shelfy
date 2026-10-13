import SwiftUI

/// The basket's content, shared by the edge panel and the menu-bar popover. The surface
/// behind it (glass in the edge panel, the popover's own material) is drawn by the host.
struct BasketView: View {
    enum Chrome: Equatable {
        case edge(ScreenEdge)
        case popover
    }

    @Bindable var model: BasketViewModel
    let chrome: Chrome
    @Environment(SystemAccessibility.self) private var accessibility

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: BasketMetrics.headerHeight)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
                .frame(height: model.showsFooter ? BasketMetrics.footerHeight : BasketMetrics.bareFooterHeight)
        }
        .contentShape(Rectangle())
        .contextMenu { backgroundMenu }
        .animation(contentAnimation, value: model.items.map(\.id))
        .animation(contentAnimation, value: model.effectiveMode)
        .animation(contentAnimation, value: model.collection.canUndoClear)
        .animation(contentAnimation, value: model.collection.canPutBack)
        .animation(contentAnimation, value: model.collection.notice)
    }

    private var contentAnimation: Animation? {
        accessibility.reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.86)
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        switch chrome {
        case .edge(let edge):
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.primary.opacity(0.2))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .frame(width: 96, height: 22, alignment: .top)
                    .overlay(RepositionHandle(model: model))
                    .help("Drag to move the tab along the edge")
                    .accessibilityHidden(true)
                HStack {
                    GlyphButton(symbol: "xmark", label: "Clear Shelf") { model.clearAll() }
                        .opacity(model.items.isEmpty ? 0 : 1)
                        .disabled(model.items.isEmpty)
                    Spacer()
                    GlyphButton(symbol: edge == .right ? "chevron.right" : "chevron.left", label: "Tuck Away") {
                        model.collapse()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)
            }
        case .popover:
            HStack(spacing: 8) {
                Text("Downloads")
                    .font(.system(size: 13, weight: .semibold))
                if !model.items.isEmpty {
                    Text("\(model.items.count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .frame(height: 17)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                Spacer()
                Menu {
                    backgroundMenu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                        .contentShape(Circle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
                .accessibilityLabel("More")
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if model.app.folder.status != .available {
            AccessProblemView(folder: model.app.folder)
                .transition(.opacity)
        } else if model.items.isEmpty {
            EmptyBasketView(folderName: model.app.folder.displayName)
                .transition(.opacity)
        } else if model.effectiveMode == .grid {
            BasketGrid(model: model)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else if model.items.count == 1, let item = model.items.first {
            SingleItemView(model: model, item: item)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            StackView(model: model)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if let notice = model.collection.notice {
            SummaryCapsule(title: notice == .trashFailed ? "Couldn’t Move to Trash" : "Couldn’t Put Back",
                           symbol: "exclamationmark.triangle", trailing: nil)
                .transition(.opacity)
        } else if model.collection.canPutBack {
            SummaryCapsule(title: "Put Back", symbol: "arrow.uturn.backward", trailing: nil) {
                model.putBack()
            }
            .accessibilityHint("Moves the file back out of the Trash")
            .transition(.opacity)
        } else if model.collection.canUndoClear && model.items.isEmpty {
            SummaryCapsule(title: "Undo Clear", symbol: "arrow.uturn.backward", trailing: nil) {
                model.undoClear()
            }
            .transition(.opacity)
        } else if !model.items.isEmpty {
            let expandable = model.items.count > 1
            SummaryCapsule(title: model.summary, symbol: nil,
                           trailing: expandable ? (model.effectiveMode == .grid ? .collapse : .expand) : nil,
                           action: expandable ? { model.toggleMode() } : nil)
                .accessibilityHint(expandable ? (model.effectiveMode == .grid ? "Shows the stack" : "Shows every file") : "")
        } else {
            Color.clear
        }
    }

    // MARK: Menus

    @ViewBuilder
    private var backgroundMenu: some View {
        Button("Clear Shelf", systemImage: "xmark.circle") { model.clearAll() }
            .disabled(model.items.isEmpty)
        if model.collection.canPutBack {
            Button("Put Back", systemImage: "arrow.uturn.backward") { model.putBack() }
        }
        if model.collection.canUndoClear {
            Button("Undo Clear", systemImage: "arrow.uturn.backward") { model.undoClear() }
        }
        Button("Open \(model.app.folder.displayName)", systemImage: "folder") { model.openWatchedFolder() }
        Divider()
        Button("Settings…", systemImage: "gearshape") { model.app.openSettings() }
        Button("Quit Shelfy", systemImage: "power") { NSApp.terminate(nil) }
    }
}

// MARK: - Single item

private struct SingleItemView: View {
    let model: BasketViewModel
    let item: BasketItem
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 12) {
            ItemThumbnail(item: item, side: BasketMetrics.heroSide, style: .hero)
                .frame(width: BasketMetrics.heroSide + 16, height: BasketMetrics.heroSide)
                .overlay {
                    FileDragSource(model: model, anchorID: item.id, role: .single) { hovering in
                        withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
                    }
                }
                .overlay {
                    if isHovering {
                        ItemCornerActions(model: model, item: item, size: 18)
                    }
                }
                .accessibilityHidden(true)
            VStack(spacing: 3) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.detailText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 22)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.detailText)
        .accessibilityHint("Drag to use the file. Double-click to open.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.open([item]) }
        .accessibilityAction(named: "Quick Look") { model.quickLook([item]) }
        .accessibilityAction(named: "Show in Finder") { model.reveal([item]) }
        .accessibilityAction(named: "Remove from Shelf") { model.remove([item]) }
        .accessibilityAction(named: "Move to Trash") { model.moveToTrash([item]) }
    }
}

// MARK: - Stack

private struct StackView: View {
    let model: BasketViewModel

    private static let rotations: [Double] = [0, -8, 7]
    private static let offsets: [CGSize] = [.zero, CGSize(width: -16, height: 5), CGSize(width: 16, height: 7)]

    var body: some View {
        let top = Array(model.items.prefix(3))
        VStack(spacing: 12) {
            ZStack {
                ForEach(Array(top.enumerated()).reversed(), id: \.element.id) { index, item in
                    ItemThumbnail(item: item, side: BasketMetrics.stackSide, style: .stack)
                        .scaleEffect(index == 0 ? 1 : 0.9)
                        .rotationEffect(.degrees(Self.rotations[index]))
                        .offset(Self.offsets[index])
                }
            }
            .frame(width: 176, height: BasketMetrics.heroSide)
            .overlay { FileDragSource(model: model, anchorID: nil, role: .stack) }
            .accessibilityHidden(true)
            VStack(spacing: 3) {
                Text(top.first?.name ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.items.count == 2 ? "and 1 more" : "and \(model.items.count - 1) more")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.summary): \(top.first?.name ?? "")")
        .accessibilityHint("Drag to use all files. Click to show every file.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.toggleMode() }
    }
}

// MARK: - Grid

private struct BasketGrid: View {
    @Bindable var model: BasketViewModel

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(BasketMetrics.gridCellWidth), spacing: BasketMetrics.gridSpacing),
                            count: BasketMetrics.gridColumns)
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: BasketMetrics.gridSpacing) {
                ForEach(model.items) { item in
                    GridCell(model: model, item: item, isSelected: model.selection.contains(item.id))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, BasketMetrics.gridHorizontalPadding)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.automatic)
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct GridCell: View {
    let model: BasketViewModel
    let item: BasketItem
    let isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 5) {
            ItemThumbnail(item: item, side: BasketMetrics.gridThumbnailSide, style: .grid)
                .frame(width: 64, height: 60)
            Text(item.name)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 72, height: 28, alignment: .top)
        }
        .padding(.top, 6)
        .frame(width: BasketMetrics.gridCellWidth, height: BasketMetrics.gridCellHeight, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.24) : Color.primary.opacity(isHovering ? 0.07 : 0))
        }
        .overlay {
            FileDragSource(model: model, anchorID: item.id, role: .cell) { hovering in
                withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
            }
        }
        .overlay {
            if isHovering {
                ItemCornerActions(model: model, item: item, size: 15)
                    .padding(2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.detailText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.open([item]) }
        .accessibilityAction(named: "Quick Look") { model.quickLook([item]) }
        .accessibilityAction(named: "Show in Finder") { model.reveal([item]) }
        .accessibilityAction(named: "Remove from Shelf") { model.remove([item]) }
        .accessibilityAction(named: "Move to Trash") { model.moveToTrash([item]) }
    }
}

/// Hover controls on a file: take it off the shelf (top left) or move the file itself to the
/// Trash (top right), kept in opposite corners so one is never mistaken for the other.
private struct ItemCornerActions: View {
    let model: BasketViewModel
    let item: BasketItem
    let size: CGFloat

    var body: some View {
        HStack(alignment: .top) {
            CornerButton(symbol: "xmark.circle.fill", label: "Remove from Shelf", size: size) {
                model.remove([item])
            }
            Spacer(minLength: 0)
            CornerButton(symbol: "trash.circle.fill", label: "Move to Trash", size: size, isDestructive: true) {
                model.moveToTrash([item])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity)
    }
}

private struct CornerButton: View {
    let symbol: String
    let label: String
    let size: CGFloat
    var isDestructive = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, circleColor)
                .font(.system(size: size))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onActiveHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(label)
        .accessibilityLabel(label)
    }

    private var circleColor: Color {
        guard isHovering else { return Color.black.opacity(0.55) }
        return isDestructive ? Color.red : Color.black.opacity(0.75)
    }
}

// MARK: - Thumbnail

struct ItemThumbnail: View {
    enum Style { case hero, stack, grid }

    let item: BasketItem
    let side: CGFloat
    let style: Style
    @Environment(\.displayScale) private var scale
    @State private var loaded: Thumbnail?

    private struct LoadKey: Hashable {
        let id: UUID
        let modified: Date?
        let side: CGFloat
    }

    var body: some View {
        let provider = ThumbnailProvider.shared
        let thumbnail = loaded ?? provider.cachedThumbnail(for: item, side: side, scale: scale)
            ?? provider.iconThumbnail(for: item)
        image(for: thumbnail)
            .frame(width: side, height: side)
            .opacity(item.isReadable ? 1 : 0.45)
            .overlay(alignment: .bottomTrailing) {
                if !item.isReadable {
                    Image(systemName: "lock.fill")
                        .font(.system(size: style == .grid ? 10 : 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
            }
            .task(id: LoadKey(id: item.id, modified: item.modifiedAt, side: side)) {
                guard item.isReadable else { return }
                if let fresh = await provider.thumbnail(for: item, side: side, scale: scale) {
                    loaded = fresh
                }
            }
    }

    @ViewBuilder
    private func image(for thumbnail: Thumbnail) -> some View {
        if thumbnail.isIcon {
            Image(nsImage: thumbnail.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: side * 0.94, height: side * 0.94)
        } else {
            let radius: CGFloat = style == .grid ? 6 : 10
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            Image(nsImage: thumbnail.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(style == .grid ? 0.12 : 0.2),
                        radius: style == .grid ? 2.5 : 7, y: style == .grid ? 1 : 3)
        }
    }
}

// MARK: - Empty and problem states

private struct EmptyBasketView: View {
    let folderName: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "tray")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            Text("Nothing on the Shelf")
                .font(.system(size: 13, weight: .semibold))
            Text("New files in \(folderName) will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

private struct AccessProblemView: View {
    let folder: WatchedFolder

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(folder.status == .missing ? "\(folder.displayName) Is Missing" : "Can’t Read \(folder.displayName)")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Button("Choose Folder…") { folder.chooseFolder() }
                .controlSize(.small)
                .buttonStyle(.glass)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Controls

/// A quiet circular control for the basket's top corners.
struct GlyphButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(isHovering ? 0.12 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onActiveHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The small capsule at the bottom of the basket: "1 Image", "3 Files ›".
struct SummaryCapsule: View {
    enum Trailing { case expand, collapse }

    let title: String
    let symbol: String?
    let trailing: Trailing?
    var action: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        let label = HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let trailing {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(trailing == .collapse ? 90 : 0))
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 28)
        .background(Capsule().fill(Color.primary.opacity(isHovering && action != nil ? 0.12 : 0.065)))
        .contentShape(Capsule())

        Group {
            if let action {
                Button(action: action) { label }
                    .buttonStyle(.plain)
                    .onActiveHover { hovering in
                        withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
                    }
            } else {
                label
            }
        }
        .accessibilityElement(children: .combine)
    }
}
