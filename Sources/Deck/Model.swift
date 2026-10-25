import AppKit

enum MediaKey: String, Codable, CaseIterable {
    case playPause, next, previous, volumeUp, volumeDown, mute

    var label: String {
        switch self {
        case .playPause: "Tocar/pausar"
        case .next: "Próxima faixa"
        case .previous: "Faixa anterior"
        case .volumeUp: "Aumentar volume"
        case .volumeDown: "Diminuir volume"
        case .mute: "Mudo"
        }
    }
}

enum Action: Codable, Equatable {
    case none
    case openApp(path: String)
    case website(url: String)
    case hotkey(keyCode: UInt16, modifiers: UInt64, label: String)
    case media(MediaKey)
    /// Alterna a saída de áudio padrão entre dois dispositivos (UIDs do CoreAudio).
    case audioToggle(first: String, second: String)
    case nextPage, previousPage
}

struct Key: Codable, Equatable {
    var action: Action = .none
    /// Arquivo em icons/; `altIcon` aparece quando o segundo dispositivo de áudio está ativo.
    var icon: String?
    var altIcon: String?
    /// Aplica o estilo neon (IconStyle) ao desenhar.
    var styled = false
    var title = ""
}

struct Config: Codable, Equatable {
    static let keys = 15
    var pages: [[Key?]] = [Config.emptyPage]
    var brightness = 80
    static var emptyPage: [Key?] { Array(repeating: nil, count: keys) }
}

final class Store: ObservableObject {
    static let defaultDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Deck")
    let dir: URL
    var icons: URL { dir.appendingPathComponent("icons") }
    private var url: URL { dir.appendingPathComponent("config.json") }
    /// Desligado no --snapshots e no --selftest, que não podem mexer na config de verdade.
    var persist = true
    private(set) var isNew = false

    @Published var config = Config() { didSet { scheduleSave() } }
    @Published var page = 0
    private var pendingSave: DispatchWorkItem?
    private var imageCache: [String: NSImage] = [:]

    init(dir: URL = Store.defaultDir) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: url) else {
            isNew = true
            return
        }
        do {
            config = try JSONDecoder().decode(Config.self, from: data)
            // Arquivo editado à mão pode vir com páginas de outro tamanho.
            config.pages = config.pages.map { Array(($0 + Config.emptyPage).prefix(Config.keys)) }
            if config.pages.isEmpty { config.pages = [Config.emptyPage] }
        } catch {
            // Nunca sobrescrever uma config que não deu pra ler: fica guardada ao lado.
            let aside = dir.appendingPathComponent("config-ilegivel-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            Log.write("config ilegível (\(error)), guardada em \(aside.lastPathComponent)")
            isNew = true
        }
    }

    var keys: [Key?] { config.pages[page] }
    func key(_ index: Int) -> Key? { config.pages[page][index] }
    func setKey(_ index: Int, _ key: Key?) { config.pages[page][index] = key }
    func swap(_ a: Int, _ b: Int) { config.pages[page].swapAt(a, b) }

    func addPage() {
        config.pages.insert(Config.emptyPage, at: page + 1)
        page += 1
    }

    func removePage() {
        guard config.pages.count > 1 else { return }
        let removed = page
        page = max(0, page - 1)
        config.pages.remove(at: removed)
    }

    /// Troca pela config do app da fifine (perfil do D6). Falso se não achar nada.
    @discardableResult
    func importOfficial() -> Bool {
        guard let imported = Importer.load(into: self) else { return false }
        page = 0
        config = imported
        return true
    }

    // MARK: - Ícones

    /// Copia uma imagem pra icons/ e devolve o nome; nil se não for imagem.
    func addIcon(from source: URL) -> String? {
        guard NSImage(contentsOf: source) != nil else { return nil }
        let name = UUID().uuidString + "." + (source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased())
        do {
            try FileManager.default.copyItem(at: source, to: icons.appendingPathComponent(name))
            return name
        } catch {
            Log.write("copiar ícone falhou: \(error)")
            return nil
        }
    }

    func addIcon(_ image: NSImage) -> String? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return nil }
        let name = UUID().uuidString + ".png"
        do {
            try png.write(to: icons.appendingPathComponent(name))
            return name
        } catch {
            Log.write("salvar ícone falhou: \(error)")
            return nil
        }
    }

    func setIcon(from source: URL, index: Int, alt: Bool = false) {
        guard let name = addIcon(from: source) else { return }
        var key = key(index) ?? Key()
        if alt { key.altIcon = name } else { key.icon = name }
        key.styled = true
        setKey(index, key)
    }

    func image(for key: Key, alt: Bool) -> NSImage? {
        guard let name = (alt ? key.altIcon : nil) ?? key.icon else { return nil }
        let cacheKey = key.styled ? name + "#neon" : name
        if let cached = imageCache[cacheKey] { return cached }
        guard let raw = NSImage(contentsOf: icons.appendingPathComponent(name)) else { return nil }
        let image = key.styled ? IconStyle.make(raw) : raw
        imageCache[cacheKey] = image
        return image
    }

    // MARK: - Salvar

    private func scheduleSave() {
        guard persist else { return }
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    func saveNow() {
        guard persist else { return }
        pendingSave?.cancel()
        pendingSave = nil
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: url, options: .atomic)
        } catch {
            Log.write("salvar falhou: \(error)")
        }
    }
}

