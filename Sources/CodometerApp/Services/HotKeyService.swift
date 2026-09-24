import CodometerCore
import CodometerPlatform
import Carbon.HIToolbox
import os

/// The app's Carbon hot keys: the system-wide shortcut that toggles the deck (id 1) and the scoped Esc that closes a
/// pinned deck while another app is active (id 2).
///
/// `RegisterEventHotKey` delivers exactly the registered combination to this app and needs no Accessibility
/// permission (unlike a global key-down monitor, which would see every keystroke). Registration is **exclusive**
/// (`kEventHotKeyExclusive`), so another app holding the same combination is reported instead of both apps getting
/// the key silently. Everything is released when the service goes away.
@MainActor
final class HotKeyService {
    /// 'Cdmt': tells our hot key events apart from anyone else's.
    nonisolated static let signature: OSType = 0x4364_6D74

    /// What a registration is for.
    enum Identifier: UInt32, CaseIterable {
        /// The global shortcut that toggles the active surface.
        case shortcut = 1
        /// Esc while a pinned deck is open and Codometer is not the active app (L4).
        case escape = 2
    }

    /// Esc's Carbon virtual key code (`kVK_Escape`).
    nonisolated static let escapeKeyCode: UInt32 = 0x35

    /// A press of the global shortcut.
    var onPress: (() -> Void)?
    /// A press of the scoped Esc hot key.
    var onEscape: (() -> Void)?

