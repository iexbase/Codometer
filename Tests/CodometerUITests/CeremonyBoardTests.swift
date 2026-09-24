import CodometerCore
@testable import CodometerUI
import Foundation
import Testing

@Suite("Ceremony board")
struct CeremonyBoardTests {
    private let account = AccountID()
    private let other = AccountID()
    private let now = UIFixture.now

    private func event(_ account: AccountID? = nil, window: String = "primary", from previous: Double = 64, at date: Date? = nil) throws -> WindowResetEvent {
        try WindowResetEvent(
            accountID: account ?? self.account,
            bucketID: "main",
            windowID: window,
            previousUsed: try Percentage(validating: previous),
            newUsed: try Percentage(validating: 3),
            detectedAt: date ?? now
        )
    }

    @Test("Inserted resets are live for 60 s on every surface, with the fill they unwind from")
    func insertAndExpire() throws {
        var board = CeremonyBoard()
        #expect(board.isEmpty && board.nextExpiry == nil)
        let reset = try event()
        board.insert([reset], previousFractions: [reset.id: 0.64], now: now)

        let ceremony = try #require(board.ceremony(accountID: account, bucketID: "main", windowID: "primary", now: now))
        #expect(ceremony.event == reset)
        #expect(ceremony.previousFraction == 0.64)
        #expect(ceremony.startedAt == now && ceremony.playedOn.isEmpty)
        for surface in CeremonySurface.allCases {
            #expect(board.unplayed(on: surface, now: now.addingTimeInterval(59)).map(\.id) == [ceremony.id])
            #expect(board.unplayed(on: surface, now: now.addingTimeInterval(60)).isEmpty)
        }
        #expect(board.ceremony(accountID: account, bucketID: "main", windowID: "primary", now: now.addingTimeInterval(60)) == nil)
        #expect(board.ceremony(accountID: account, bucketID: "main", windowID: "other", now: now) == nil)
        #expect(board.nextExpiry == now.addingTimeInterval(ResetCeremony.lifetime))
    }

    @Test("A missing fraction unwinds from the previous usage; fractions are clamped")
    func fractions() throws {
        var board = CeremonyBoard()
        let plain = try event(from: 91)
        let wild = try event(other, from: 50)
        board.insert([plain, wild], previousFractions: [wild.id: 7], now: now)
        #expect(board.ceremony(accountID: account, bucketID: "main", windowID: "primary", now: now)?.previousFraction == 0.91)
        #expect(board.ceremony(accountID: other, bucketID: "main", windowID: "primary", now: now)?.previousFraction == 1)
    }

    @Test("The same reset again is not replayed; a newer reset replaces an older one, an older one is ignored")
    func dedupe() throws {
        var board = CeremonyBoard()
        let first = try event()
        board.insert([first], previousFractions: [:], now: now)
        let original = try #require(board.ceremony(accountID: account, bucketID: "main", windowID: "primary", now: now))
        board.markPlayed(original.id, on: .rail)

        board.insert([first], previousFractions: [:], now: now.addingTimeInterval(5))
        #expect(board.ceremony(accountID: account, bucketID: "main", windowID: "primary", now: now)?.id == original.id)
        #expect(board.unplayed(on: .rail, now: now).isEmpty)

        let older = try event(at: now.addingTimeInterval(-120))
        board.insert([older], previousFractions: [:], now: now.addingTimeInterval(6))
        #expect(board.ceremony(accountID: account, bucketID: "main", windowID: "primary", now: now)?.id == original.id)

        let newer = try event(at: now.addingTimeInterval(30))
        board.insert([newer], previousFractions: [:], now: now.addingTimeInterval(30))
        let replaced = try #require(board.ceremony(accountID: account, bucketID: "main", windowID: "primary", now: now.addingTimeInterval(30)))
        #expect(replaced.id != original.id && replaced.event == newer)
        #expect(replaced.playedOn.isEmpty)
        #expect(board.unplayed(on: .rail, now: now.addingTimeInterval(30)).count == 1)
    }

    @Test("Playing marks one surface only; unplayed lists oldest first")
    func markPlayed() throws {
        var board = CeremonyBoard()
        let early = try event(window: "primary")
        board.insert([early], previousFractions: [:], now: now)
        let late = try event(window: "secondary")
        board.insert([late], previousFractions: [:], now: now.addingTimeInterval(2))
        #expect(board.unplayed(on: .deck, now: now.addingTimeInterval(3)).map(\.event) == [early, late])

        let first = try #require(board.unplayed(on: .deck, now: now).first)
        board.markPlayed(first.id, on: .deck)
        #expect(board.unplayed(on: .deck, now: now.addingTimeInterval(3)).map(\.event) == [late])
        #expect(board.unplayed(on: .rail, now: now.addingTimeInterval(3)).count == 2)
        #expect(board.ceremony(accountID: account, bucketID: "main", windowID: "primary", now: now)?.playedOn == [.deck])

        let before = board
        board.markPlayed(UUID(), on: .card)
        #expect(board == before)
    }

    @Test("Just reset lasts 10 minutes from the latest reset; prune drops what expired")
    func justResetAndPrune() throws {
        var board = CeremonyBoard()
        board.insert([try event(at: now)], previousFractions: [:], now: now)
        #expect(board.justReset(accountID: account, now: now.addingTimeInterval(599)) == now)
        #expect(board.justReset(accountID: account, now: now.addingTimeInterval(600)) == nil)
        #expect(board.justReset(accountID: other, now: now) == nil)

        board.prune(now: now.addingTimeInterval(61))
        #expect(board.unplayed(on: .rail, now: now).isEmpty)
        #expect(board.justReset(accountID: account, now: now.addingTimeInterval(61)) == now)
        #expect(board.nextExpiry == now.addingTimeInterval(CeremonyBoard.justResetDuration))

        board.prune(now: now.addingTimeInterval(600))
        #expect(board.isEmpty && board.nextExpiry == nil)
    }
}
