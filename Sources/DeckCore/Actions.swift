import AppKit
import ApplicationServices
import CoreAudio

/// A permissão de Acessibilidade de um DeckApp. Fica num objeto (e não em variáveis globais) pra cada DeckApp
/// e o selftest terem a sua; `isTrusted` e `askSystem` só mudam no --selftest (nada de pedido nem de tecla de verdade).
final class Accessibility {
    /// Dentro do NeyHub a Acessibilidade é a dele: só confere, nunca pede ao sistema.
    let hosted: Bool
    /// Hospedado sem Acessibilidade: a tela mostra "Precisa de Acessibilidade" com Conceder.
    var onUntrusted: () -> Void = {}
    var isTrusted: () -> Bool = { AXIsProcessTrusted() }
    var askSystem: () -> Void = {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    init(hosted: Bool) { self.hosted = hosted }

    /// Simular teclas exige a permissão de Acessibilidade; no avulso, na primeira vez o macOS pede.
    func trusted() -> Bool {
        if isTrusted() { return true }
        if hosted { onUntrusted() } else { askSystem() }
        Log.write("sem permissão de Acessibilidade")
        return false
    }
}

enum Perform {
    static func run(_ action: Action, store: Store, accessibility: Accessibility) {
        switch action {
        case .none:
            break
        case .openApp(let path):
            guard !path.isEmpty else { return }
            open(["-a", path])
        case .website(let address):
            guard !address.isEmpty else { return }
            open([address.contains("://") ? address : "https://" + address])
        case .hotkey(let code, let modifiers, _):
            guard accessibility.trusted() else { return }
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
                event?.flags = CGEventFlags(rawValue: modifiers)
                event?.post(tap: .cghidEventTap)
            }
        case .media(let key):
            guard accessibility.trusted() else { return }
            media(key)
        case .audioToggle(let first, let second):
            let target = Audio.defaultOutputUID() == first ? second : first
            if !Audio.setDefaultOutput(uid: target) {
                Log.write("saída de áudio não encontrada: \(target)")
                NSSound.beep()
            }
        case .nextPage:
            store.turnPage(by: 1, wrapping: true)
        case .previousPage:
            store.turnPage(by: -1, wrapping: true)
        }
    }

    /// Igual ao app da fifine: o `open` traz pra frente até app já aberto; o NSWorkspace, chamado de
    /// um app de barra que não está ativo, só abre sem trazer pra frente.
    private static func open(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        process.terminationHandler = { if $0.terminationStatus != 0 { Log.write("open \(arguments) saiu com \($0.terminationStatus)") } }
        do { try process.run() } catch { Log.write("open \(arguments) falhou: \(error)") }
    }

    /// Teclas de mídia são eventos de sistema (NX_KEYTYPE_*), não teclas comuns.
    private static func media(_ key: MediaKey) {
        let code: Int = switch key {
        case .volumeUp: 0
        case .volumeDown: 1
        case .mute: 7
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
        for down in [true, false] {
            let state = down ? 0xa : 0xb
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                           modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                           data1: (code << 16) | (state << 8), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

/// Saída de áudio padrão pelo CoreAudio.
enum Audio {
    struct Device: Hashable {
        let uid: String
        let name: String
    }

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func outputs() -> [Device] {
        deviceIDs().compactMap { id in
            var streams = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &size) == noErr, size > 0,
                  let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return Device(uid: uid, name: name)
        }
    }

    static func defaultOutputUID() -> String? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &id) == noErr else { return nil }
        return string(id, kAudioDevicePropertyDeviceUID)
    }

    static func setDefaultOutput(uid: String) -> Bool {
        guard var id = deviceIDs().first(where: { string($0, kAudioDevicePropertyDeviceUID) == uid }) else { return false }
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        return AudioObjectSetPropertyData(system, &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id) == noErr
    }

    /// Avisa quando a saída padrão muda (pelo deck ou por fora), pra trocar o ícone da tecla.
    /// Devolve o que o `removeListener` precisa pra parar.
    static func onChange(_ block: @escaping () -> Void) -> AudioObjectPropertyListenerBlock {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { _, _ in block() }
        AudioObjectAddPropertyListenerBlock(system, &address, .main, listener)
        return listener
    }

    static func removeListener(_ listener: @escaping AudioObjectPropertyListenerBlock) {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(system, &address, .main, listener)
    }
}
