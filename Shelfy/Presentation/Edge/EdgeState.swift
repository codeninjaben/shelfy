import CoreGraphics
import Observation

/// Observable state the edge panel's SwiftUI surface renders. Rects are in screen
/// coordinates; the view converts them into the panel's local space.
@MainActor @Observable
final class EdgeState {
    var edge: ScreenEdge = .right
    var windowFrame: CGRect = .zero
    /// The resting, visible part of the tab.
    var tabRect: CGRect = .zero
    var basketRect: CGRect = CGRect(x: 0, y: 0, width: BasketMetrics.edgeWidth, height: 200)
    /// Drives the glass morph between tab and basket.
    var isExpanded = false
    /// Drives the basket content's fade, slightly behind the morph.
    var showsContent = false
    var isHoveringTab = false
    /// The pointer is clearly heading for the tab: it sticks out a little further.
    var isApproaching = false
    /// Waiting out of sight (Near Pointer, or over a full-screen app) until the pointer
    /// reaches the edge or heads for the tab.
    var isTabHidden = false
    /// Incremented to play the arrival nudge.
    var arrivalPulse = 0
}
