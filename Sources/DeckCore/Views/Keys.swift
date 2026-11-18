import AppKit
import NeyKit
import SwiftUI
import UniformTypeIdentifiers

/// Uma tecla do D6: o que ela mostra no aparelho. No popover 74 pt; na tela, do tamanho que couber e com o número.
struct KeyTile: View {
    @EnvironmentObject var store: Store
    let index: Int
    @Binding var selected: Int?
    var side: CGFloat = 74
    var numbered = false
    @ViewState var targeted = false

    var body: some View {
        let radius = side * 0.14
        ZStack {
            if let key = store.key(index) {
                Image(nsImage: Render.tile(key, store: store)).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: radius)
                    .fill(Grafite.card)
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(Grafite.ghostBorder)
                Image(systemName: "plus").foregroundStyle(Grafite.label)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay(alignment: .topTrailing) {
            if numbered {
                Text("\(index + 1)").font(.system(size: 9)).foregroundStyle(Grafite.label).padding(.top, 5).padding(.trailing, 7)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: radius + 3)
                .stroke(selected == index ? Grafite.accent : targeted ? Color.white.opacity(0.6) : .clear, lineWidth: 2)
                .padding(-3)
        )
        .contentShape(Rectangle())
        .onTapGesture { selected = index }
        .onDrag { NSItemProvider(object: String(index) as NSString) }
        .onDrop(of: [.fileURL, .text], isTargeted: $targeted) { providers in drop(providers) }
        .accessibilityElement()
        .accessibilityLabel("Tecla \(index + 1)\(store.key(index).map { $0.title.isEmpty ? "" : ", \($0.title)" } ?? ", vazia")")
        .accessibilityAddTraits(selected == index ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selected = index }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            loadDroppedFile(provider) { url in
                store.setIcon(from: url, index: index)
                selected = index
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

/// Arquivo solto do Finder: entrega a URL no main.
private func loadDroppedFile(_ provider: NSItemProvider, _ use: @escaping (URL) -> Void) {
    _ = provider.loadObject(ofClass: URL.self) { url, _ in
        guard let url else { return }
        DispatchQueue.main.async { use(url) }
    }
}

/// As teclas do D6 na posição real: linhas de cima pra baixo, número = linha * colunas + coluna.
struct KeyGrid<Tile: View>: View {
    let spacing: CGFloat
    @ViewBuilder let tile: (Int) -> Tile

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<D6.rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<D6.columns, id: \.self) { column in tile(row * D6.columns + column) }
                }
            }
        }
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

    /// Rótulo dos campos da ação na tela; nil = ação sem campos.
    var fieldTitle: String? {
        switch self {
        case .app: "App"
        case .website: "Site"
        case .hotkey: "Atalho"
        case .media: "Tecla"
        case .audio: "Saídas"
        case .none, .nextPage, .previousPage: nil
        }
    }
}

extension View {
    /// A caixa de campo do mockup (fundo escuro, borda fina); `on` false deixa como está (popover).
    @ViewBuilder func fieldBox(_ on: Bool = true) -> some View {
        if on {
            padding(.horizontal, 9).padding(.vertical, 7)
                .background(Grafite.field, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Grafite.border, lineWidth: 1))
        } else {
            self
        }
    }
}

/// Editor de uma tecla. No popover abre embaixo da grade; na tela (`wide`) fica sempre aberto ao lado,
/// com as ações em lista. Os dois gravam pelo mesmo `KeyEditor.binding` → `Store.setKey`.
struct KeyEditor: View {
    @EnvironmentObject var store: Store
    let index: Int
    var wide = false
    @ViewState var recording: Any?
    @ViewState var targeted = false

    private var key: Binding<Key> { Self.binding(store, index) }

    static func binding(_ store: Store, _ index: Int) -> Binding<Key> {
        Binding(get: { store.key(index) ?? Key() }, set: { store.setKey(index, $0) })
    }

    private var kind: Binding<ActionKind> {
        Binding(get: { ActionKind(key.wrappedValue.action) }, set: { key.wrappedValue.action = $0.empty })
    }

