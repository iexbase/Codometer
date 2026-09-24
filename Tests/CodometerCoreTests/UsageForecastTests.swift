import CodometerCore
import Foundation
import Testing

@Suite("Usage forecast")
struct UsageForecastTests {
    /// A 5-hour window with `elapsed` of it gone.
    private func window(used: Double, elapsed: Double, minutes: Int? = 300, resetsIn: TimeInterval? = nil) throws -> LimitWindow {
        let length = TimeInterval(minutes ?? 300) * 60
        return try Fixture.window("primary", used: used, minutes: minutes, resetsIn: resetsIn ?? length * (1 - elapsed))
    }

    @Test("40 % used at half the window → 80 %")
    func halfway() throws {
        let forecast = try #require(UsageForecast(window: try window(used: 40, elapsed: 0.5), now: Fixture.now, thresholds: .standard))
        #expect(abs(forecast.projectedUsed - 80) < 1e-9)
        #expect(!forecast.reachesLimit)
        #expect(forecast.band == .critical)
    }

    @Test("60 % used at 40 % elapsed → 150 %, reaches the limit, band exhausted")
    func overshoot() throws {
        let forecast = try #require(UsageForecast(window: try window(used: 60, elapsed: 0.4), now: Fixture.now, thresholds: .standard))
        #expect(abs(forecast.projectedUsed - 150) < 1e-9)
        #expect(forecast.reachesLimit)
        #expect(forecast.band == .exhausted)
    }

    @Test("Exactly 100 % projected reaches the limit")
    func exactlyAtLimit() throws {
        let forecast = try #require(UsageForecast(window: try window(used: 50, elapsed: 0.5), now: Fixture.now, thresholds: .standard))
        #expect(forecast.reachesLimit)
    }

    @Test("The band uses the user's thresholds")
    func bandThresholds() throws {
        let relaxed = try BandThresholds(watch: try Percentage(validating: 85), critical: try Percentage(validating: 95))
        let forecast = try #require(UsageForecast(window: try window(used: 40, elapsed: 0.5), now: Fixture.now, thresholds: relaxed))
        #expect(forecast.band == .ample)
    }

    @Test("Nothing to forecast", arguments: [
        (40.0, 0.14),   // too early
        (0.0, 0.5),     // nothing used
        (100.0, 0.5),   // already exhausted
        (99.0, 0.995),  // adds less than two points
        (30.0, 0.0),    // window just started
    ])
    func noForecast(used: Double, elapsed: Double) throws {
        #expect(UsageForecast(window: try window(used: used, elapsed: elapsed), now: Fixture.now, thresholds: .standard) == nil)
    }

    @Test("15 % elapsed is enough")
    func gateBoundary() throws {
        // 2 700 s of an 18 000 s window: exactly 15 %.
        #expect(UsageForecast(window: try window(used: 10, elapsed: 0, resetsIn: 15_300), now: Fixture.now, thresholds: .standard) != nil)
    }

    @Test("No reset time or duration, a passed reset, or a reset beyond one window (clock skew) forecast nothing")
    func missingOrSkewed() throws {
        let noDuration = try Fixture.window("primary", used: 40, minutes: nil, resetsIn: 3_600)
        #expect(UsageForecast(window: noDuration, now: Fixture.now, thresholds: .standard) == nil)
        let noReset = try Fixture.window("primary", used: 40, minutes: 300, resetsIn: nil)
        #expect(UsageForecast(window: noReset, now: Fixture.now, thresholds: .standard) == nil)
        let passed = try Fixture.window("primary", used: 40, minutes: 300, resetsIn: -60)
        #expect(UsageForecast(window: passed, now: Fixture.now, thresholds: .standard) == nil)
        let atReset = try Fixture.window("primary", used: 40, minutes: 300, resetsIn: 0)
        #expect(UsageForecast(window: atReset, now: Fixture.now, thresholds: .standard) == nil)
        let skewed = try Fixture.window("primary", used: 40, minutes: 300, resetsIn: 300 * 60 * 2)
        #expect(UsageForecast(window: skewed, now: Fixture.now, thresholds: .standard) == nil)
    }

    @Test("Agrees with the pace's elapsed share")
    func matchesPace() throws {
        let window = try window(used: 33, elapsed: 0.6)
        let pace = try #require(UsagePace(window: window, now: Fixture.now))
        let forecast = try #require(UsageForecast(window: window, now: Fixture.now, thresholds: .standard))
        #expect(abs(forecast.projectedUsed - 33 / pace.elapsedFraction) < 1e-9)
    }
}
