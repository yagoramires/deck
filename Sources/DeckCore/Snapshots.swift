import AppKit
import NeyKit
import SwiftUI

/// `Deck --snapshots <pasta>`: desenha o popover e as configurações em PNG com teclas de exemplo e sai.
/// Usa uma pasta temporária (config e ícones de exemplo), nunca a config de verdade, e não abre o D6.
enum Snapshots {
    static func run(into folder: URL) {
        Log.enabled = false
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deck-snapshots-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = sample(dir)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        func deck(connected: Bool = true, official: Bool = false, accessibility: Bool = false, hosted: Bool = false) -> DeckState {
            let deck = DeckState(popover: PopoverState(version: "0.2.0", hosted: hosted, updateReady: !hosted))
            deck.connected = connected
            deck.officialRunning = official
            deck.needsAccessibility = accessibility
            return deck
        }
        for (name, selected, state) in [("popover", nil, deck()), ("popover-editor", 1, deck()), ("popover-atalho", 5, deck()),
                                        ("popover-fifine", nil, deck(connected: false, official: true)),
                                        ("popover-neyhub", 3, deck(accessibility: true, hosted: true))] as [(String, Int?, DeckState)] {
            render(RootView(selected: selected).environmentObject(store).environmentObject(state), to: folder.appendingPathComponent("\(name).png"))
        }
        render(SettingsView(version: "0.2.0", hosted: false, presence: Presence(screen: false, menuBar: true), onPresence: { _ in },
                            grant: {}, trusted: { true }), to: folder.appendingPathComponent("settings.png"))
        render(SettingsView(version: "0.2.0", hosted: true, presence: nil, onPresence: { _ in }, grant: {}, trusted: { false }),
               to: folder.appendingPathComponent("settings-neyhub.png"))
        print("✓ \(folder.path)")
    }

    /// Três páginas de exemplo; os ícones são os dos apps do sistema, copiados pra pasta temporária.
    static func sample(_ dir: URL) -> Store {
        let store = Store(dir: dir)
        store.persist = false
        func icon(_ path: String) -> String? {
            let image = NSWorkspace.shared.icon(forFile: path)
            image.size = NSSize(width: 256, height: 256)
            return store.addIcon(image)
        }
        let music = icon("/System/Applications/Music.app"), messages = icon("/System/Applications/Messages.app")
        let terminal = icon("/System/Applications/Utilities/Terminal.app"), calendar = icon("/System/Applications/Calendar.app")
        var page = Config.emptyPage
        page[0] = Key(action: .openApp(path: "/System/Applications/Music.app"), icon: music, styled: true, title: "")
        page[1] = Key(action: .openApp(path: "/System/Applications/Messages.app"), icon: messages, styled: true, title: "Mensagens")
        page[2] = Key(action: .website(url: "https://calendar.google.com"), icon: calendar, title: "Agenda")
        page[3] = Key(action: .media(.playPause), title: "Play")
        page[4] = Key(action: .audioToggle(first: "", second: ""), title: "Fone ↔ Caixa")
        page[5] = Key(action: .hotkey(keyCode: 21, modifiers: 0x120000, label: "⇧⌘4"), title: "⇧⌘4")
        page[6] = Key(action: .openApp(path: "/System/Applications/Utilities/Terminal.app"), icon: terminal, title: "")
        page[8] = Key(action: .media(.volumeDown), title: "Vol −")
        page[9] = Key(action: .media(.volumeUp), title: "Vol +")
        page[13] = Key(action: .previousPage, title: "◀ Página")
        page[14] = Key(action: .nextPage, title: "Página ▶")
        var config = Config()
        config.pages = [page, Config.emptyPage, Config.emptyPage]
        config.pages[1][0] = Key(action: .previousPage, title: "◀")
        store.config = config
        return store
    }

    /// Desenha a tela numa janela fora da vista e grava o PNG.
    private static func render(_ root: some View, to file: URL) {
        let view = NSHostingView(rootView: root)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.setContentSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
        // Os controles do AppKit só desenham depois de uma volta no runloop.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: file)
    }
}
