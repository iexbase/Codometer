/// Colour band for a usage level.
public enum UsageBand: String, Sendable, CaseIterable, Comparable {
    case ample
    case watch
    case critical
    case exhausted

    public init(used: Percentage, thresholds: BandThresholds) {
        if used.isExhausted {
            self = .exhausted
        } else if used >= thresholds.critical {
            self = .critical
        } else if used >= thresholds.watch {
            self = .watch
        } else {
            self = .ample
        }
    }

    private var severity: Int {
        switch self {
        case .ample: 0
        case .watch: 1
        case .critical: 2
        case .exhausted: 3
        }
    }

    public static func < (lhs: UsageBand, rhs: UsageBand) -> Bool {
        lhs.severity < rhs.severity
    }
}
