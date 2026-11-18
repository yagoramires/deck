import Foundation
import IOKit.hid

/// O que o D6 usa do IOKit. O --selftest troca por um falso: nunca abre o D6 de verdade.
protocol HIDPort: AnyObject {
    /// Procura e abre o D6: nil = não achou; senão o resultado do IOHIDDeviceOpen.
    func open() -> IOReturn?
    /// Teclas e remoção chegam no runloop principal até o `close()`.
    func listen(report: @escaping (UnsafeMutablePointer<UInt8>, CFIndex) -> Void, removed: @escaping () -> Void)
    /// Tira os callbacks do dispositivo e do runloop e fecha.
    func close()
    /// Chamado na fila de escrita.
    func send(_ packet: [UInt8]) -> IOReturn
}

/// fifine AmpliGame D6 por HID (protocolo MiraBox, ver re/PROTOCOL.md).
/// Teclas são numeradas 0–14 a partir do canto superior esquerdo, linha por linha.
final class D6 {
    static let vendorID = 0x3142, productID = 0x0007
    static let columns = 5, rows = 3
    static let keyCount = columns * rows
    static let reportSize = 512

    var onKey: ((Int, Bool) -> Void)?
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?
    private(set) var isOpen = false

    private let port: HIDPort
    private let writes = DispatchQueue(label: "local.deck.hid")
    private(set) var timer: Timer?
    /// Depois do stop() nada abre, nada é enviado e callbacks atrasados são ignorados.
    private(set) var stopped = false
    /// "Encontrado mas não abriu" vai pro log uma vez só, não a cada 2 s.
    private var reported = false
    /// Ligado no stop(): a fila de escrita pula o que ainda não saiu, menos o HAN.
    private let dropping = Flag()
    /// Quanto o stop() espera a fila antes de fechar assim mesmo.
    static let stopTimeout: TimeInterval = 1

    init(port: HIDPort = IOKitHID()) { self.port = port }

    /// Procura o deck a cada 2 s até abrir; o app da fifine segura o dispositivo enquanto estiver aberto.
    func start() {
        stopped = false
        dropping.set(false)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tryOpen() }
        tryOpen()
    }

    /// Desinstalar no NeyHub ou fechar o avulso: imagens na fila são puladas, o HAN sai se der tempo (até 1 s)
    /// e o D6 fica livre pro próximo dono.
    func stop() {
        stopped = true
        timer?.invalidate()
        timer = nil
        dropping.set(true)
        let drained = DispatchSemaphore(value: 0)
        writes.async { drained.signal() }
        if drained.wait(timeout: .now() + Self.stopTimeout) == .timedOut {
            Log.write("fila do D6 não esvaziou em \(Self.stopTimeout) s; fechando assim mesmo")
        }
        if isOpen { port.close() }
        isOpen = false
    }

    func flush() { writes.sync {} }

    func tryOpen() {
        guard !isOpen, !stopped, let result = port.open() else { return }
        guard result == kIOReturnSuccess else {
            if !reported { Log.write("D6 encontrado mas não abriu: 0x\(String(UInt32(bitPattern: result), radix: 16))") }
            reported = true
            return
        }
        reported = false
        isOpen = true
        port.listen(report: { [weak self] report, length in self?.received(report, length) },
                    removed: { [weak self] in self?.removed() })
        Log.write("D6 conectado")
        onConnect?()
    }

    private func removed() {
        guard !stopped, isOpen else { return }
        port.close()
        isOpen = false
        Log.write("D6 desconectado")
        onDisconnect?()
    }

    /// Tecla: "ACK..OK.." + [9] número 1–15 + [10] 1 apertou / 0 soltou.
    private func received(_ report: UnsafeMutablePointer<UInt8>, _ length: CFIndex) {
        guard !stopped, length >= 11, report[0] == 0x41, report[1] == 0x43, report[2] == 0x4b else { return }
        let key = Int(report[9])
        guard (1...Self.keyCount).contains(key) else { return }
        onKey?(key - 1, report[10] == 1)
    }

    // MARK: - Comandos

    func wake() { enqueue([[Self.command("DIS")]]) }
    func screenOff() { enqueue([[Self.command("HAN")]], keep: true) }
    func heartbeat() { enqueue([[Self.command("CONNECT")]]) }
    func setBrightness(_ percent: Int) { enqueue([[Self.command("LIG", [10: UInt8(clamping: percent)])]]) }

    /// O que o app oficial faz antes de desenhar: modo '2' (conectado) e limpar a tela inteira,
    /// senão fica o degradê de "desconectado" atrás das teclas.
    func takeOver() { enqueue([[Self.command("MOD", [10: 0x32])], [Self.command("CLE", [11: 0xff])]]) }

    /// Troca a imagem das teclas (JPEG 112 px, já girado); `nil` apaga a tecla.
    func update(_ keys: [(index: Int, jpeg: Data?)]) {
        guard !keys.isEmpty else { return }
        var groups: [[[UInt8]]] = []
        for (index, jpeg) in keys {
            let slot = UInt8(Self.imageSlot(index))
            guard let jpeg else {
                groups.append([Self.command("CLE", [11: slot])])
                continue
            }
            let n = jpeg.count, bytes = [UInt8](jpeg)
            var packets = [Self.command("BAT") + [UInt8(n >> 24 & 0xff), UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff), slot]]
            for offset in stride(from: 0, to: n, by: Self.reportSize) {
                packets.append(Array(bytes[offset..<min(offset + Self.reportSize, n)]))
            }
            groups.append(packets)
        }
        groups.append([Self.command("STP")])
        enqueue(groups)
    }

    /// Inverte a ordem das linhas, mantendo a coluna: as imagens contam a partir da linha de baixo e as teclas,
    /// da de cima (conferido no aparelho). Vale nos dois sentidos.
    static func mirroredRows(_ index: Int) -> Int { (rows - 1 - index / columns) * columns + index % columns }

    static func imageSlot(_ index: Int) -> Int { mirroredRows(index) + 1 }

    /// "CRT" + 2 zeros + nome do comando, com bytes extras em posições fixas.
    static func command(_ name: String, _ extra: [Int: UInt8] = [:]) -> [UInt8] {
        var packet = Array("CRT".utf8) + [0, 0] + Array(name.utf8)
        for (position, value) in extra {
            if packet.count <= position { packet += [UInt8](repeating: 0, count: position - packet.count + 1) }
            packet[position] = value
        }
        return packet
    }

    /// Cada grupo sai inteiro (um comando, ou o BAT com os dados de uma imagem): parar no meio de uma imagem
    /// faria o D6 ler o próximo comando como JPEG. Depois do stop() só os grupos com `keep` (o HAN) ainda saem.
    private func enqueue(_ groups: [[[UInt8]]], keep: Bool = false) {
        guard isOpen, !stopped else { return }
        writes.async { [port, dropping] in
            for group in groups {
                if !keep, dropping.isOn { return }
                for packet in group {
                    let buffer = packet + [UInt8](repeating: 0, count: max(0, Self.reportSize - packet.count))
                    let result = port.send(buffer)
                    if result != kIOReturnSuccess {
                        Log.write("envio falhou: 0x\(String(UInt32(bitPattern: result), radix: 16))")
                        return
                    }
                }
            }
        }
    }
}

