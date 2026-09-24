import Carbon.HIToolbox
import CodometerCore
import Testing

@Suite("Shortcut conflict resolver")
struct ShortcutConflictResolverTests {
    private let controlOption = UInt32(controlKey | optionKey)

    @Test("Combinations are the Carbon values the hot key service registered before")
    func combinations() throws {
        #expect(ShortcutConflictResolver.combination(for: .off) == nil)
        let u = try #require(ShortcutConflictResolver.combination(for: .controlOptionCommandU))
        #expect(u.keyCode == UInt32(kVK_ANSI_U) && u.carbonModifiers == controlOption | UInt32(cmdKey))
        let space = try #require(ShortcutConflictResolver.combination(for: .controlOptionSpace))
        #expect(space.keyCode == UInt32(kVK_Space) && space.carbonModifiers == controlOption)
        let l = try #require(ShortcutConflictResolver.combination(for: .controlOptionCommandL))
        #expect(l.keyCode == UInt32(kVK_ANSI_L) && l.carbonModifiers == controlOption | UInt32(cmdKey))
        #expect(ShortcutConflictResolver.commandMask == UInt32(cmdKey))
        #expect(ShortcutConflictResolver.shiftMask == UInt32(shiftKey))
        #expect(ShortcutConflictResolver.optionMask == UInt32(optionKey))
        #expect(ShortcutConflictResolver.controlMask == UInt32(controlKey))
        #expect(ShortcutConflictResolver.hotKeyExistsCode == Int32(eventHotKeyExistsErr))
    }

    /// Raw modifier values and their Carbon masks: HIToolbox dictionaries use Carbon masks, `com.apple.symbolichotkeys`
    /// uses `NSEvent.ModifierFlags` bits (⇧ 1<<17, ⌃ 1<<18, ⌥ 1<<19, ⌘ 1<<20, fn 1<<23).
    private static let modifierCases: [(raw: UInt32, carbon: UInt32)] = {
        let command = UInt32(cmdKey)
        let shift = UInt32(shiftKey)
        let option = UInt32(optionKey)
        let control = UInt32(controlKey)
        let capsLock = UInt32(alphaLock)
        let eventShift: UInt32 = 1 << 17
        let eventControl: UInt32 = 1 << 18
        let eventOption: UInt32 = 1 << 19
        let eventCommand: UInt32 = 1 << 20
        let eventFunction: UInt32 = 1 << 23
        let carbonFunction: UInt32 = 1 << 17 // kEventKeyModifierFnBit, the same bit as NSEvent Shift
        return [
            (control | option, control | option),
            (command | shift | capsLock, command | shift),
            (control | option | carbonFunction, control | option),
            (eventControl, control),
            (eventControl | eventOption, control | option),
            (eventShift | eventCommand | eventFunction, command | shift),
            (0, 0),
        ]
    }()

    @Test("Symbolic hot key modifiers normalise from both encodings")
    func modifierEncodings() {
        for entry in Self.modifierCases {
            #expect(ShortcutConflictResolver.carbonModifiers(normalizing: entry.raw) == entry.carbon)
            #expect(SymbolicHotKey(keyCode: 49, modifiers: entry.raw, isEnabled: true).carbonModifiers == entry.carbon)
        }
    }

    private let inputSourceSwitch = SymbolicHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(1 << 18 | 1 << 19), isEnabled: true)

    @Test("Truth table")
    func truthTable() {
        let trials: [GlobalShortcut: ShortcutRegistration] = [:]
        #expect(ShortcutConflictResolver.status(for: .off, registration: .registered, symbolic: [], trials: trials) == .off)
        #expect(ShortcutConflictResolver.status(for: .controlOptionCommandU, registration: .off, symbolic: [], trials: trials) == .off)
        #expect(ShortcutConflictResolver.status(for: .controlOptionCommandU, registration: .registered, symbolic: [], trials: trials) == .active(.controlOptionCommandU))
        #expect(ShortcutConflictResolver.status(for: .controlOptionCommandU, registration: .takenExclusively, symbolic: [], trials: trials)
            == .unavailable(.controlOptionCommandU, reason: .usedByAnotherApp, alternatives: []))
        #expect(ShortcutConflictResolver.status(for: .controlOptionCommandU, registration: .failed(code: -9878), symbolic: [], trials: trials)
            == .unavailable(.controlOptionCommandU, reason: .usedByAnotherApp, alternatives: []))
        #expect(ShortcutConflictResolver.status(for: .controlOptionCommandU, registration: .failed(code: -50), symbolic: [], trials: trials)
            == .unavailable(.controlOptionCommandU, reason: .failed(code: -50), alternatives: []))
    }

    @Test("An enabled macOS shortcut wins even when registration succeeds; a disabled one does not")
    func macOSConflicts() {
        #expect(ShortcutConflictResolver.status(for: .controlOptionSpace, registration: .registered, symbolic: [inputSourceSwitch], trials: [:])
            == .unavailable(.controlOptionSpace, reason: .usedByMacOS, alternatives: []))
        let disabled = SymbolicHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), isEnabled: false)
        #expect(ShortcutConflictResolver.status(for: .controlOptionSpace, registration: .registered, symbolic: [disabled], trials: [:])
            == .active(.controlOptionSpace))
        let otherModifiers = SymbolicHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey), isEnabled: true)
        #expect(ShortcutConflictResolver.status(for: .controlOptionSpace, registration: .registered, symbolic: [otherModifiers], trials: [:])
            == .active(.controlOptionSpace))
        #expect(!ShortcutConflictResolver.isUsedByMacOS(.off, symbolic: [inputSourceSwitch]))
    }

    @Test("Alternatives: other choices that registered in a trial and no macOS shortcut uses, in picker order")
    func alternatives() {
        let trials: [GlobalShortcut: ShortcutRegistration] = [
            .controlOptionCommandU: .registered,
            .controlOptionSpace: .registered,
            .controlOptionCommandL: .registered,
            .off: .registered,
        ]
        #expect(ShortcutConflictResolver.status(for: .controlOptionCommandU, registration: .takenExclusively, symbolic: [inputSourceSwitch], trials: trials)
            == .unavailable(.controlOptionCommandU, reason: .usedByAnotherApp, alternatives: [.controlOptionCommandL]))
        let someFail: [GlobalShortcut: ShortcutRegistration] = [.controlOptionSpace: .registered, .controlOptionCommandL: .takenExclusively]
        #expect(ShortcutConflictResolver.status(for: .controlOptionCommandU, registration: .failed(code: -1), symbolic: [], trials: someFail)
            == .unavailable(.controlOptionCommandU, reason: .failed(code: -1), alternatives: [.controlOptionSpace]))
    }
}
