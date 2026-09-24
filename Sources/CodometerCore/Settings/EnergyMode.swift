/// How refreshes react to battery, Low Power Mode and heat.
public enum EnergyMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Refreshes less often on battery, in Low Power Mode or when the Mac runs hot.
    case automatic
    /// Keeps the normal schedule (live effects still pause in Low Power Mode, which the system asks for).
    case alwaysFresh
    /// Refreshes at most half as often as normal, and less when `automatic` would.
    case saveBattery

    public var id: String { rawValue }
}
