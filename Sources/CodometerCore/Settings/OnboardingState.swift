/// Which version of the first-run welcome flow the user has finished.
///
/// Settings written before the key existed decode as `completed`, so existing users are never asked again; a fresh
/// install writes `notStarted`. A version above `currentVersion` (written by a newer build) counts as completed.
public struct OnboardingState: Hashable, Sendable {
    public static let currentVersion = 1

    public let completedVersion: Int

    public init(completedVersion: Int) throws(ValidationError) {
        guard completedVersion >= 0 else {
            throw .outOfRange(
                field: "general.onboarding.completedVersion",
                value: Double(completedVersion),
                lowerBound: 0,
                upperBound: Double(Int.max)
            )
        }
        self.completedVersion = completedVersion
    }

    private init(trustedVersion: Int) {
        completedVersion = trustedVersion
    }

    public static let completed = OnboardingState(trustedVersion: currentVersion)
    public static let notStarted = OnboardingState(trustedVersion: 0)

    public var needsOnboarding: Bool { completedVersion < Self.currentVersion }
}

extension OnboardingState: Codable {
    private enum CodingKeys: String, CodingKey {
        case completedVersion
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .completedVersion)
        do throws(ValidationError) {
            self = try OnboardingState(completedVersion: version)
        } catch {
            throw error.decodingError(at: container.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(completedVersion, forKey: .completedVersion)
    }
}
