import Foundation

/// An account's identity colour.
///
/// Identity only, never data: tints appear on identity chrome (monogram badge, card header accent, a small dot) and
/// never on arcs, bars, rims or glass, where colour means usage, waiting or provider.
public enum AccountTint: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Picked by `AccountStyleResolver` from the palette.
    case automatic
    case teal, sky, indigo, lime, pink, sand, slate, graphite

    public var id: String { rawValue }

    /// The eight concrete tints, in the order automatic assignment probes them.
    public static let palette: [AccountTint] = [.teal, .sky, .indigo, .lime, .pink, .sand, .slate, .graphite]
}

/// One or two letters or digits, or a single emoji, that stand for an account on small surfaces.
public struct AccountMonogram: Hashable, Sendable, CustomStringConvertible {
    public static let maximumCharacters = 2
    public static let maximumBytes = 16

    public let value: String

    /// Trimmed; 1–2 `Character`s that are each a letter or digit (any script, uppercased), or exactly one emoji
    /// `Character`; no whitespace or control characters; at most 16 UTF-8 bytes.
    public init(validating raw: String) throws(ValidationError) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty(field: "account.monogram") }
        guard trimmed.utf8.count <= Self.maximumBytes else {
            throw .tooLong(field: "account.monogram", length: trimmed.utf8.count, maximum: Self.maximumBytes)
        }
        let characters = Array(trimmed)
        guard characters.count <= Self.maximumCharacters else {
            throw .tooLong(field: "account.monogram", length: characters.count, maximum: Self.maximumCharacters)
        }
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters).union(.illegalCharacters)
        guard !trimmed.unicodeScalars.contains(where: forbidden.contains) else {
            throw .invalidCharacters(field: "account.monogram")
        }
        if characters.count == 1, let only = characters.first, Self.isEmoji(only) {
            value = trimmed
            return
        }
        guard characters.allSatisfy({ Self.isLetterOrDigit($0) }) else {
            throw .invalidCharacters(field: "account.monogram")
        }
        value = characters.map(Self.uppercased).joined()
    }

    private init(trusted value: String) {
        self.value = value
    }

    public var description: String { value }

    /// The monogram an account gets when the user has not chosen one.
    ///
    /// Words of the label without the provider's name: two or more words → their initials ("Work account" → "WA"),
    /// one word → its initial ("Claude · work" → "W", "Личное" → "Л"); no words left ("Codex") → the account's
    /// 1-based `ordinal` among the provider's accounts ("1", "2", …; clamped to 1…99).
    public static func automatic(label: AccountLabel, provider: ProviderKind, ordinal: Int) -> AccountMonogram {
        var words: [Substring] = []
        var previous = ""
        for word in label.value.split(whereSeparator: { !isLetterOrDigit($0) }) {
            let folded = word.lowercased()
            // Provider names ("Claude", "Codex", "Claude Code") say nothing about which account this is.
            let isProviderName = folded == "claude" || folded == "codex" || (folded == "code" && previous == "claude")
            previous = folded
            if !isProviderName { words.append(word) }
        }
        let initials = words.prefix(maximumCharacters).compactMap(\.first).map(uppercased).joined()
        if !initials.isEmpty, let monogram = try? AccountMonogram(validating: initials) {
            return monogram
        }
        return AccountMonogram(trusted: String(min(max(ordinal, 1), 99)))
    }

    private static func isLetterOrDigit(_ character: Character) -> Bool {
        (character.isLetter || character.isNumber) && !isEmoji(character)
    }

    /// A pictographic emoji: emoji presentation by default, or text presentation turned into emoji with U+FE0F.
    private static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        if scalars.contains(where: { $0.properties.isEmojiPresentation }) { return true }
        return scalars.contains("\u{FE0F}") && scalars.first?.properties.isEmoji == true
    }

    /// Uppercases one character, keeping it when uppercasing would change the character count ("ß" → "SS").
    private static func uppercased(_ character: Character) -> String {
        let upper = String(character).uppercased()
        return upper.count == 1 ? upper : String(character)
    }
}

extension AccountMonogram: Codable {
    public init(from decoder: any Decoder) throws {
        let raw = try String(from: decoder)
        do throws(ValidationError) {
            self = try AccountMonogram(validating: raw)
        } catch {
            throw error.decodingError(at: decoder.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }
}

/// An account's resolved identity: a concrete tint and a monogram.
public struct AccountStyle: Hashable, Sendable {
    /// Never `.automatic`.
    public let tint: AccountTint
    public let monogram: AccountMonogram
    public let isAutomaticTint: Bool
    public let isAutomaticMonogram: Bool

    public init(tint: AccountTint, monogram: AccountMonogram, isAutomaticTint: Bool, isAutomaticMonogram: Bool) throws(ValidationError) {
        guard tint != .automatic else {
            throw .inconsistent(field: "account.tint", reason: "a resolved style needs a concrete tint")
        }
        self.tint = tint
        self.monogram = monogram
        self.isAutomaticTint = isAutomaticTint
        self.isAutomaticMonogram = isAutomaticMonogram
    }

    fileprivate init(trustedTint tint: AccountTint, monogram: AccountMonogram, isAutomaticTint: Bool, isAutomaticMonogram: Bool) {
        self.tint = tint
        self.monogram = monogram
        self.isAutomaticTint = isAutomaticTint
        self.isAutomaticMonogram = isAutomaticMonogram
    }
}

/// Resolves every account's tint and monogram. Run it over the whole settings account list (not a filtered one), so
/// automatic tints stay the same whatever the island shows.
public enum AccountStyleResolver {
    /// Explicit tints are kept (duplicates allowed). Automatic ones take unused palette entries, in settings order,
    /// starting at a stable FNV-1a hash of the account's UUID bytes (never `Hasher`, which is seeded per process) and
    /// probing forward; once all eight are used, an automatic account takes its hash entry. Monograms: explicit ones
    /// are kept, others come from `AccountMonogram.automatic` with the account's ordinal among its provider's accounts.
    public static func styles(for accounts: [AccountProfile]) -> [AccountID: AccountStyle] {
        let palette = AccountTint.palette
        var used = Set(accounts.map(\.tint).filter { $0 != .automatic })
        var ordinals: [ProviderKind: Int] = [:]
        var styles: [AccountID: AccountStyle] = [:]
        for account in accounts {
            let ordinal = (ordinals[account.provider] ?? 0) + 1
            ordinals[account.provider] = ordinal

            let tint: AccountTint
            if account.tint != .automatic {
                tint = account.tint
            } else {
                let start = Int(fnv1a(account.id.rawValue) % UInt64(palette.count))
                let free = (0..<palette.count)
                    .map { palette[(start + $0) % palette.count] }
                    .first { !used.contains($0) }
                tint = free ?? palette[start]
                used.insert(tint)
            }
            let monogram = account.monogram
                ?? AccountMonogram.automatic(label: account.label, provider: account.provider, ordinal: ordinal)
            styles[account.id] = AccountStyle(
                trustedTint: tint,
                monogram: monogram,
                isAutomaticTint: account.tint == .automatic,
                isAutomaticMonogram: account.monogram == nil
            )
        }
        return styles
    }

    /// 64-bit FNV-1a over the UUID's 16 bytes.
    static func fnv1a(_ uuid: UUID) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        withUnsafeBytes(of: uuid.uuid) { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        return hash
    }
}
