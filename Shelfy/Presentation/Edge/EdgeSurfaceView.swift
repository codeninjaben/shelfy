import SwiftUI

/// The edge panel's single glass surface. Collapsed, it's a small capsule tucked half
/// behind the screen edge; expanded, the same surface grows out of the tab into the basket,
/// so the glass stays continuous through the whole transition.
struct EdgeSurfaceView: View {
    let state: EdgeState
    let basket: BasketViewModel
    let accessibility: SystemAccessibility
    let onActivate: () -> Void

    var body: some View {
        EdgeSurface(state: state, basket: basket, onActivate: onActivate)
            .environment(accessibility)
    }
}

private struct EdgeSurface: View {
    let state: EdgeState
    let basket: BasketViewModel
    let onActivate: () -> Void
    @Environment(SystemAccessibility.self) private var accessibility

    /// How far the tab pokes out further when something new arrives.
    private static let arrivalNudge: CGFloat = 8

    var body: some View {
        let window = state.windowFrame
        KeyframeAnimator(initialValue: CGFloat.zero, trigger: state.arrivalPulse) { nudge in
            surface(nudge: accessibility.reduceMotion ? 0 : nudge)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(Self.arrivalNudge, duration: 0.2, spring: .snappy)
                SpringKeyframe(0, duration: 0.85, spring: Spring(duration: 0.65, bounce: 0.38))
            }
        }
        .frame(width: window.width, height: window.height, alignment: .topLeading)
    }

    private func surface(nudge: CGFloat) -> some View {
        let rect = local(state.isExpanded ? state.basketRect : tabShapeRect(nudge: nudge))
        let radius = state.isExpanded ? BasketMetrics.cornerRadius : min(rect.width, rect.height) / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let edgeAlignment: Alignment = state.edge == .right ? .trailing : .leading

        return Color.clear
            .frame(width: rect.width, height: rect.height)
            .overlay(alignment: state.edge == .right ? .leading : .trailing) {
                // The tab's grip sits in the visible half of the capsule.
                TabGlyph(hasUnseen: basket.collection.hasUnseen, isHovering: state.isHoveringTab)
                    .frame(width: visibleTabWidth(nudge: nudge))
                    .opacity(state.isExpanded || state.isTabHidden ? 0 : 1)
            }
            .overlay(alignment: edgeAlignment) {
                // Fixed-size content, revealed by the growing surface from the edge outward.
                BasketView(model: basket, chrome: .edge(state.edge))
                    .frame(width: state.basketRect.width, height: state.basketRect.height)
                    .opacity(state.showsContent ? 1 : 0)
                    .scaleEffect(state.showsContent ? 1 : 0.96, anchor: state.edge == .right ? .trailing : .leading)
                    .allowsHitTesting(state.showsContent)
                    .accessibilityHidden(!state.showsContent)
            }
            .clipShape(shape)
            .modifier(SurfaceMaterial(shape: shape, tint: tint, reduceTransparency: accessibility.reduceTransparency))
            .shadow(color: .black.opacity(state.isExpanded ? 0.18 : 0.1),
                    radius: state.isExpanded ? 24 : 4, y: state.isExpanded ? 12 : 1)
            .opacity(surfaceOpacity)
            .position(x: rect.midX, y: rect.midY)
            .accessibilityElement(children: state.isExpanded ? .contain : .ignore)
            .accessibilityLabel("Shelfy")
            .accessibilityValue(state.isExpanded ? "" : tabAccessibilityValue)
            .accessibilityHint(state.isExpanded ? "" : "Opens your downloads shelf")
            .accessibilityAddTraits(state.isExpanded ? [] : .isButton)
            .accessibilityAction { onActivate() }
    }

    // MARK: Geometry

    /// The tab as a capsule centered on the edge line; the window clips its outer half.
    private func tabShapeRect(nudge: CGFloat) -> CGRect {
        let tab = state.tabRect
        let visible = visibleTabWidth(nudge: nudge)
        let edgeX = state.edge == .right ? tab.maxX : tab.minX
        let growth: CGFloat = state.isHoveringTab ? 10 : 0
        return CGRect(x: edgeX - visible, y: tab.minY - growth / 2, width: visible * 2, height: tab.height + growth)
    }

    /// A hidden tab slides back behind the edge; with Reduce Motion it fades in place instead.
    private func visibleTabWidth(nudge: CGFloat) -> CGFloat {
        if state.isTabHidden && !accessibility.reduceMotion { return 0 }
        return state.tabRect.width + (state.isApproaching ? 3 : 0) + (state.isHoveringTab ? 4 : 0) + nudge
    }

    /// Screen rect → this window's SwiftUI space (origin top-left).
    private func local(_ rect: CGRect) -> CGRect {
        let window = state.windowFrame
        return CGRect(x: rect.minX - window.minX, y: window.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: Appearance

    private var tint: Color? {
        guard !state.isExpanded, basket.collection.hasUnseen else { return nil }
        return Color.accentColor.opacity(0.42)
    }

    private var surfaceOpacity: Double {
        if state.isExpanded { return 1 }
        if state.isTabHidden { return 0 }
        // An empty basket keeps the tab especially quiet.
        return basket.items.isEmpty && !state.isHoveringTab ? 0.6 : 1
    }

    private var tabAccessibilityValue: String {
        let items = basket.items
        guard !items.isEmpty else { return "Empty" }
        let unseen = basket.collection.unseen.count
        return unseen > 0 ? "\(ItemKind.summary(for: items)), \(unseen) new" : ItemKind.summary(for: items)
    }
}

/// The small mark inside the resting tab: a grip, or an accent dot when something new arrived.
private struct TabGlyph: View {
    let hasUnseen: Bool
    let isHovering: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.primary.opacity(isHovering ? 0.5 : 0.32))
                .frame(width: 3, height: isHovering ? 26 : 20)
                .opacity(hasUnseen ? 0 : 1)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .shadow(color: Color.accentColor.opacity(0.7), radius: 3)
                .scaleEffect(hasUnseen ? 1 : 0.2)
                .opacity(hasUnseen ? 1 : 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: hasUnseen)
        .animation(.easeOut(duration: 0.18), value: isHovering)
    }
}

/// Liquid Glass, or an opaque surface when Reduce Transparency is on.
private struct SurfaceMaterial: ViewModifier {
    let shape: RoundedRectangle
    let tint: Color?
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        } else {
            content.glassEffect(Glass.regular.tint(tint), in: shape)
        }
    }
}
