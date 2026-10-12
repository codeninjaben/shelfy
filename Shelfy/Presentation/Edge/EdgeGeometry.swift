import CoreGraphics

/// Screen-space layout for the edge tab and basket (AppKit coordinates, origin bottom-left).
/// Pure value math so it can be unit tested.
nonisolated struct EdgeGeometry: Equatable {
    struct Input: Equatable {
        var screenFrame: CGRect
        var visibleFrame: CGRect
        var edge: ScreenEdge
        /// 0 = top of the usable edge, 1 = bottom.
        var position: Double
        var tabSize: CGSize
        var activationDepth: CGFloat
        var basketSize: CGSize
    }

    /// Gap between the basket and the screen edge.
    static let basketInset: CGFloat = 10
    /// Keeps the basket off the menu bar, Dock and screen corners.
    static let screenMargin: CGFloat = 8
    /// Keeps the tab well away from the corners, where hot corners live.
    static let cornerClearance: CGFloat = 76
    /// Room around the basket for its shadow.
    static let shadowMargin: CGFloat = 30
    /// Extra room around the basket that still counts as "inside" for hover.
    static let hoverMargin: CGFloat = 16
    /// Visible-frame insets thinner than this come from an auto-hidden Dock and are ignored.
    static let dockInsetThreshold: CGFloat = 12
    /// Vertical slack around the tab in the activation area.
    static let activationSlack: CGFloat = 12
    /// How far above and below the tab the hidden tab can be summoned from the edge.
    static let revealSlack: CGFloat = 96
    /// Width of the invisible strip that watches for the pointer while the tab is hidden.
    static let sensorDepth: CGFloat = 4

    let input: Input
    /// The x coordinate of the edge the tab is tucked against.
    let edgeX: CGFloat
    let tabCenterY: CGFloat
    /// The visible part of the resting tab.
    let tabRect: CGRect
    /// The panel frame while collapsed: the tab plus a small activation area.
    let collapsedFrame: CGRect
    /// While the tab is hidden: a thin strip along the edge, around the tab's position.
    let sensorFrame: CGRect
    /// While a hidden tab is revealed: the sensor strip plus the tab's activation area.
    let revealedFrame: CGRect
    let basketRect: CGRect
    /// The panel frame while expanded.
    let expandedFrame: CGRect
    /// The region that keeps the basket open.
    let hoverRegion: CGRect

    init(_ input: Input) {
        self.input = input
        let screen = input.screenFrame
        let visible = input.visibleFrame

        // Sit beside a Dock that's visible on this edge; ignore the sliver an auto-hidden Dock reserves.
        switch input.edge {
        case .right:
            let inset = screen.maxX - visible.maxX
            edgeX = inset > Self.dockInsetThreshold ? visible.maxX : screen.maxX
        case .left:
            let inset = visible.minX - screen.minX
            edgeX = inset > Self.dockInsetThreshold ? visible.minX : screen.minX
        }

        let range = Self.tabCenterRange(visibleFrame: visible, tabHeight: input.tabSize.height)
        let position = min(max(input.position, 0), 1)
        tabCenterY = range.upperBound - (range.upperBound - range.lowerBound) * position

        let tabHeight = input.tabSize.height
        let tabWidth = input.tabSize.width
        let tabMinY = tabCenterY - tabHeight / 2
        tabRect = input.edge == .right
            ? CGRect(x: edgeX - tabWidth, y: tabMinY, width: tabWidth, height: tabHeight)
            : CGRect(x: edgeX, y: tabMinY, width: tabWidth, height: tabHeight)

        let depth = max(input.activationDepth, tabWidth)
        let zoneY = tabMinY - Self.activationSlack
        let zoneHeight = tabHeight + Self.activationSlack * 2
        collapsedFrame = input.edge == .right
            ? CGRect(x: edgeX - depth, y: zoneY, width: depth, height: zoneHeight)
            : CGRect(x: edgeX, y: zoneY, width: depth, height: zoneHeight)

        let sensorMinY = max(tabMinY - Self.revealSlack, visible.minY + Self.screenMargin)
        let sensorMaxY = min(tabMinY + tabHeight + Self.revealSlack, visible.maxY - Self.screenMargin)
        sensorFrame = input.edge == .right
            ? CGRect(x: edgeX - Self.sensorDepth, y: sensorMinY, width: Self.sensorDepth, height: sensorMaxY - sensorMinY)
            : CGRect(x: edgeX, y: sensorMinY, width: Self.sensorDepth, height: sensorMaxY - sensorMinY)
        revealedFrame = sensorFrame.union(collapsedFrame)

        let size = input.basketSize
        let lowest = visible.minY + Self.screenMargin
        let highest = visible.maxY - Self.screenMargin - size.height
        let basketY = highest >= lowest
            ? min(max(tabCenterY - size.height / 2, lowest), highest)
            : visible.minY + (visible.height - size.height) / 2
        let basketX = input.edge == .right ? edgeX - Self.basketInset - size.width : edgeX + Self.basketInset
        basketRect = CGRect(x: basketX, y: basketY, width: size.width, height: size.height)

        // The expanded panel covers the basket, its shadow and the tab, but never crosses the
        // edge (where it would spill onto a neighboring display) or leaves the screen.
        var expanded = basketRect.insetBy(dx: -Self.shadowMargin, dy: -Self.shadowMargin).union(collapsedFrame)
        if input.edge == .right {
            expanded.size.width = edgeX - expanded.minX
        } else {
            let maxX = expanded.maxX
            expanded.origin.x = edgeX
            expanded.size.width = maxX - edgeX
        }
        // Vertically, stay inside the visible frame so the transparent shadow margin never
        // sits over (and swallows clicks meant for) the menu bar or the Dock.
        let usable = CGRect(x: screen.minX, y: visible.minY, width: screen.width, height: visible.height)
        expandedFrame = expanded.intersection(usable).integral
        hoverRegion = basketRect.insetBy(dx: -Self.hoverMargin, dy: -Self.hoverMargin)
            .union(collapsedFrame)
            .intersection(expandedFrame)
    }

    /// Range of valid tab centers (bottom...top) on a display.
    static func tabCenterRange(visibleFrame: CGRect, tabHeight: CGFloat) -> ClosedRange<CGFloat> {
        let half = tabHeight / 2
        let top = visibleFrame.maxY - cornerClearance - half
        let bottom = visibleFrame.minY + cornerClearance + half
        guard top > bottom else { return visibleFrame.midY...visibleFrame.midY }
        return bottom...top
    }

    /// The `position` preference that puts the tab's center at `centerY`.
    static func position(forTabCenterY centerY: CGFloat, visibleFrame: CGRect, tabHeight: CGFloat) -> Double {
        let range = tabCenterRange(visibleFrame: visibleFrame, tabHeight: tabHeight)
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0.5 }
        return Double(min(max((range.upperBound - centerY) / span, 0), 1))
    }
}
