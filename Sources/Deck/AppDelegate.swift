import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class DeckState: ObservableObject {
    static let officialBundleID = "com.fifine.fifinecontroldeck"
    @Published var connected = false
    @Published var officialRunning = false

    func closeOfficial() {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.officialBundleID).forEach { $0.terminate() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = Store()
    private let deck = DeckState()
    private let d6 = D6()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var outsideClicks: Any?
    private var subscriptions = Set<AnyCancellable>()
    /// O JPEG que cada tecla mostra agora, pra mandar só o que mudou.
    private var sent: [Int: Data?] = [:]
    private var sentBrightness: Int?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if store.isNew, store.importOfficial() {
            Log.write("primeira abertura: config importada do app da fifine")
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Deck")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)

        let host = NSHostingController(rootView: RootView().environmentObject(store).environmentObject(deck))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        // O painel de escolher arquivo é do próprio app; .transient fecharia a janelinha quando ele abre.
        popover.behavior = .applicationDefined
        popover.delegate = self

        d6.onConnect = { [weak self] in self?.connected() }
        d6.onDisconnect = { [weak self] in self?.deck.connected = false }
        d6.onKey = { [weak self] index, pressed in self?.pressed(index, down: pressed) }
        d6.start()

        store.objectWillChange
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] in self?.redraw() }
            .store(in: &subscriptions)
        Audio.onChange { [weak self] in self?.redraw() }

        // shortcut: heartbeat igual ao do app oficial, sem saber se o firmware precisa; tirar se não fizer falta.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.d6.heartbeat() }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.d6.screenOff() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.connected() }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.checkOfficial() }
        }
        checkOfficial()

        if !UserDefaults.standard.bool(forKey: "loginItemOffered") {
            UserDefaults.standard.set(true, forKey: "loginItemOffered")
            do { try SMAppService.mainApp.register() } catch { Log.write("abrir ao iniciar falhou: \(error)") }
        }
        Log.write("iniciou · \(store.config.pages.count) páginas")
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
        d6.screenOff()
        Thread.sleep(forTimeInterval: 0.1) // deixa o comando sair antes do processo acabar
    }

    private func checkOfficial() {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: DeckState.officialBundleID).isEmpty
        deck.officialRunning = running
        // Ao fechar, o app da fifine deixa o deck no modo desconectado: assumimos de novo.
        if !running {
            d6.tryOpen()
            connected()
        }
    }

    /// Conectou ou acordou: liga a tela e manda tudo de novo.
    private func connected() {
        guard d6.isOpen else { return }
        deck.connected = true
        sent = [:]
        sentBrightness = nil
        d6.wake()
        d6.takeOver()
        redraw()
    }

    private func redraw() {
        guard d6.isOpen else { return }
        if sentBrightness != store.config.brightness {
            sentBrightness = store.config.brightness
            d6.setBrightness(store.config.brightness)
        }
        var changes: [(index: Int, jpeg: Data?)] = []
        for (index, key) in store.keys.enumerated() {
            let jpeg = key.map { Render.jpeg(Render.tile($0, store: store)) }
            if sent[index] != .some(jpeg) {
                sent[index] = .some(jpeg)
                changes.append((index, jpeg))
            }
        }
        d6.update(changes)
    }

    private func pressed(_ index: Int, down: Bool) {
        guard down, let key = store.key(index) else { return }
        Log.write("tecla \(index + 1): \(key.action)")
        Perform.run(key.action, store: store)
    }

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        // App de barra não é ativo: sem isso os campos de texto não recebem teclado.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Clique em outro app fecha; cliques no próprio app (painéis de arquivo) não chegam aqui.
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
    }
}
