import AppKit
import IOKit
import NeyKit

/// `Deck --selftest`. Sem XCTest (só CommandLineTools). Nunca abre o D6 (a porta HID é um falso), nunca lê nem
/// grava a config de verdade (pasta temporária), nunca grava no `.standard` (é o domínio do Deck em uso),
/// nunca simula tecla nem pede permissão e nunca fecha o app da fifine.
extension DeckApp {
    public static func selfTest() {
        Log.enabled = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deck-selftest-\(UUID())")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        protocolBasics(folder)
        storeLoads(folder)
        d6Stop()
        appStop(folder)
        accessibility(folder)
        popover()
    }

    /// Suite temporária no lugar do `.standard`; o chamador apaga. Nome fixo: não junta um plist por rodada.
    /// `UserDefaults(suiteName:)` direto só aqui: o app usa `AppDefaults.forApp`; o teste quer um domínio descartável.
    private static func tempDefaults() -> (UserDefaults, String) {
        let name = "deck.selftest"
        return (UserDefaults(suiteName: name)!, name)
    }

    private static func spin(_ seconds: TimeInterval = 0.05) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// Os testes da 0.1.0: posições das teclas, comandos, Key em JSON e o import do app da fifine (só leitura, numa pasta temporária).
    static func protocolBasics(_ folder: URL) {
        precondition(D6.imageSlot(0) == 11 && D6.imageSlot(4) == 15 && D6.imageSlot(10) == 1 && D6.imageSlot(14) == 5)
        precondition(Importer.index("4,1") == 9 && Importer.index("0,2") == 0 && Importer.index("0,0") == 10 && Importer.index("5,0") == nil)
        precondition(D6.command("LIG", [10: 80]) == Array("CRT".utf8) + [0, 0] + Array("LIG".utf8) + [0, 0, 80])
        let key = Key(action: .hotkey(keyCode: 0, modifiers: 1 << 20, label: "⌘A"), title: "x")
        precondition(try! JSONDecoder().decode(Key.self, from: JSONEncoder().encode(key)) == key)
        if Importer.profile() != nil {
            let store = Store(dir: folder.appendingPathComponent("import"))
            store.persist = false
            precondition(store.importOfficial() && !store.config.pages.isEmpty && store.config.pages.allSatisfy { $0.count == Config.keys })
        }
    }

