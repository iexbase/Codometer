/// One notification that summarises a burst of alerts.
public struct AlertSummaryStrings: Sendable {
    let l: Localizer

    /// The title: "3 alerts" | «3 события».
    public func title(count: Int) -> String {
        l.plural(count, en: ("\(count) alert", "\(count) alerts"), ru: ("\(count) событие", "\(count) события", "\(count) событий"))
    }

    /// The body: the fragments joined with commas, ending with `…` when some were left out.
    public func body(fragments: [String], isTruncated: Bool) -> String {
        (isTruncated ? fragments + ["…"] : fragments).joined(separator: ", ")
    }
}

extension Localizer {
    public var alertSummary: AlertSummaryStrings { AlertSummaryStrings(l: self) }
}
