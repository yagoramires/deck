import Foundation
import IOKit.hid

/// fifine AmpliGame D6 por HID (protocolo MiraBox, ver re/PROTOCOL.md).
/// Teclas são numeradas 0–14 a partir do canto superior esquerdo, linha por linha.
final class D6 {
    static let vendorID = 0x3142, productID = 0x0007
    static let reportSize = 512

    var onKey: ((Int, Bool) -> Void)?
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?
    private(set) var isOpen = false

    private var device: IOHIDDevice?
    private let input = UnsafeMutablePointer<UInt8>.allocate(capacity: reportSize)
    private let writes = DispatchQueue(label: "local.deck.hid")
    private var timer: Timer?

    /// Procura o deck a cada 2 s até abrir; o app da fifine segura o dispositivo enquanto estiver aberto.
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tryOpen() }
        tryOpen()
    }

    func tryOpen() {
        guard !isOpen else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: Self.productID] as CFDictionary)
        guard let found = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first else { return }
        let result = IOHIDDeviceOpen(found, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            if device == nil { Log.write("D6 encontrado mas não abriu: 0x\(String(UInt32(bitPattern: result), radix: 16))") }
            device = found
            return
        }
        device = found
        isOpen = true
        let me = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(found, input, Self.reportSize, { context, _, _, _, _, report, length in
            Unmanaged<D6>.fromOpaque(context!).takeUnretainedValue().received(report, length)
        }, me)
        IOHIDDeviceRegisterRemovalCallback(found, { context, _, _ in
            Unmanaged<D6>.fromOpaque(context!).takeUnretainedValue().removed()
        }, me)
        IOHIDDeviceScheduleWithRunLoop(found, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        Log.write("D6 conectado")
        onConnect?()
    }

    private func removed() {
        if let device { IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) }
        device = nil
        isOpen = false
        Log.write("D6 desconectado")
        onDisconnect?()
    }

    /// Tecla: "ACK..OK.." + [9] número 1–15 + [10] 1 apertou / 0 soltou.
    private func received(_ report: UnsafeMutablePointer<UInt8>, _ length: CFIndex) {
        guard length >= 11, report[0] == 0x41, report[1] == 0x43, report[2] == 0x4b else { return }
        let key = Int(report[9])
        guard (1...15).contains(key) else { return }
        onKey?(key - 1, report[10] == 1)
    }

    // MARK: - Comandos

    func wake() { enqueue([Self.command("DIS")]) }
    func screenOff() { enqueue([Self.command("HAN")]) }
    func heartbeat() { enqueue([Self.command("CONNECT")]) }
    func setBrightness(_ percent: Int) { enqueue([Self.command("LIG", [10: UInt8(clamping: percent)])]) }

    /// O que o app oficial faz antes de desenhar: modo '2' (conectado) e limpar a tela inteira,
    /// senão fica o degradê de "desconectado" atrás das teclas.
    func takeOver() { enqueue([Self.command("MOD", [10: 0x32]), Self.command("CLE", [11: 0xff])]) }

    /// Troca a imagem das teclas (JPEG 112 px, já girado); `nil` apaga a tecla.
    func update(_ keys: [(index: Int, jpeg: Data?)]) {
        guard !keys.isEmpty else { return }
        var packets: [[UInt8]] = []
        for (index, jpeg) in keys {
            let slot = UInt8(Self.imageSlot(index))
            guard let jpeg else {
                packets.append(Self.command("CLE", [11: slot]))
                continue
            }
            let n = jpeg.count, bytes = [UInt8](jpeg)
            packets.append(Self.command("BAT") + [UInt8(n >> 24 & 0xff), UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff), slot])
            for offset in stride(from: 0, to: n, by: Self.reportSize) {
                packets.append(Array(bytes[offset..<min(offset + Self.reportSize, n)]))
            }
        }
        packets.append(Self.command("STP"))
        enqueue(packets)
    }

    /// As imagens contam a partir da linha de baixo; as teclas, da de cima (conferido no aparelho).
    static func imageSlot(_ index: Int) -> Int { (2 - index / 5) * 5 + index % 5 + 1 }

    /// "CRT" + 2 zeros + nome do comando, com bytes extras em posições fixas.
    static func command(_ name: String, _ extra: [Int: UInt8] = [:]) -> [UInt8] {
        var packet = Array("CRT".utf8) + [0, 0] + Array(name.utf8)
        for (position, value) in extra {
            if packet.count <= position { packet += [UInt8](repeating: 0, count: position - packet.count + 1) }
            packet[position] = value
        }
        return packet
    }

    private func enqueue(_ packets: [[UInt8]]) {
        guard isOpen, let device else { return }
        writes.async {
            for packet in packets {
                var buffer = packet + [UInt8](repeating: 0, count: max(0, Self.reportSize - packet.count))
                let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, &buffer, buffer.count)
                if result != kIOReturnSuccess {
                    Log.write("envio falhou: 0x\(String(UInt32(bitPattern: result), radix: 16))")
                    return
                }
            }
        }
    }
}