    /// Um config.json de exemplo (página curta, como um arquivo editado à mão) abre inteiro; um ilegível fica guardado ao lado.
    static func storeLoads(_ parent: URL) {
        let fm = FileManager.default
        let dir = parent.appendingPathComponent("config")
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        {"brightness":55,"pages":[
          [{"action":{"openApp":{"path":"/System/Applications/Music.app"}},"icon":"musica.png","styled":true,"title":"Música"},null,
           {"action":{"media":{"_0":"playPause"}},"styled":false,"title":"Play"}],
          [null,{"action":{"nextPage":{}},"styled":false,"title":"›"}]
        ]}
        """
        try! Data(json.utf8).write(to: dir.appendingPathComponent("config.json"))
        let store = Store(dir: dir)
        precondition(!store.isNew && store.config.brightness == 55 && store.config.pages.count == 2, "\(store.config)")
        precondition(store.config.pages.allSatisfy { $0.count == Config.keys })
        precondition(store.key(0) == Key(action: .openApp(path: "/System/Applications/Music.app"), icon: "musica.png", styled: true, title: "Música"))
        precondition(store.key(1) == nil && store.key(2)?.action == .media(.playPause) && store.config.pages[1][1]?.action == .nextPage)
        precondition(try! fm.contentsOfDirectory(atPath: dir.path).sorted() == ["config.json", "icons"])

        let broken = parent.appendingPathComponent("quebrado")
        try! fm.createDirectory(at: broken, withIntermediateDirectories: true)
        try! Data("{".utf8).write(to: broken.appendingPathComponent("config.json"))
        let fresh = Store(dir: broken)
        precondition(fresh.isNew && fresh.config == Config())
        precondition(try! fm.contentsOfDirectory(atPath: broken.path).contains { $0.hasPrefix("config-ilegivel-") })
    }

    /// Review Focus 1: depois do stop() o D6 está fechado, o timer de 2 s parou, a fila de escrita esvaziou e
    /// nenhum callback (atrasado) faz nada.
    static func d6Stop() {
        let port = FakeHID()
        let d6 = D6(port: port)
        var keys = 0, disconnects = 0
        d6.onKey = { _, _ in keys += 1 }
        d6.onDisconnect = { disconnects += 1 }
        d6.start()
        precondition(d6.isOpen && port.opens == 1 && port.listening && d6.timer?.isValid == true)
        port.press(3)
        precondition(keys == 1)
        d6.wake()
        d6.update([(index: 0, jpeg: Data([1, 2, 3])), (index: 1, jpeg: nil)])
        d6.stop()
        // wake + BAT + dados + CLE + STP: o que estava na fila saiu antes de fechar.
        precondition(port.sentCount == 5, "\(port.sentCount)")
        precondition(!d6.isOpen && port.closes == 1 && !port.listening && port.closedAfterLastSend, "\(port)")
        precondition(d6.timer == nil)
        port.press(4)
        port.remove()
        precondition(keys == 1 && disconnects == 0, "callback depois do stop")
        d6.tryOpen()
        d6.wake()
        d6.flush()
        precondition(port.opens == 1 && port.sentCount == 5, "abriu ou enviou depois do stop")

        // Removido: fecha (callbacks fora) e o timer tenta de novo.
        let other = FakeHID()
        let again = D6(port: other)
        again.onDisconnect = { disconnects += 1 }
        again.start()
        other.remove()
        precondition(!again.isOpen && other.closes == 1 && disconnects == 1 && again.timer?.isValid == true)
        again.stop()
        precondition(other.closes == 1, "fechou duas vezes")
    }

    /// O DeckApp hospedado: stop() solta o D6 (apaga as telas antes), tira observadores e timers, e não toca no login.
    static func appStop(_ folder: URL) {
        let (d, name) = tempDefaults()
        defer { d.removePersistentDomain(forName: name) }
        let before = UserDefaults.standard.object(forKey: "loginItemOffered") as? Bool
        let port = FakeHID()
        let app = DeckApp(defaults: d, hosted: true, version: "9.8.7", dir: sampleDir(folder, "app"), port: port)
        app.start()
        precondition(port.opens == 1 && app.d6.isOpen)
        precondition(d.object(forKey: "loginItemOffered") == nil, "hospedado mexeu no login")
        precondition(UserDefaults.standard.object(forKey: "loginItemOffered") as? Bool == before)
        app.d6.flush()
        let sent = port.sentCount
        precondition(sent > 0, "conectou sem desenhar")
        app.stop()
        precondition(port.closes == 1 && !port.listening && !app.d6.isOpen && app.d6.timer == nil)
        // O HAN (apagar as telas) sai antes de fechar.
        precondition(port.sentCount == sent + 1 && port.last == D6.command("HAN") + [UInt8](repeating: 0, count: D6.reportSize - 8))
        port.press(0)
        app.store.setKey(0, Key(action: .nextPage, title: "x"))
        spin(0.2)
        precondition(port.sentCount == sent + 1, "redesenhou depois do stop")
    }

    /// Hospedado só confere a Acessibilidade (nunca pede ao sistema) e mostra o aviso com Conceder → Permissões do NeyHub.
    static func accessibility(_ folder: URL) {
        let saved = (Perform.isTrusted, Perform.askSystem, Perform.hosted)
        defer { (Perform.isTrusted, Perform.askSystem, Perform.hosted) = saved }
        var asked = 0
        Perform.isTrusted = { false }
        Perform.askSystem = { asked += 1 }
        let store = Store(dir: folder.appendingPathComponent("ax"))
        store.persist = false

        let (d, name) = tempDefaults()
        defer { d.removePersistentDomain(forName: name) }
        let hosted = DeckApp(defaults: d, hosted: true, version: "9.8.7", dir: sampleDir(folder, "ax-hosted"), port: FakeHID())
        var opened = 0
        hosted.onOpenPermissions = { opened += 1 }
        hosted.start()
        precondition(hosted.deck.needsAccessibility, "config com atalho e sem permissão: sem aviso")
        Perform.run(.hotkey(keyCode: 0, modifiers: 0, label: "A"), store: store)
        Perform.run(.media(.mute), store: store)
        precondition(asked == 0, "hospedado pediu Acessibilidade ao sistema")
        hosted.deck.grant()
        precondition(opened == 1 && asked == 0)
        Perform.isTrusted = { true }
        hosted.store.config.brightness = 70
        spin(0.2)
        precondition(!hosted.deck.needsAccessibility, "aviso não sumiu com a permissão")
        hosted.stop()

        // Avulso: igual à 0.1.0, o macOS pede na primeira tecla; nada de aviso.
        Perform.isTrusted = { false }
        let alone = DeckApp(defaults: d, hosted: false, version: "9.8.7", dir: sampleDir(folder, "ax-alone"), port: FakeHID())
        precondition(!Perform.hosted)
        Perform.run(.hotkey(keyCode: 0, modifiers: 0, label: "A"), store: store)
        precondition(asked == 1 && !alone.deck.needsAccessibility)
    }

    /// Hospedado: sem Sair, sem login, sem Configurações e sem a linha de atualização.
    static func popover() {
        let hosted = PopoverState(version: "9.8.7", hosted: true, updateReady: true)
        let alone = PopoverState(version: "9.8.7", hosted: false, updateReady: true)
        precondition(!hosted.showsQuit && !hosted.showsLoginItem && !hosted.showsSettings && !hosted.showsUpdate, "\(hosted)")
        precondition(alone.showsQuit && alone.showsLoginItem && alone.showsSettings && alone.showsUpdate, "\(alone)")
        let (d, name) = tempDefaults()
        defer { d.removePersistentDomain(forName: name) }
        let app = DeckApp(defaults: d, hosted: true, version: "9.8.7", dir: FileManager.default.temporaryDirectory
            .appendingPathComponent("deck-selftest-popover-\(UUID())"), port: FakeHID())
        defer { try? FileManager.default.removeItem(at: app.store.dir) }
        app.updateReady = true
        var relaunched = 0
        app.onRelaunch = { relaunched += 1 }
        app.deck.relaunch()
        precondition(app.deck.popover == hosted && relaunched == 0, "hospedado reiniciou pela casca")
    }

    /// Pasta temporária com um config.json pequeno (uma tecla de atalho), pra não cair no import da primeira abertura.
    private static func sampleDir(_ folder: URL, _ name: String) -> URL {
        let dir = folder.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var config = Config()
        config.pages[0][0] = Key(action: .hotkey(keyCode: 0, modifiers: 0, label: "A"), title: "A")
        try! JSONEncoder().encode(config).write(to: dir.appendingPathComponent("config.json"))
        return dir
    }
}

/// D6 de mentira: conta o que o D6 pediu e dispara teclas/remoção à mão, mesmo depois do close (callback atrasado).
final class FakeHID: HIDPort, CustomStringConvertible {
    var opens = 0, closes = 0, listening = false
    private var report: ((UnsafeMutablePointer<UInt8>, CFIndex) -> Void)?
    private var removal: (() -> Void)?
    /// Escrito na fila de escrita do D6; lido depois de um flush/stop.
    private(set) var sentCount = 0
    private(set) var last: [UInt8] = []
    private(set) var closedAfterLastSend = false

    func open() -> IOReturn? {
        opens += 1
        return kIOReturnSuccess
    }

    func listen(report: @escaping (UnsafeMutablePointer<UInt8>, CFIndex) -> Void, removed: @escaping () -> Void) {
        listening = true
        self.report = report
        removal = removed
    }

    func close() {
        closes += 1
        listening = false
        closedAfterLastSend = true
    }

    func send(_ packet: [UInt8]) -> IOReturn {
        precondition(listening, "envio com o dispositivo fechado")
        sentCount += 1
        last = packet
        closedAfterLastSend = false
        return kIOReturnSuccess
    }

    /// "ACK" + ... + [9] tecla 1–15 + [10] 1 = apertou.
    func press(_ index: Int) {
        var bytes = [UInt8](repeating: 0, count: D6.reportSize)
        bytes[0] = 0x41; bytes[1] = 0x43; bytes[2] = 0x4b
        bytes[9] = UInt8(index + 1); bytes[10] = 1
        bytes.withUnsafeMutableBufferPointer { report?($0.baseAddress!, 11) }
    }

    func remove() { removal?() }

    var description: String { "FakeHID(opens: \(opens), closes: \(closes), listening: \(listening), enviados: \(sentCount))" }
}
