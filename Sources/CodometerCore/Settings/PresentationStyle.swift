/// How usage is presented on the desktop. Exactly one style is on screen; the menu bar item always stays.
public enum PresentationStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// The island on a screen edge (default).
    case island
    /// A movable card that can be minimized to a pill.
    case floatingCard

    public var id: String { rawValue }
}

/// Whether a top-centred island blends with a MacBook camera notch.
public enum NotchFusionMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Fuses whenever the island sits attached at the top centre of a display with a notch (drawn solid black).
    case automatic
    case off

    public var id: String { rawValue }
}
