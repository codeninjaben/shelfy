import Foundation
import Observation

nonisolated enum PresentationMode: String, CaseIterable, Identifiable, Sendable {
    case both, edge, menuBar

    var id: Self { self }
    var showsEdgeTab: Bool { self != .menuBar }
    var showsMenuBarIcon: Bool { self != .edge }

    var title: String {
        switch self {
        case .both: "Edge Tab & Menu Bar"
        case .edge: "Edge Tab Only"
        case .menuBar: "Menu Bar Only"
        }
    }
}

nonisolated enum ScreenEdge: String, CaseIterable, Identifiable, Sendable {
    case left, right
    var id: Self { self }
    var title: String { self == .left ? "Left" : "Right" }
}

/// Whether the edge tab is always on screen or waits for the pointer to reach the edge.
nonisolated enum TabVisibility: String, CaseIterable, Identifiable, Sendable {
    case nearPointer, always

    var id: Self { self }
    var title: String { self == .always ? "Always" : "Near Pointer" }
}

nonisolated enum HoverSensitivity: String, CaseIterable, Identifiable, Sendable {
    case low, medium, high

    var id: Self { self }
    var title: String { rawValue.capitalized }

    /// How long the pointer must rest on the tab before the basket opens.
    var openDelay: Duration {
        switch self {
        case .low: .milliseconds(420)
        case .medium: .milliseconds(240)
        case .high: .milliseconds(110)
        }
    }

    /// Depth of the invisible activation strip measured from the screen edge.
    var activationDepth: CGFloat {
        switch self {
        case .low: 18
        case .medium: 22
        case .high: 28
        }
    }
}

/// User settings, persisted in `UserDefaults`. Every change is reported through `onChange`
/// so AppKit controllers can react without polling.
@MainActor @Observable
final class Preferences {
    enum Key: Sendable {
        case presentation, edge, verticalPosition, display, tabVisibility, hideTabWhenEmpty
        case hoverSensitivity, arrivalAnimation
    }

    @ObservationIgnored var onChange: ((Key) -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    var presentation: PresentationMode {
        didSet { store(presentation.rawValue, .presentation) }
    }
    var edge: ScreenEdge {
        didSet { store(edge.rawValue, .edge) }
    }
    /// 0 is the top of the usable edge, 1 the bottom.
    var verticalPosition: Double {
        didSet {
            let clamped = min(max(verticalPosition, 0), 1)
            if clamped != verticalPosition { verticalPosition = clamped; return }
            store(verticalPosition, .verticalPosition)
        }
    }
    /// Display UUID for the edge tab; nil follows the main display.
    var displayID: String? {
        didSet { store(displayID, .display) }
    }
    /// Remembered so a disconnected display can still be named in Settings.
    var displayName: String? {
        didSet { defaults.set(displayName, forKey: Self.storageKey(for: "displayName")) }
    }
    var tabVisibility: TabVisibility {
        didSet { store(tabVisibility.rawValue, .tabVisibility) }
    }
    /// Take the tab off the edge entirely while there's nothing in the basket.
    var hideTabWhenEmpty: Bool {
        didSet { store(hideTabWhenEmpty, .hideTabWhenEmpty) }
    }
    var hoverSensitivity: HoverSensitivity {
        didSet { store(hoverSensitivity.rawValue, .hoverSensitivity) }
    }
    var arrivalAnimation: Bool {
        didSet { store(arrivalAnimation, .arrivalAnimation) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func value(_ name: String) -> Any? { defaults.object(forKey: Self.storageKey(for: name)) }
        presentation = (value("presentation") as? String).flatMap(PresentationMode.init) ?? .both
        edge = (value("edge") as? String).flatMap(ScreenEdge.init) ?? .right
        verticalPosition = (value("verticalPosition") as? Double) ?? 0.5
        displayID = value("display") as? String
        displayName = value("displayName") as? String
        tabVisibility = (value("tabVisibility") as? String).flatMap(TabVisibility.init) ?? .nearPointer
        hideTabWhenEmpty = (value("hideTabWhenEmpty") as? Bool) ?? false
        hoverSensitivity = (value("hoverSensitivity") as? String).flatMap(HoverSensitivity.init) ?? .medium
        arrivalAnimation = (value("arrivalAnimation") as? Bool) ?? true
    }

    private func store(_ value: Any?, _ key: Key) {
        let name: String = switch key {
        case .presentation: "presentation"
        case .edge: "edge"
        case .verticalPosition: "verticalPosition"
        case .display: "display"
        case .tabVisibility: "tabVisibility"
        case .hideTabWhenEmpty: "hideTabWhenEmpty"
        case .hoverSensitivity: "hoverSensitivity"
        case .arrivalAnimation: "arrivalAnimation"
        }
        defaults.set(value, forKey: Self.storageKey(for: name))
        onChange?(key)
    }

    private nonisolated static func storageKey(for name: String) -> String { "Shelfy.\(name)" }
}
