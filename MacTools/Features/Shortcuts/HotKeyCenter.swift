import Carbon.HIToolbox
import Foundation

/// Registers global hotkeys through Carbon's `RegisterEventHotKey`.
///
/// Carbon is the API that needs no permission at all: the app declares the
/// exact combos it wants and macOS delivers only those. Nothing else about the
/// keyboard is visible to the app, so there is no Accessibility prompt.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    enum RegistrationError: Error, CustomStringConvertible {
        case unknownKey(String)
        case alreadyTaken
        case failed(OSStatus)

        var description: String {
            switch self {
            case .unknownKey(let key): return "touche inconnue : \(key)"
            case .alreadyTaken: return "combinaison deja prise par une autre app"
            case .failed(let status): return "echec Carbon (\(status))"
            }
        }
    }

    private struct Registration {
        let ref: EventHotKeyRef
        let shortcutID: String
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextCarbonID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private var onTrigger: ((String) -> Void)?

    private init() {}

    /// Called with the shortcut id every time one of the combos fires.
    func setTriggerHandler(_ handler: @escaping (String) -> Void) {
        onTrigger = handler
    }

    /// Replaces every registration. Returns the shortcuts that could not be
    /// registered, so the UI can say why instead of failing silently.
    @discardableResult
    func register(_ shortcuts: [UserShortcut]) -> [String: RegistrationError] {
        installEventHandlerIfNeeded()
        unregisterAll()

        var failures: [String: RegistrationError] = [:]
        for shortcut in shortcuts where shortcut.enabled {
            do {
                try register(shortcut)
            } catch let error as RegistrationError {
                failures[shortcut.id] = error
            } catch {
                failures[shortcut.id] = .failed(OSStatus(-1))
            }
        }
        return failures
    }

    private func register(_ shortcut: UserShortcut) throws {
        guard let keyCode = KeyCodeResolver.keyCode(for: shortcut.key) else {
            throw RegistrationError.unknownKey(shortcut.key)
        }

        let carbonID = nextCarbonID
        nextCarbonID += 1

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: carbonID)
        let status = RegisterEventHotKey(
            keyCode,
            carbonModifiers(shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            // -9878 is eventHotKeyExistsErr: someone else owns the combo.
            throw status == -9878 ? RegistrationError.alreadyTaken : RegistrationError.failed(status)
        }

        registrations[carbonID] = Registration(ref: hotKeyRef, shortcutID: shortcut.id)
    }

    private func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
    }

    private func carbonModifiers(_ modifiers: [UserShortcut.Modifier]) -> UInt32 {
        var mask: UInt32 = 0
        for modifier in modifiers {
            switch modifier {
            case .command: mask |= UInt32(cmdKey)
            case .shift: mask |= UInt32(shiftKey)
            case .option: mask |= UInt32(optionKey)
            case .control: mask |= UInt32(controlKey)
            }
        }
        return mask
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventCallback, 1, &spec, nil, &eventHandler)
    }

    fileprivate func trigger(carbonID: UInt32) {
        guard let registration = registrations[carbonID] else { return }
        onTrigger?(registration.shortcutID)
    }
}

/// Four-char code 'MCTL', identifying our hotkeys among Carbon's. Kept outside
/// the class so the C callback can read it without actor isolation.
private let hotKeySignature: OSType = Array("MCTL".utf8)
    .reduce(OSType(0)) { ($0 << 8) | OSType($1) }

/// C callback: cannot capture context, so it forwards to the shared center.
private func hotKeyEventCallback(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == hotKeySignature else { return status }

    let carbonID = hotKeyID.id
    Task { @MainActor in
        HotKeyCenter.shared.trigger(carbonID: carbonID)
    }
    return noErr
}
