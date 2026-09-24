/// What happened when the App tried to register a global shortcut.
public enum ShortcutRegistration: Hashable, Sendable {
    case registered
    /// Nothing was registered: the shortcut is off, or this instance does not register shortcuts.
    case off
    /// Another app holds the combination exclusively (`eventHotKeyExistsErr`).
    case takenExclusively
    case failed(code: Int32)
}

/// One of macOS's own keyboard shortcuts (`CopySymbolicHotKeys`).
public struct SymbolicHotKey: Hashable, Sendable {
    public let keyCode: UInt32
    /// Carbon modifier mask (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
    public let carbonModifiers: UInt32
    public let isEnabled: Bool

    /// `modifiers` may use either the Carbon mask or `NSEvent.ModifierFlags` bits; both are normalised to the Carbon
    /// mask of Command, Shift, Option and Control.
    public init(keyCode: UInt32, modifiers: UInt32, isEnabled: Bool) {
        self.keyCode = keyCode
        carbonModifiers = ShortcutConflictResolver.carbonModifiers(normalizing: modifiers)
        self.isEnabled = isEnabled
    }
}

/// Why a chosen shortcut does not reach Codometer.
public enum ShortcutConflict: Hashable, Sendable {
    /// An enabled macOS shortcut uses it; the system handles it first even though registration succeeds.
    case usedByMacOS
    case usedByAnotherApp
    case failed(code: Int32)
}

/// The global shortcut as the user should see it.
public enum ShortcutStatus: Hashable, Sendable {
    case off
    case active(GlobalShortcut)
    /// `alternatives` are the other choices that registered in a trial and conflict with no macOS shortcut.
    case unavailable(GlobalShortcut, reason: ShortcutConflict, alternatives: [GlobalShortcut])
}

/// Pure shortcut rules: Carbon combinations and conflict decisions.
public enum ShortcutConflictResolver {
    /// Carbon `cmdKey`, `shiftKey`, `optionKey`, `controlKey`.
    public static let commandMask: UInt32 = 1 << 8
    public static let shiftMask: UInt32 = 1 << 9
    public static let optionMask: UInt32 = 1 << 11
    public static let controlMask: UInt32 = 1 << 12
    /// `kEventHotKeyExistsErr`: another app registered the combination exclusively.
    public static let hotKeyExistsCode: Int32 = -9878

    /// Carbon virtual key codes (`kVK_ANSI_U`, `kVK_ANSI_L`, `kVK_Space`).
    private static let keyU: UInt32 = 0x20
    private static let keyL: UInt32 = 0x25
    private static let keySpace: UInt32 = 0x31

    /// Carbon key code and modifier mask for a shortcut; `nil` for `.off`.
    public static func combination(for shortcut: GlobalShortcut) -> (keyCode: UInt32, carbonModifiers: UInt32)? {
        let controlOption = controlMask | optionMask
        switch shortcut {
        case .off:
            return nil
        case .controlOptionCommandU:
            return (keyU, controlOption | commandMask)
        case .controlOptionSpace:
            return (keySpace, controlOption)
        case .controlOptionCommandL:
            return (keyL, controlOption | commandMask)
        }
    }

    /// The Carbon mask of Command, Shift, Option and Control from either encoding. A value with any Carbon modifier
    /// bit is a Carbon mask (Carbon's Fn bit is 1<<17, the same bit as NSEvent's Shift, so the Carbon bits decide);
    /// otherwise `NSEvent.ModifierFlags` bits (Shift 1<<17, Control 1<<18, Option 1<<19, Command 1<<20) are mapped.
    /// Caps Lock, Fn and device-dependent bits are ignored.
    public static func carbonModifiers(normalizing raw: UInt32) -> UInt32 {
        let carbonBits = commandMask | shiftMask | optionMask | controlMask
        guard raw & carbonBits == 0 else {
            return raw & carbonBits
        }
        let eventShift: UInt32 = 1 << 17
        let eventControl: UInt32 = 1 << 18
        let eventOption: UInt32 = 1 << 19
        let eventCommand: UInt32 = 1 << 20
        var mask: UInt32 = 0
        if raw & eventShift != 0 { mask |= shiftMask }
        if raw & eventControl != 0 { mask |= controlMask }
        if raw & eventOption != 0 { mask |= optionMask }
        if raw & eventCommand != 0 { mask |= commandMask }
        return mask
    }

    /// Whether an enabled macOS shortcut uses the combination.
    public static func isUsedByMacOS(_ shortcut: GlobalShortcut, symbolic: [SymbolicHotKey]) -> Bool {
        guard let combination = combination(for: shortcut) else { return false }
        return symbolic.contains { key in
            key.isEnabled && key.keyCode == combination.keyCode && key.carbonModifiers == combination.carbonModifiers
        }
    }

    /// - `.off` for `GlobalShortcut.off` or when nothing was registered;
    /// - `.unavailable(.usedByMacOS)` when an enabled macOS shortcut matches, even if registration succeeded;
    /// - `.active` when registered;
    /// - `.unavailable(.usedByAnotherApp)` when taken exclusively, `.unavailable(.failed)` for other errors.
    ///
    /// Alternatives: the other shortcuts, in picker order, whose trial registered and that no macOS shortcut uses.
    public static func status(
        for shortcut: GlobalShortcut,
        registration: ShortcutRegistration,
        symbolic: [SymbolicHotKey],
        trials: [GlobalShortcut: ShortcutRegistration]
    ) -> ShortcutStatus {
        guard shortcut != .off, registration != .off else { return .off }
        let conflict: ShortcutConflict
        if isUsedByMacOS(shortcut, symbolic: symbolic) {
            conflict = .usedByMacOS
        } else {
            switch registration {
            case .registered, .off:
                return .active(shortcut)
            case .takenExclusively:
                conflict = .usedByAnotherApp
            case .failed(let code) where code == hotKeyExistsCode:
                conflict = .usedByAnotherApp
            case .failed(let code):
                conflict = .failed(code: code)
            }
        }
        let alternatives = GlobalShortcut.allCases.filter { candidate in
            candidate != .off
                && candidate != shortcut
                && trials[candidate] == .registered
                && !isUsedByMacOS(candidate, symbolic: symbolic)
        }
        return .unavailable(shortcut, reason: conflict, alternatives: alternatives)
    }
}
