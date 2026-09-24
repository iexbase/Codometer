/// Token counts of one or more model responses. Every count is non-negative.
///
/// `input` counts only uncached prompt tokens: sources whose input total already includes cache reads
/// (Codex `input_tokens`) must subtract `cachedInput` before building a value, or cache reads count twice.
public struct TokenCounts: Hashable, Sendable {
    /// Uncached prompt tokens.
    public var input: Int64
    /// Prompt tokens read from the cache.
    public var cachedInput: Int64
    /// Prompt tokens written to the cache.
    public var cacheWrite: Int64
    /// Generated tokens, reasoning included.
    public var output: Int64
    /// The reasoning part of `output`, for display only; never added on top of `output`.
    public var reasoningOutput: Int64

    public static let zero = TokenCounts(trustedInput: 0, cachedInput: 0, cacheWrite: 0, output: 0, reasoningOutput: 0)

    public init(
        input: Int64,
        cachedInput: Int64,
        cacheWrite: Int64,
        output: Int64,
        reasoningOutput: Int64
    ) throws(ValidationError) {
        for (field, value) in [
            ("tokens.input", input),
            ("tokens.cachedInput", cachedInput),
            ("tokens.cacheWrite", cacheWrite),
            ("tokens.output", output),
            ("tokens.reasoningOutput", reasoningOutput),
        ] where value < 0 {
            throw .outOfRange(field: field, value: Double(value), lowerBound: 0, upperBound: Double(Int64.max))
        }
        self.init(
            trustedInput: input,
            cachedInput: cachedInput,
            cacheWrite: cacheWrite,
            output: output,
            reasoningOutput: reasoningOutput
        )
    }

    private init(trustedInput input: Int64, cachedInput: Int64, cacheWrite: Int64, output: Int64, reasoningOutput: Int64) {
        self.input = input
        self.cachedInput = cachedInput
        self.cacheWrite = cacheWrite
        self.output = output
        self.reasoningOutput = reasoningOutput
    }

    public var isZero: Bool { self == .zero }

    /// Adds counts field by field, saturating at `Int64.max` instead of trapping.
    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            trustedInput: saturatingSum(lhs.input, rhs.input),
            cachedInput: saturatingSum(lhs.cachedInput, rhs.cachedInput),
            cacheWrite: saturatingSum(lhs.cacheWrite, rhs.cacheWrite),
            output: saturatingSum(lhs.output, rhs.output),
            reasoningOutput: saturatingSum(lhs.reasoningOutput, rhs.reasoningOutput)
        )
    }

    /// Approximate limit cost in "input-token equivalents".
    ///
    /// Claude: input 1, cache write 1.25, cache read 0.1, output 5 (reasoning is already inside output).
    /// Codex: input 1, cache write 1, cache read 0.1, output 8 (reasoning output is a subset of output).
    public func weighted(for provider: ProviderKind) -> Double {
        let weights: (input: Double, cacheWrite: Double, cachedInput: Double, output: Double) = switch provider {
        case .claude: (1, 1.25, 0.1, 5)
        case .codex: (1, 1, 0.1, 8)
        }
        // Fields are public vars, so a caller could have stored a negative value; it never costs anything.
        return Double(max(input, 0)) * weights.input
            + Double(max(cacheWrite, 0)) * weights.cacheWrite
            + Double(max(cachedInput, 0)) * weights.cachedInput
            + Double(max(output, 0)) * weights.output
    }

    private static func saturatingSum(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (sum, overflow) = max(lhs, 0).addingReportingOverflow(max(rhs, 0))
        return overflow ? .max : sum
    }
}
