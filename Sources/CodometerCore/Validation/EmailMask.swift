import Foundation

extension DisplayText {
    /// The mask character used in place of hidden letters.
    public static let maskBullet: Character = "•"

    /// Hides most of an e-mail address: `example@test.com` → `e••••e@test.com`.
    ///
    /// The local part keeps its first and last character around bullets; the domain stays readable.
    /// The bullet count is half the local part's length rounded up, clamped to 3...6, so the mask neither
    /// reveals the exact length nor collapses short names. A one- or two-character local part keeps only
    /// its first character. Text that is not an address becomes its first character plus bullets.
    public static func maskEmail(_ email: String) -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }

        guard
            let at = trimmed.lastIndex(of: "@"),
            at != trimmed.startIndex,
            trimmed.index(after: at) != trimmed.endIndex
        else {
            return String(first) + bullets(forLength: trimmed.count)
        }
        let local = trimmed[..<at]
        let domain = trimmed[at...]
        guard local.count > 2, let last = local.last else {
            return String(first) + bullets(forLength: local.count) + domain
        }
        return String(first) + bullets(forLength: local.count) + String(last) + domain
    }

    private static func bullets(forLength length: Int) -> String {
        let count = min(max((length + 1) / 2, 3), 6)
        return String(repeating: maskBullet, count: count)
    }
}