/// Lê o perfil do D6 do app fifine Control Deck (formato StreamDock da MiraBox).
enum Importer {
    static let profiles = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/HotSpot/StreamDock/profiles")

    static func profile() -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil)) ?? []
        let candidates = items.filter { $0.pathExtension == "sdProfile" }
        return candidates.first { (manifest($0)?["DeviceUUID"] as? String) == "D6" } ?? candidates.first
    }

    static func manifest(_ dir: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func load(into store: Store) -> Config? {
        guard let root = profile(), let rootManifest = manifest(root) else { return nil }
        // A primeira página é o próprio perfil; as outras ficam em profiles/ dentro dele.
        var dirs = [root]
        let names = ((rootManifest["Pages"] as? [String: Any])?["Pages"] as? [String]) ?? []
        for name in names where name != root.lastPathComponent {
            dirs.append(root.appendingPathComponent("profiles").appendingPathComponent(name))
        }
        var config = Config()
        config.pages = dirs.compactMap { dir in manifest(dir).map { page($0, dir: dir, store: store) } }
        guard !config.pages.isEmpty else { return nil }
        Log.write("importou \(config.pages.count) páginas de \(root.lastPathComponent)")
        return config
    }

    static func page(_ manifest: [String: Any], dir: URL, store: Store) -> [Key?] {
        var keys = Config.emptyPage
        for (position, action) in (manifest["Actions"] as? [String: [String: Any]]) ?? [:] {
            guard let index = index(position) else { continue }
            keys[index] = key(action, dir: dir, store: store)
        }
        return keys
    }

    /// "coluna,linha" → número da tecla a partir do canto superior esquerdo. No app da fifine a
    /// linha 0 é a de baixo (conferido com a tela dele).
    static func index(_ position: String) -> Int? {
        let parts = position.split(separator: ",").compactMap { Int($0) }
        guard parts.count == 2, (0..<5).contains(parts[0]), (0..<3).contains(parts[1]) else { return nil }
        return (2 - parts[1]) * 5 + parts[0]
    }

    static func key(_ action: [String: Any], dir: URL, store: Store) -> Key {
        let settings = action["Settings"] as? [String: Any] ?? [:]
        let states = action["States"] as? [[String: Any]] ?? []
        func icon(_ state: Int) -> String? {
            guard states.indices.contains(state), let name = states[state]["Image"] as? String else { return nil }
            return store.addIcon(from: dir.appendingPathComponent("Images").appendingPathComponent(name))
        }
        var key = Key(icon: icon(0), title: states.first?["Title"] as? String ?? "")
        switch action["UUID"] as? String ?? "" {
        case "com.hotspot.streamdock.system.open":
            key.action = .openApp(path: settings["path"] as? String ?? "")
        case "com.hotspot.streamdock.system.openApps":
            // appId é a posição do app escolhido na lista `applications`.
            let apps = settings["applications"] as? [[String: Any]] ?? []
            if let id = settings["appId"] as? Int, apps.indices.contains(id) {
                key.action = .openApp(path: apps[id]["path"] as? String ?? "")
            }
        case "com.hotspot.streamdock.system.website":
            key.action = .website(url: settings["path"] as? String ?? "")
        case "com.hotspot.streamdock.page.next":
            key.action = .nextPage
        case "com.hotspot.streamdock.page.previous":
            key.action = .previousPage
        case "com.mirabox.streamdock.switchAudio.myaction1":
            key.action = .audioToggle(first: settings["select"] as? String ?? "", second: settings["select2"] as? String ?? "")
            key.altIcon = icon(1)
        default:
            Log.write("importar: ação sem equivalente \(action["UUID"] ?? "?")")
        }
        return key
    }
}
