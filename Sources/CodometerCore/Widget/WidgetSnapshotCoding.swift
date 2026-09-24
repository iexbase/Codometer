import CodometerL10n
import Foundation

// Tolerant decoding: the widget extension may read a snapshot written by an older or newer app. Missing keys take
// defaults, an invalid account or window is dropped instead of failing the whole file, and every value passes the
// same validation as when it was created.

extension WidgetSnapshot: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, generatedAt, accounts, bands, attentionCount, workingCount, language, showsForecast, layout
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let generatedAt = (try? container.decodeIfPresent(Date.self, forKey: .generatedAt)) ?? .distantPast
        let accounts = (try? container.decodeIfPresent([Lossy<WidgetAccount>].self, forKey: .accounts))?
            .compactMap(\.value) ?? []
        let bands = (try? container.decodeIfPresent(BandThresholds.self, forKey: .bands)) ?? .standard
        let waiting = accounts.reduce(0) { $0 + $1.waitingCount }
        let working = accounts.reduce(0) { $0 + $1.workingCount }
        self.init(
            generatedAt: generatedAt,
            accounts: accounts,
            bands: bands,
            attentionCount: (try? container.decodeIfPresent(Int.self, forKey: .attentionCount)) ?? waiting,
            workingCount: (try? container.decodeIfPresent(Int.self, forKey: .workingCount)) ?? working,
            // Written by an app from before the key existed, or unknown: English, the default language.
            language: (try? container.decodeIfPresent(Language.self, forKey: .language)) ?? .en,
            // Missing or not a boolean: the setting's own default, so an older file keeps the feature on.
            showsForecast: (try? container.decodeIfPresent(Bool.self, forKey: .showsForecast)) ?? true,
            // Missing (a version-1 file) or a layout this build does not know: rings, the setting's own default.
            layout: (try? container.decodeIfPresent(WidgetLayout.self, forKey: .layout)) ?? .rings
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(bands, forKey: .bands)
        try container.encode(attentionCount, forKey: .attentionCount)
        try container.encode(workingCount, forKey: .workingCount)
        try container.encode(language, forKey: .language)
        try container.encode(showsForecast, forKey: .showsForecast)
        try container.encode(layout, forKey: .layout)
    }

    /// Deterministic JSON (sorted keys, dates as seconds since 1970), so equal content is byte-identical.
    public func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(self)
    }

    /// Decodes a snapshot file's contents; `nil` for oversized or unreadable data.
    public static func decode(_ data: Data) -> WidgetSnapshot? {
        guard !data.isEmpty, data.count <= maximumFileBytes else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}

extension WidgetAccount: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, label, provider, tint, monogram, plan, email, notice, windows
        case primaryWindowID, secondaryWindowID, modelWeeklyWindowID
        case capturedAt, isStale, isLimitReached, waitingCount, workingCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(AccountID.self, forKey: .id)
        let label = try container.decode(String.self, forKey: .label)
        let rawProvider = try container.decode(String.self, forKey: .provider)
        guard let provider = ProviderKind(rawValue: rawProvider) else {
            throw ValidationError.invalidCharacters(field: "widget.account.provider").decodingError(at: container.codingPath)
        }
        let windows = (try? container.decodeIfPresent([Lossy<WidgetWindow>].self, forKey: .windows))?
            .compactMap(\.value) ?? []
        do throws(ValidationError) {
            self = try WidgetAccount(
                id: id,
                label: label,
                provider: provider,
                // A tint this build does not know, and a monogram that no longer validates, are dropped: the account
                // then looks the way it did before it had an identity mark.
                tint: (try? container.decodeIfPresent(AccountTint.self, forKey: .tint)) ?? nil,
                monogram: (try? container.decodeIfPresent(AccountMonogram.self, forKey: .monogram)) ?? nil,
                plan: try? container.decodeIfPresent(String.self, forKey: .plan),
                email: try? container.decodeIfPresent(String.self, forKey: .email),
                notice: try? container.decodeIfPresent(String.self, forKey: .notice),
                windows: windows,
                primaryWindowID: try? container.decodeIfPresent(String.self, forKey: .primaryWindowID),
                secondaryWindowID: try? container.decodeIfPresent(String.self, forKey: .secondaryWindowID),
                modelWeeklyWindowID: try? container.decodeIfPresent(String.self, forKey: .modelWeeklyWindowID),
                capturedAt: try? container.decodeIfPresent(Date.self, forKey: .capturedAt),
                isStale: (try? container.decodeIfPresent(Bool.self, forKey: .isStale)) ?? false,
                isLimitReached: (try? container.decodeIfPresent(Bool.self, forKey: .isLimitReached)) ?? false,
                waitingCount: (try? container.decodeIfPresent(Int.self, forKey: .waitingCount)) ?? 0,
                workingCount: (try? container.decodeIfPresent(Int.self, forKey: .workingCount)) ?? 0
            )
        } catch {
            throw error.decodingError(at: container.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(provider.rawValue, forKey: .provider)
        try container.encodeIfPresent(tint?.rawValue, forKey: .tint)
        try container.encodeIfPresent(monogram, forKey: .monogram)
        try container.encodeIfPresent(plan, forKey: .plan)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(notice, forKey: .notice)
        try container.encode(windows, forKey: .windows)
        try container.encodeIfPresent(primaryWindowID, forKey: .primaryWindowID)
        try container.encodeIfPresent(secondaryWindowID, forKey: .secondaryWindowID)
        try container.encodeIfPresent(modelWeeklyWindowID, forKey: .modelWeeklyWindowID)
        try container.encodeIfPresent(capturedAt, forKey: .capturedAt)
        try container.encode(isStale, forKey: .isStale)
        try container.encode(isLimitReached, forKey: .isLimitReached)
        try container.encode(waitingCount, forKey: .waitingCount)
        try container.encode(workingCount, forKey: .workingCount)
    }
}

extension WidgetWindow: Codable {
    private enum CodingKeys: String, CodingKey {
        case bucketID, bucketTitle, isMainBucket, window, title
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bucketID = try container.decode(String.self, forKey: .bucketID)
        let window = try container.decode(LimitWindow.self, forKey: .window)
        do throws(ValidationError) {
            self = try WidgetWindow(
                bucketID: bucketID,
                bucketTitle: try? container.decodeIfPresent(String.self, forKey: .bucketTitle),
                isMainBucket: (try? container.decodeIfPresent(Bool.self, forKey: .isMainBucket)) ?? true,
                window: window,
                title: try? container.decodeIfPresent(String.self, forKey: .title),
                // Every app writes the title; a file without one gets an English title (the snapshot's own language is
                // decoded by the enclosing container and not visible here).
                language: .en
            )
        } catch {
            throw error.decodingError(at: container.codingPath)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bucketID, forKey: .bucketID)
        try container.encodeIfPresent(bucketTitle, forKey: .bucketTitle)
        try container.encode(isMainBucket, forKey: .isMainBucket)
        try container.encode(window, forKey: .window)
        try container.encode(title, forKey: .title)
    }
}

/// Decodes an array element without failing the array: an invalid element becomes `nil`.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