    private(set) var shortcut: GlobalShortcut = .off
    private var hotKeys: [Identifier: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    /// Carbon key code and modifier mask for a shortcut; `nil` for `.off`. The values live in Core
    /// (`ShortcutConflictResolver.combination`), so conflict checks and registration use the same combination.
    nonisolated static func combination(for shortcut: GlobalShortcut) -> (keyCode: UInt32, modifiers: UInt32)? {
        ShortcutConflictResolver.combination(for: shortcut).map { ($0.keyCode, $0.carbonModifiers) }
    }

    // MARK: - The global shortcut

    /// Registers `shortcut`, replacing the previous one; `.off` unregisters. Returns what happened, for the shortcut
    /// status shown in Settings (asking again for the registered shortcut reports `.registered` without re-registering).
    @discardableResult
    func apply(_ shortcut: GlobalShortcut) -> ShortcutRegistration {
        guard shortcut != self.shortcut else { return shortcut == .off ? .off : .registered }
        unregister(id: .shortcut)
        self.shortcut = .off
        guard let combination = Self.combination(for: shortcut) else { return .off }
        let result = register(id: .shortcut, keyCode: combination.keyCode, modifiers: combination.modifiers)
        if result == .registered {
            self.shortcut = shortcut
        } else {
            // Most likely another app already owns the combination; the rest of the app works without it.
            AppLog.interface.error("global shortcut \(shortcut.rawValue, privacy: .public) unavailable: \(String(describing: result), privacy: .public)")
        }
        return result
    }

    /// Trial-registers every other choice to find out which ones are free, then releases them again.
    ///
    /// Synchronous and cheap (a register/unregister pair per candidate). Called only when the chosen shortcut is
    /// unavailable or when Settings asks for a fresh status, never on a timer.
    func probeAlternatives(excluding chosen: GlobalShortcut) -> [GlobalShortcut: ShortcutRegistration] {
        var trials: [GlobalShortcut: ShortcutRegistration] = [:]
        for candidate in GlobalShortcut.allCases where candidate != .off && candidate != chosen {
            guard let combination = Self.combination(for: candidate) else { continue }
            let result = register(id: .shortcut, keyCode: combination.keyCode, modifiers: combination.modifiers)
            trials[candidate] = result
            unregister(id: .shortcut)
        }
        // The trials borrowed the shortcut slot: put the chosen one back through `apply`, so a restore that fails
        // (another app took the combination during the probe) leaves `shortcut` at `.off` and the next `apply`
        // registers it again, instead of reporting a shortcut nothing is listening for.
        let registered = shortcut
        shortcut = .off
        _ = apply(registered)
        return trials
    }

    /// macOS's own keyboard shortcuts, for detecting a combination the system handles first.
    ///
    /// `CopySymbolicHotKeys` is an old HIToolbox API; an error simply means no system check (documented in L3).
    func symbolicHotKeys() -> [SymbolicHotKey] {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let array = unmanaged?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }
        return array.compactMap { entry in
            guard let keyCode = (entry[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value,
                  let modifiers = (entry[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value
            else { return nil }
            let enabled = (entry[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue ?? false
            return SymbolicHotKey(keyCode: keyCode, modifiers: modifiers, isEnabled: enabled)
        }
    }

    // MARK: - Esc

    /// Arms or disarms the scoped Esc hot key. Idempotent, so the island may call it on every state change.
    @discardableResult
    func setEscapeArmed(_ armed: Bool) -> ShortcutRegistration {
        guard armed else {
            unregister(id: .escape)
            return .off
        }
        guard hotKeys[.escape] == nil else { return .registered }
        let result = register(id: .escape, keyCode: Self.escapeKeyCode, modifiers: 0)
        if result != .registered {
            // Very rare (another app holds plain Esc): the local monitor and an outside click still close the deck.
            AppLog.interface.debug("escape hot key unavailable: \(String(describing: result), privacy: .public)")
        }
        return result
    }

    var isEscapeArmed: Bool { hotKeys[.escape] != nil }

    // MARK: - Registration

    private func register(id: Identifier, keyCode: UInt32, modifiers: UInt32) -> ShortcutRegistration {
        unregister(id: id)
        let handlerStatus = installHandler()
        guard handlerStatus == noErr else { return .failed(code: handlerStatus) }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: id.rawValue),
            GetApplicationEventTarget(),
            UInt32(kEventHotKeyExclusive),
            &reference
        )
        guard status == noErr, let reference else {
            releaseHandlerIfUnused()
            return status == ShortcutConflictResolver.hotKeyExistsCode ? .takenExclusively : .failed(code: status == noErr ? -1 : status)
        }
        hotKeys[id] = reference
        return .registered
    }

    private func unregister(id: Identifier) {
        if let hotKey = hotKeys.removeValue(forKey: id) {
            UnregisterEventHotKey(hotKey)
        }
        releaseHandlerIfUnused()
    }

    /// Releases every registration, e.g. when the service goes away.
    func unregister() {
        for id in Identifier.allCases {
            if let hotKey = hotKeys.removeValue(forKey: id) {
                UnregisterEventHotKey(hotKey)
            }
        }
        shortcut = .off
        removeHandler()
    }

    isolated deinit {
        unregister()
    }

    /// `noErr` when the handler is (already) installed.
    private func installHandler() -> OSStatus {
        guard handler == nil else { return noErr }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var reference: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &reference
        )
        guard status == noErr, let reference else {
            AppLog.interface.error("hot key handler not installed: \(status, privacy: .public)")
            return status == noErr ? -1 : status
        }
        handler = reference
        return noErr
    }

    private func releaseHandlerIfUnused() {
        guard hotKeys.isEmpty else { return }
        removeHandler()
    }

    private func removeHandler() {
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    /// The seam every hot key press goes through, so id routing is testable without Carbon.
    func pressed(id: Identifier) {
        guard hotKeys[id] != nil else { return }
        switch id {
        case .shortcut:
            onPress?()
        case .escape:
            onEscape?()
        }
    }

    fileprivate func pressed(eventID: EventHotKeyID) {
        guard eventID.signature == Self.signature, let id = Identifier(rawValue: eventID.id) else { return }
        pressed(id: id)
    }
}

/// Carbon calls this on the main thread for hot key events sent to the application target.
private func hotKeyEventHandler(_ call: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr, id.signature == HotKeyService.signature else { return OSStatus(eventNotHandledErr) }
    let hotKeyID = id
    let address = UInt(bitPattern: userData)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<HotKeyService>.fromOpaque(pointer).takeUnretainedValue().pressed(eventID: hotKeyID)
    }
    return noErr
}
