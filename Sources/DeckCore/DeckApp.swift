import AppKit
import Combine
import CoreAudio
import NeyKit
import ServiceManagement
import SwiftUI

/// Estado do deck e a ponte entre as telas (popover e tela de app) e o DeckApp.
final class DeckState: ObservableObject {
    static let officialBundleID = "com.fifine.fifinecontroldeck"
    @Published var connected = false
    @Published var officialRunning = false
    @Published var popover: PopoverState
    /// Hospedado, com tecla de atalho/mídia e o NeyHub sem Acessibilidade.
    @Published var needsAccessibility = false
    var grant: () -> Void = {}
    var showSettings: () -> Void = {}
    var relaunch: () -> Void = {}

    init(popover: PopoverState = PopoverState(version: "", hosted: false)) { self.popover = popover }

    func closeOfficial() {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.officialBundleID).forEach { $0.terminate() }
    }
}

/// O que muda no popover entre o avulso e o NeyHub.
struct PopoverState: Equatable {
    var version: String
    var hosted: Bool
    var updateReady = false

    /// Hospedado o login é o do NeyHub.
    var showsLoginItem: Bool { !hosted }
    /// Hospedado fecharia o NeyHub inteiro.
    var showsQuit: Bool { !hosted }
    /// Hospedado as configurações ficam no card do NeyHub.
    var showsSettings: Bool { !hosted }
    /// Hospedado quem atualiza é o NeyHub.
    var showsUpdate: Bool { updateReady && !hosted }
}

/// O Deck inteiro, sem a casca: o avulso (`Deck`) e o plugin do NeyHub (`DeckPlugin`) usam o mesmo.
public final class DeckApp: NSObject, NSPopoverDelegate {
    private let defaults: UserDefaults
    /// Dentro do NeyHub: sem item de login, sem "Sair" e sem pedir Acessibilidade ao sistema.
    private let hosted: Bool
    let store: Store
    let deck: DeckState
    let d6: D6
    let accessibility: Accessibility
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var outsideClicks: Any?
    private var subscriptions = Set<AnyCancellable>()
    private var heartbeat: Timer?
    private var observers: [NSObjectProtocol] = []
    private var audioListener: AudioObjectPropertyListenerBlock?
    private var settingsWindow: NSWindow?
    private var screenWindow: NSWindow?
    /// O JPEG que cada tecla mostra agora, pra mandar só o que mudou.
    private var sent: [Int: Data?] = [:]
    private var sentBrightness: Int?

    /// Hospedado: o NeyHub liga à tela de Permissões dele (a Acessibilidade é do NeyHub).
    public var onOpenPermissions: (() -> Void)?
    /// Avulso: o Updater já preparou uma versão, que entra quando o app fechar.
    public var updateReady = false { didSet { deck.popover.updateReady = updateReady } }
    /// Avulso: "Reiniciar agora" ao lado da linha de atualização; a casca liga ao `Updater.relaunchNow`.
    public var onRelaunch: (() -> Void)?

    public convenience init(defaults: UserDefaults, hosted: Bool, version: String) {
        self.init(defaults: defaults, hosted: hosted, version: version, dir: Store.defaultDir, port: IOKitHID())
    }

    /// `dir` e `port` só mudam no selftest: pasta temporária e um D6 falso.
    init(defaults: UserDefaults, hosted: Bool, version: String, dir: URL, port: HIDPort) {
        self.defaults = defaults
        self.hosted = hosted
        store = Store(dir: dir)
        deck = DeckState(popover: PopoverState(version: version, hosted: hosted))
        d6 = D6(port: port)
        accessibility = Accessibility(hosted: hosted)
        super.init()
        accessibility.onUntrusted = { [weak self] in self?.refreshAccessibility(untrusted: true) }
        deck.grant = { [weak self] in self?.grantAccessibility() }
        deck.showSettings = { [weak self] in
            self?.popover.performClose(nil)
            self?.showSettings()
        }
        // Hospedado quem atualiza e reinicia é o NeyHub.
        deck.relaunch = { [weak self] in if self?.hosted == false { self?.onRelaunch?() } }
    }

    public func start() {
        if store.isNew, store.importOfficial() {
            Log.write("primeira abertura: config importada do app da fifine")
        }

        d6.onConnect = { [weak self] in self?.connected() }
        d6.onDisconnect = { [weak self] in self?.deck.connected = false }
        d6.onKey = { [weak self] index, pressed in self?.pressed(index, down: pressed) }
        d6.start()

        store.objectWillChange
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.redraw()
                self?.refreshAccessibility()
            }
            .store(in: &subscriptions)
        audioListener = Audio.onChange { [weak self] in self?.redraw() }