/// Bool lido na fila de escrita e ligado no main.
private final class Flag {
    private let lock = NSLock()
    private var value = false
    var isOn: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func set(_ on: Bool) {
        lock.lock()
        value = on
        lock.unlock()
    }
}

/// O D6 de verdade pelo IOKit.
final class IOKitHID: HIDPort {
    private var device: IOHIDDevice?
    /// A fila de escrita lê o `device` enquanto o runloop principal pode fechar (D6 removido).
    private let lock = NSLock()
    private let input = UnsafeMutablePointer<UInt8>.allocate(capacity: D6.reportSize)
    private var handlers: Handlers?

    deinit {
        close()
        input.deallocate()
    }

    private final class Handlers {
        let report: (UnsafeMutablePointer<UInt8>, CFIndex) -> Void
        let removed: () -> Void
        init(_ report: @escaping (UnsafeMutablePointer<UInt8>, CFIndex) -> Void, _ removed: @escaping () -> Void) {
            self.report = report
            self.removed = removed
        }
    }

    func open() -> IOReturn? {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: D6.vendorID, kIOHIDProductIDKey: D6.productID] as CFDictionary)
        guard let found = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first else { return nil }
        let result = IOHIDDeviceOpen(found, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess { setDevice(found) }
        return result
    }

    func listen(report: @escaping (UnsafeMutablePointer<UInt8>, CFIndex) -> Void, removed: @escaping () -> Void) {
        guard let device = currentDevice() else { return }
        let box = Handlers(report, removed)
        handlers = box
        let context = Unmanaged.passUnretained(box).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, input, D6.reportSize, { context, _, _, _, _, report, length in
            Unmanaged<Handlers>.fromOpaque(context!).takeUnretainedValue().report(report, length)
        }, context)
        IOHIDDeviceRegisterRemovalCallback(device, { context, _, _ in
            Unmanaged<Handlers>.fromOpaque(context!).takeUnretainedValue().removed()
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    /// Pode ser chamado de novo (removido, stop, deinit): sem dispositivo não faz nada.
    func close() {
        guard let device = currentDevice() else { return }
        IOHIDDeviceRegisterInputReportCallback(device, input, D6.reportSize, nil, nil)
        IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        setDevice(nil)
        handlers = nil
    }

    func send(_ packet: [UInt8]) -> IOReturn {
        guard let device = currentDevice() else { return kIOReturnNotOpen }
        var buffer = packet
        return IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, &buffer, buffer.count)
    }

    private func currentDevice() -> IOHIDDevice? {
        lock.lock()
        defer { lock.unlock() }
        return device
    }

    private func setDevice(_ value: IOHIDDevice?) {
        lock.lock()
        device = value
        lock.unlock()
    }
}
