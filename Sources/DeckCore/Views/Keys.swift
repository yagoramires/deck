import AppKit
import NeyKit
import SwiftUI
import UniformTypeIdentifiers

/// Uma tecla do D6: o que ela mostra no aparelho.
struct KeyTile: View {
    @EnvironmentObject var store: Store
    let index: Int
    @Binding var selected: Int?
    @ViewState var targeted = false

    var body: some View {
        let side: CGFloat = 74, radius: CGFloat = 10
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

/// Editor de uma tecla, embaixo da grade do popover.
struct KeyEditor: View {
    @EnvironmentObject var store: Store
    let index: Int
    @ViewState var recording: Any?

    private var key: Binding<Key> { Self.binding(store, index) }

    /// A tecla `index` da página atual; mudar grava no config.json (Store).
    static func binding(_ store: Store, _ index: Int) -> Binding<Key> {
        Binding(get: { store.key(index) ?? Key() }, set: { store.setKey(index, $0) })
    }

    private var kind: Binding<ActionKind> {
        Binding(get: { ActionKind(key.wrappedValue.action) }, set: { key.wrappedValue.action = $0.empty })
    }

    var body: some View {
        popoverBody
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
            .fieldBox(false)
        case .website(let url):
            TextField("https://…", text: Binding(get: { url }, set: { key.wrappedValue.action = .website(url: $0) }))
                .textFieldStyle(.plain)
                .foregroundStyle(Grafite.strong)
                .fieldBox(true)
        case .hotkey(_, _, let label):
            HStack {
                Text(recording != nil ? "Aperte o atalho…" : label.isEmpty ? "Nenhum atalho" : label)
                    .monospaced()
                    .foregroundStyle(label.isEmpty || recording != nil ? Grafite.muted : Grafite.strong)
                Spacer()
                Button(recording != nil ? "Cancelar" : "Gravar") { recording != nil ? stopRecording() : startRecording() }
                    .buttonStyle(.plain).foregroundStyle(Grafite.accent)
            }
            .fieldBox(false)
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