        // shortcut: heartbeat igual ao do app oficial, sem saber se o firmware precisa; tirar se não fizer falta.
        heartbeat = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.d6.heartbeat()
            // A Acessibilidade chega pelos Ajustes com o Deck aberto.
            self?.refreshAccessibility()
        }

        let center = NSWorkspace.shared.notificationCenter
        func observe(_ names: [Notification.Name], _ block: @escaping (DeckApp) -> Void) {
            for name in names {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    if let self { block(self) }
                })
            }
        }
        observe([NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification]) { $0.d6.screenOff() }
        observe([NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification]) { $0.connected() }
        observe([NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]) { $0.checkOfficial() }
        checkOfficial()
        refreshAccessibility()

        // No NeyHub o login é dele.
        if !hosted, !defaults.bool(forKey: "loginItemOffered") {
            defaults.set(true, forKey: "loginItemOffered")
            do { try SMAppService.mainApp.register() } catch { Log.write("abrir ao iniciar falhou: \(error)") }
        }
        Log.write("iniciou\(hosted ? " no NeyHub" : "") · \(store.config.pages.count) páginas")
    }

    /// Desinstalar no NeyHub (ou fechar o avulso): grava, apaga as telas e solta o D6 pro próximo dono.
    public func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        if let audioListener { Audio.removeListener(audioListener) }
        audioListener = nil
        subscriptions = []
        store.saveNow()
        d6.screenOff()
        d6.stop()
        d6.onConnect = nil
        d6.onDisconnect = nil
        d6.onKey = nil
        deck.connected = false
        accessibility.onUntrusted = {}
        setMenuBarVisible(false)
        removeOutsideClicks()
        settingsWindow?.close()
        screenWindow?.close()
        Log.write("parou")
    }

    /// false REMOVE o ícone; true cria com autosaveName "local.deck" (a posição na barra é lembrada).
    public func setMenuBarVisible(_ visible: Bool) {
        if !visible, let statusItem {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        } else if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "local.deck"
            item.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Deck")
            item.button?.target = self
            item.button?.action = #selector(toggle)
            statusItem = item
        }
    }

    public func makeScreen() -> NSViewController {
        NSHostingController(rootView: ScreenView().environmentObject(store).environmentObject(deck))
    }

    public func makeSettings() -> NSViewController {
        NSHostingController(rootView: SettingsView(
            version: deck.popover.version, hosted: hosted,
            presence: hosted ? nil : presence,
            onPresence: { [weak self] presence in
                guard let self else { return }
                presence.save(defaults)
                applyPresence(presence)
            },
            grant: { [weak self] in self?.grantAccessibility() },
            trusted: { [accessibility] in accessibility.isTrusted() }))
    }

    public static func runSnapshots(into folder: URL) { Snapshots.run(into: folder) }

    /// `Deck --icon <entrada> <saída>`: aplica o estilo neon numa imagem, sem tocar na config.
    public static func styleIcon(_ input: String, to output: String) {
        guard let image = NSImage(contentsOfFile: input) else { fatalError("não abriu \(input)") }
        let styled = IconStyle.make(image)
        let png = NSBitmapImageRep(cgImage: styled.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
            .representation(using: .png, properties: [:])!
        try! png.write(to: URL(fileURLWithPath: output))
    }

    // MARK: Avulso

    /// Modo do avulso. Sem escolha salva fica só na barra de menus, como na 0.1.0 (o padrão do NeyKit com tela seria "os dois").
    public var presence: Presence {
        Presence.load(defaults, hasScreen: false).normalized(hasScreen: true)
    }

    /// Avulso: troca o modo na hora, sem reiniciar. Tela = ícone no Dock + janela; barra de menus = o ícone do Deck.
    public func applyPresence(_ presence: Presence) {
        setMenuBarVisible(presence.menuBar)
        guard !hosted else { return }
        NSApp.setActivationPolicy(presence.screen ? .regular : .accessory)
        if presence.screen { showScreen() } else { screenWindow?.close() }
    }

    public func showScreen() {
        if screenWindow == nil {
            screenWindow = window(makeScreen(), title: "Deck")
            screenWindow?.setContentSize(NSSize(width: 820, height: 560))
        }
        bringToFront(screenWindow)
    }

    /// Janela de configurações do avulso: Configurações… no popover ou o menu do app no modo Tela.
    public func showSettings() {
        if settingsWindow == nil { settingsWindow = window(makeSettings(), title: "Configurações do Deck") }
        bringToFront(settingsWindow)
    }

    private func window(_ controller: NSViewController, title: String) -> NSWindow {
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func bringToFront(_ window: NSWindow?) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Acessibilidade

    /// Só conta hospedado: no avulso o macOS pede na primeira tecla, como sempre.
    private func refreshAccessibility(untrusted: Bool = false) {
        guard hosted else { return }
        let needs = untrusted || (Self.usesAccessibility(store.config) && !accessibility.isTrusted())
        if deck.needsAccessibility != needs { deck.needsAccessibility = needs }
    }

    /// Atalho de teclado e tecla de mídia simulam teclas; as outras ações não precisam de permissão.
    static func usesAccessibility(_ config: Config) -> Bool {
        config.pages.joined().contains { key in
            switch key?.action {
            case .hotkey, .media: true
            default: false
            }
        }
    }

    /// Hospedado abre a tela de Permissões do NeyHub; avulso, o pedido do sistema.
    private func grantAccessibility() {
        if hosted { onOpenPermissions?() } else { accessibility.askSystem() }
    }

    // MARK: D6

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
        Perform.run(key.action, store: store, accessibility: accessibility)
    }

    // MARK: Popover

    @objc private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem?.button else { return }
        if popover.contentViewController == nil {
            let host = NSHostingController(rootView: RootView().environmentObject(store).environmentObject(deck))
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
            popover.appearance = NSAppearance(named: .darkAqua)
            // O painel de escolher arquivo é do próprio app; .transient fecharia a janelinha quando ele abre.
            popover.behavior = .applicationDefined
            popover.delegate = self
        }
        refreshAccessibility()
        // App de barra não é ativo: sem isso os campos de texto não recebem teclado.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Clique em outro app fecha; cliques no próprio app (painéis de arquivo) não chegam aqui.
        if outsideClicks == nil {
            outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.popover.performClose(nil)
            }
        }
    }

    public func popoverDidClose(_ notification: Notification) { removeOutsideClicks() }

    private func removeOutsideClicks() {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
    }
}
