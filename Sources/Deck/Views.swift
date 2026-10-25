import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// O mesmo que @State. No SDK atual @State virou macro, e o plugin dele só vem com o Xcode;
/// como o build usa só as CommandLineTools, embrulhamos o State à mão (igual ao Dose).
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private var state: State<Value>
    init(wrappedValue: Value) { state = State(initialValue: wrappedValue) }
    var wrappedValue: Value {
        get { state.wrappedValue }
        nonmutating set { state.wrappedValue = newValue }
    }
    var projectedValue: Binding<Value> { state.projectedValue }
}

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var deck: DeckState
    @ViewState var selected: Int?
    @ViewState var confirmDeletePage = false
    @ViewState var confirmImport = false

    init(selected: Int? = nil) { _selected = ViewState(wrappedValue: selected) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if deck.officialRunning { officialBanner }
            pageBar
            grid
            Divider()
            if let selected {
                KeyEditor(index: selected).id("\(store.page)-\(selected)")
            } else {
                Text("Clique numa tecla pra configurar. Arraste uma tecla pra trocar de lugar, ou solte uma imagem em cima dela pra virar o ícone.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 470)
        .onChange(of: store.page) { _, _ in selected = nil }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(deck.connected ? Color.green : Color.secondary).frame(width: 8, height: 8)
            Text(deck.connected ? "D6 conectado" : "D6 desconectado").font(.headline)
            Spacer()
            Image(systemName: "sun.min").foregroundStyle(.secondary)
            Slider(value: Binding(get: { Double(store.config.brightness) },
                                  set: { store.config.brightness = Int($0) }), in: 10...100)
                .frame(width: 110)
                .help("Brilho das telas")
            Image(systemName: "sun.max").foregroundStyle(.secondary)
        }
    }

    private var officialBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("O app da fifine está aberto e segurando o deck.")
            Spacer()
            Button("Fechar ele") { deck.closeOfficial() }
        }
        .font(.callout)
        .padding(8)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var pageBar: some View {
        HStack(spacing: 10) {
            Button { store.page -= 1 } label: { Image(systemName: "chevron.left") }
                .disabled(store.page == 0)
            Text("Página \(store.page + 1) de \(store.config.pages.count)").monospacedDigit()
            Button { store.page += 1 } label: { Image(systemName: "chevron.right") }
                .disabled(store.page == store.config.pages.count - 1)
            Spacer()
            Button { store.addPage() } label: { Label("Nova página", systemImage: "plus") }
            Button { confirmDeletePage = true } label: { Image(systemName: "trash") }
                .disabled(store.config.pages.count == 1)
                .help("Apagar esta página")
        }
        .buttonStyle(.borderless)
        .alert("Apagar a página \(store.page + 1)?", isPresented: $confirmDeletePage) {
            Button("Apagar", role: .destructive) { store.removePage() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("As teclas dessa página somem.")
        }
    }

    private var grid: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { column in
                        KeyTile(index: row * 5 + column, selected: $selected)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private var footer: some View {
        HStack {
            LoginToggle()
            Spacer()
            Button("Importar do app da fifine") { confirmImport = true }
                .disabled(Importer.profile() == nil)
            Button("Sair") { NSApp.terminate(nil) }
        }
        .font(.callout)
        .alert("Importar do app da fifine?", isPresented: $confirmImport) {
            Button("Importar", role: .destructive) { store.importOfficial() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Todas as páginas daqui são trocadas pelas do app da fifine.")
        }
    }
}

struct LoginToggle: View {
    @ViewState var on = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Abrir ao iniciar", isOn: Binding(get: { on }, set: { value in
            do {
                if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                Log.write("abrir ao iniciar: \(error)")
            }
            on = SMAppService.mainApp.status == .enabled
        }))
        .toggleStyle(.checkbox)
    }
}

struct KeyTile: View {
    @EnvironmentObject var store: Store
    let index: Int
    @Binding var selected: Int?
    @ViewState var targeted = false

    var body: some View {
        ZStack {
            if let key = store.key(index) {
                Image(nsImage: Render.tile(key, store: store)).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                Image(systemName: "plus").foregroundStyle(.tertiary)
            }
        }
        .frame(width: 74, height: 74)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selected == index ? Color.accentColor : targeted ? Color.white.opacity(0.6) : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture { selected = index }
        .onDrag { NSItemProvider(object: String(index) as NSString) }
        .onDrop(of: [.fileURL, .text], isTargeted: $targeted) { providers in drop(providers) }
    }

    /// Imagem do Finder vira o ícone; outra tecla arrastada troca de lugar com esta.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    store.setIcon(from: url, index: index)
                    selected = index
                }
            }
            return true
        }
        _ = provider.loadObject(ofClass: NSString.self) { text, _ in
            guard let from = (text as? String).flatMap(Int.init), from != index else { return }
            DispatchQueue.main.async {
                store.swap(from, index)
                selected = index
            }
        }
        return true
    }
}

enum ActionKind: String, CaseIterable, Identifiable {
    case none, app, website, hotkey, media, audio, nextPage, previousPage
    var id: String { rawValue }

    init(_ action: Action) {
        self = switch action {
        case .none: .none
        case .openApp: .app
        case .website: .website
        case .hotkey: .hotkey
        case .media: .media
        case .audioToggle: .audio
        case .nextPage: .nextPage
        case .previousPage: .previousPage
        }
    }

