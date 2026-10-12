import CoreGraphics

/// Fixed metrics shared by the basket views and the window controllers, so a controller can
/// size its window before SwiftUI lays the content out (which keeps the morph seamless).
nonisolated enum BasketMetrics {
    static let cornerRadius: CGFloat = 30
    static let edgeWidth: CGFloat = 244
    static let popoverWidth: CGFloat = 288
    static let gridWidth: CGFloat = 284

    static let headerHeight: CGFloat = 46
    static let footerHeight: CGFloat = 56
    static let bareFooterHeight: CGFloat = 18

    static let heroSide: CGFloat = 132
    static let heroHeight: CGFloat = 184
    static let stackSide: CGFloat = 104
    static let emptyHeight: CGFloat = 132

    static let gridColumns = 3
    static let gridCellWidth: CGFloat = 80
    static let gridCellHeight: CGFloat = 100
    static let gridSpacing: CGFloat = 6
    static let gridHorizontalPadding: CGFloat = 14
    static let gridVisibleRows: CGFloat = 3.4
    static let gridThumbnailSide: CGFloat = 56

    enum Layout: Equatable { case empty, hero, grid(itemCount: Int) }

    static func size(for layout: Layout, surfaceWidth: CGFloat, showsFooter: Bool) -> CGSize {
        let footer = showsFooter ? footerHeight : bareFooterHeight
        switch layout {
        case .empty:
            return CGSize(width: surfaceWidth, height: headerHeight + emptyHeight + footer)
        case .hero:
            return CGSize(width: surfaceWidth, height: headerHeight + heroHeight + footer)
        case .grid(let count):
            let rows = CGFloat((count + gridColumns - 1) / gridColumns)
            let visibleRows = min(rows, gridVisibleRows)
            let body = visibleRows * gridCellHeight + max(0, visibleRows.rounded(.up) - 1) * gridSpacing + 10
            return CGSize(width: max(surfaceWidth, gridWidth), height: headerHeight + body + footer)
        }
    }
}
