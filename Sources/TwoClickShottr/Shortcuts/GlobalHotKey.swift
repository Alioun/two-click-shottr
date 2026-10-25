import Carbon

@MainActor
final class GlobalHotKey {
    static let identifier = EventHotKeyID(signature: 0x5443_5348, id: 1)
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var handlerStatus = OSStatus(eventNotHandledErr)
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    func install() {
        guard handler == nil else { return }
        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr, identifier.signature == GlobalHotKey.identifier.signature,
                    identifier.id == GlobalHotKey.identifier.id
                else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { owner.action() }
                return noErr
            }, 1, &specification, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: CaptureShortcut) -> OSStatus {
        guard handlerStatus == noErr else { return handlerStatus }
        return Self.register(shortcut, reference: &reference)
    }

    static func register(_ shortcut: CaptureShortcut, reference: inout EventHotKeyRef?) -> OSStatus {
        RegisterEventHotKey(
            shortcut.keyCode, shortcut.modifiers, identifier,
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }

    func invalidate() {
        unregister()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        handlerStatus = OSStatus(eventNotHandledErr)
    }

    static func deliverPress() -> OSStatus {
        var event: EventRef?
        let status = CreateEvent(
            nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
            GetCurrentEventTime(), 0, &event)
        guard status == noErr, let event else {
            return status == noErr ? OSStatus(eventNotHandledErr) : status
        }
        defer { ReleaseEvent(event) }
        var identifier = identifier
        let parameterStatus = SetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size, &identifier)
        guard parameterStatus == noErr else { return parameterStatus }
        return SendEventToEventTarget(event, GetApplicationEventTarget())
    }
}