    var label: String {
        switch self {
        case .none: "Nada"
        case .app: "Abrir app"
        case .website: "Abrir site"
        case .hotkey: "Atalho de teclado"
        case .media: "Tecla de mídia"
        case .audio: "Alternar saída de áudio"
        case .nextPage: "Próxima página"
        case .previousPage: "Página anterior"
        }
    }

    var empty: Action {
        switch self {
        case .none: .none
        case .app: .openApp(path: "")
        case .website: .website(url: "")
        case .hotkey: .hotkey(keyCode: 0, modifiers: 0, label: "")
        case .media: .media(.playPause)
        case .audio: .audioToggle(first: "", second: "")
        case .nextPage: .nextPage
        case .previousPage: .previousPage
        }
    }
}

struct KeyEditor: View {
    @EnvironmentObject var store: Store
    let index: Int
    @ViewState var recording: Any?

    private var key: Binding<Key> {
        Binding(get: { store.key(index) ?? Key() }, set: { store.setKey(index, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                iconColumn
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Ação", selection: Binding(get: { ActionKind(key.wrappedValue.action) },
                                                      set: { key.wrappedValue.action = $0.empty })) {
                        ForEach(ActionKind.allCases) { Text($0.label).tag($0) }
                    }
                    fields
                    TextField("Título (opcional)", text: key.title)
                }
            }
            HStack {
                Toggle("Estilo neon no ícone", isOn: key.styled)
                    .toggleStyle(.checkbox)
                    .disabled(key.wrappedValue.icon == nil)
                Spacer()
                Button("Apagar tecla", role: .destructive) { store.setKey(index, nil) }
            }
            .font(.callout)
        }
        .onDisappear { stopRecording() }
    }

    private var iconColumn: some View {
        VStack(spacing: 6) {
            Image(nsImage: Render.tile(key.wrappedValue, store: store))
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            Button("Imagem…") { chooseImage(alt: false) }
            if case .openApp(let path) = key.wrappedValue.action, !path.isEmpty {
                Button("Ícone do app") { useAppIcon(path) }
            }
            if case .audioToggle = key.wrappedValue.action {
                Button("Imagem B…") { chooseImage(alt: true) }.help("Aparece quando a saída B está ativa")
            }
        }
        .controlSize(.small)
        .frame(width: 92)
    }

    @ViewBuilder private var fields: some View {
        switch key.wrappedValue.action {
        case .openApp(let path):
            HStack {
                Text(path.isEmpty ? "Nenhum app escolhido" : FileManager.default.displayName(atPath: path))
                    .lineLimit(1)
                    .foregroundStyle(path.isEmpty ? .secondary : .primary)
                Spacer()
                Button("Escolher…") { chooseApp() }
            }
        case .website(let url):
            TextField("https://…", text: Binding(get: { url }, set: { key.wrappedValue.action = .website(url: $0) }))
        case .hotkey(_, _, let label):
            HStack {
                Text(recording != nil ? "Aperte o atalho…" : label.isEmpty ? "Nenhum atalho" : label)
                    .monospaced()
                    .foregroundStyle(label.isEmpty || recording != nil ? .secondary : .primary)
                Spacer()
                Button(recording != nil ? "Cancelar" : "Gravar") { recording != nil ? stopRecording() : startRecording() }
            }
        case .media(let media):
            Picker("Tecla", selection: Binding(get: { media }, set: { key.wrappedValue.action = .media($0) })) {
                ForEach(MediaKey.allCases, id: \.self) { Text($0.label).tag($0) }
            }
        case .audioToggle(let first, let second):
            let outputs = Audio.outputs()
            Picker("Saída A", selection: Binding(get: { first }, set: { key.wrappedValue.action = .audioToggle(first: $0, second: second) })) {
                deviceOptions(outputs, current: first)
            }
            Picker("Saída B", selection: Binding(get: { second }, set: { key.wrappedValue.action = .audioToggle(first: first, second: $0) })) {
                deviceOptions(outputs, current: second)
            }
        case .none, .nextPage, .previousPage:
            EmptyView()
        }
    }

    /// Dispositivo desconectado continua na lista, pra não perder a escolha.
    @ViewBuilder private func deviceOptions(_ outputs: [Audio.Device], current: String) -> some View {
        Text("Escolha…").tag("")
        ForEach(outputs, id: \.uid) { Text($0.name).tag($0.uid) }
        if !current.isEmpty, !outputs.contains(where: { $0.uid == current }) {
            Text("Desconectado").tag(current)
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        key.wrappedValue.action = .openApp(path: url.path)
        if key.wrappedValue.icon == nil { useAppIcon(url.path) }
    }

    private func useAppIcon(_ path: String) {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 256, height: 256)
        guard let name = store.addIcon(icon) else { return }
        key.wrappedValue.icon = name
        key.wrappedValue.styled = true
    }

    private func chooseImage(alt: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setIcon(from: url, index: index, alt: alt)
    }

    private func startRecording() {
        recording = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if event.keyCode == 53, modifiers.isEmpty { // Esc sozinho cancela
                stopRecording()
                return nil
            }
            // Os bits de NSEvent.ModifierFlags são os mesmos do CGEventFlags.
            key.wrappedValue.action = .hotkey(keyCode: event.keyCode, modifiers: UInt64(modifiers.rawValue),
                                              label: Self.symbols(modifiers) + Self.name(event))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let recording { NSEvent.removeMonitor(recording) }
        recording = nil
    }

    static func symbols(_ modifiers: NSEvent.ModifierFlags) -> String {
        (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "")
    }

    static func name(_ event: NSEvent) -> String {
        let special: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Espaço", 51: "⌫", 53: "⎋", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        return special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
    }
}
