import AppKit
import DeckCore
import NeyKitApp

/// Casca do avulso: o Deck em si mora no DeckCore, o mesmo que o NeyHub carrega como plugin.
final class DeckAppDelegate: NSObject, NSApplicationDelegate {
    private var deck: DeckApp?
    private var updater: Updater?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if HubCheck.isHosted(id: "local.deck") && HubCheck.leaveForHub(id: "local.deck", name: "Deck") { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let deck = DeckApp(defaults: .standard, hosted: false, version: version)
        deck.start()
        setupMenu()
        deck.applyPresence(deck.presence)
        self.deck = deck

        let updater = Updater(name: "Deck", repo: "yagoramires/deck", id: "local.deck")
        deck.updateReady = updater.staged != nil
        updater.onChange = { [weak deck, weak updater] in deck?.updateReady = updater?.staged != nil }
        deck.onRelaunch = { [weak updater] in updater?.relaunchNow() }
        updater.start()
        self.updater = updater
        // Toda abertura: mostra as novidades uma vez e limpa um preparado velho.
        if let notes = Updater.notesAfterUpdate(id: "local.deck", current: version) {
            WhatsNew.show(name: "Deck", version: version, notes: notes)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        deck?.stop()
        _ = updater?.applyStaged()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let deck, deck.presence.screen else { return true }
        deck.showScreen()
        return false
    }

    /// No modo Tela (com ícone no Dock) o menu do app é o caminho até as configurações sem o ícone da barra.
    private func setupMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Configurações…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Sair do Deck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        // Editar: sem ele ⌘C/⌘V/⌘Z não chegam aos campos de texto (título, site).
        let edit = NSMenu(title: "Editar")
        for (title, action, key, mods) in [("Desfazer", "undo:", "z", NSEvent.ModifierFlags.command), ("Refazer", "redo:", "z", [.command, .shift]),
                                           ("Recortar", "cut:", "x", .command), ("Copiar", "copy:", "c", .command),
                                           ("Colar", "paste:", "v", .command), ("Selecionar tudo", "selectAll:", "a", .command)] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key).keyEquivalentModifierMask = mods
            if action == "redo:" { edit.addItem(.separator()) }
        }
        let editItem = NSMenuItem()
        editItem.submenu = edit
        NSApp.mainMenu = NSMenu()
        NSApp.mainMenu?.addItem(item)
        NSApp.mainMenu?.addItem(editItem)
    }

    @objc private func showSettings() { deck?.showSettings() }
}