    var body: some View {
        Group { if wide { screenBody } else { popoverBody } }
            .onDisappear { stopRecording() }
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                iconColumn
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Ação", selection: kind) {
                        ForEach(ActionKind.allCases) { Text($0.label).tag($0) }
                    }
                    fields
                    TextField("Título (opcional)", text: key.title)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Grafite.strong)
                        .fieldBox()
                }
            }
            HStack {
                neon
                Spacer()
                Chip(title: "Apagar tecla") { store.setKey(index, nil) }
            }
        }
        .font(.system(size: 12))
    }

    private var iconColumn: some View {
        VStack(spacing: 6) {
            Image(nsImage: Render.tile(key.wrappedValue, store: store))
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            iconButtons
        }
        .frame(width: 92)
    }

    @ViewBuilder private var iconButtons: some View {
        Chip(title: "Imagem…") { chooseImage(alt: false) }
        if case .openApp(let path) = key.wrappedValue.action, !path.isEmpty {
            Chip(title: "Ícone do app") { useAppIcon(path) }
        }
        if case .audioToggle = key.wrappedValue.action {
            Chip(title: "Imagem B…") { chooseImage(alt: true) }.help("Aparece quando a saída B está ativa")
        }
    }

    private var neon: some View {
        HStack(spacing: 2) {
            Text("Estilo neon").foregroundStyle(Grafite.muted)
            GSwitch(isOn: key.styled, label: "Estilo neon")
        }
        .disabled(key.wrappedValue.icon == nil)
        .opacity(key.wrappedValue.icon == nil ? 0.4 : 1)
    }

    // MARK: Tela

    private var screenBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Tecla \(index + 1)").font(.system(size: 13, weight: .bold)).foregroundStyle(Grafite.strong)
                Spacer()
                Text("página \(store.page + 1)").font(.system(size: 11)).foregroundStyle(Grafite.muted)
            }
            label("Ação")
            VStack(alignment: .leading, spacing: 3) {
                ForEach(ActionKind.allCases) { option in
                    let on = kind.wrappedValue == option
                    Button { kind.wrappedValue = option } label: {
                        Text(option.label)
                            .foregroundStyle(on ? Grafite.strong : Grafite.muted)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(on ? Grafite.rowOn : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(alignment: .leading) { if on { Rectangle().fill(Grafite.accent).frame(width: 2) } }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if let title = kind.wrappedValue.fieldTitle {
                label(title)
                fields
            }
            label("Ícone e rótulo")
            HStack(spacing: 10) {
                drop
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Rótulo (opcional)", text: key.title)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Grafite.strong)
                        .fieldBox()
                    neon
                }
            }
            HStack(spacing: 6) { iconButtons }.padding(.top, 8)
            HStack { Chip(title: "Limpar tecla") { store.setKey(index, nil) } }.padding(.top, 12)
        }
        .font(.system(size: 12))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Grafite.card, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Grafite.border, lineWidth: 1))
    }

    private var drop: some View {
        Button { chooseImage(alt: false) } label: {
            ZStack {
                if key.wrappedValue.icon != nil || !key.wrappedValue.title.isEmpty {
                    Image(nsImage: Render.tile(key.wrappedValue, store: store)).resizable().interpolation(.high)
                } else {
                    Image(systemName: "photo").font(.system(size: 20)).foregroundStyle(Grafite.label)
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(targeted ? Grafite.accent : Grafite.ghostBorder))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Escolher imagem, ou solte uma imagem aqui")
        .accessibilityLabel("Ícone da tecla \(index + 1)")
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            loadDroppedFile(provider) { store.setIcon(from: $0, index: index) }
            return true
        }
    }

    private func label(_ text: String) -> some View {
        GSectionLabel(text).padding(.top, 12).padding(.bottom, 6)
    }

    // MARK: Campos de cada ação

    @ViewBuilder private var fields: some View {
        switch key.wrappedValue.action {
        case .openApp(let path):
            HStack {
                Text(path.isEmpty ? "Nenhum app escolhido" : FileManager.default.displayName(atPath: path))
                    .lineLimit(1)
                    .foregroundStyle(path.isEmpty ? Grafite.muted : Grafite.strong)
                Spacer()
                Button("Escolher…") { chooseApp() }.buttonStyle(.plain).foregroundStyle(Grafite.accent)
            }
            .fieldBox(wide)
        case .website(let url):
            TextField("https://…", text: Binding(get: { url }, set: { key.wrappedValue.action = .website(url: $0) }))
                .textFieldStyle(.plain)
                .foregroundStyle(Grafite.strong)
                .fieldBox()
        case .hotkey(_, _, let label):
            HStack {
                Text(recording != nil ? "Aperte o atalho…" : label.isEmpty ? "Nenhum atalho" : label)
                    .monospaced()
                    .foregroundStyle(label.isEmpty || recording != nil ? Grafite.muted : Grafite.strong)
                Spacer()
                Button(recording != nil ? "Cancelar" : "Gravar") { recording != nil ? stopRecording() : startRecording() }
                    .buttonStyle(.plain).foregroundStyle(Grafite.accent)
            }
            .fieldBox(wide)
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
            if event.keyCode == 53, modifiers.isEmpty {
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
