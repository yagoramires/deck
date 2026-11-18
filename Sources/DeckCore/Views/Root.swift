import NeyKit
import ServiceManagement
import SwiftUI

/// O popover da barra: a mesma navegação da 0.1.0, no tema Grafite.
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
            if deck.officialRunning { OfficialBanner() }
            if deck.needsAccessibility { AccessibilityBanner() }
            pageBar
            grid
            Line()
            if let selected {
                KeyEditor(index: selected).id("\(store.page)-\(selected)")
            } else {
                Text("Clique numa tecla pra configurar. Arraste uma tecla pra trocar de lugar, ou solte uma imagem em cima dela pra virar o ícone.")
                    .font(.system(size: 12)).foregroundStyle(Grafite.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Line()
            footer
        }
        .padding(14)
        .frame(width: 470)
        .tint(Grafite.accent)
        .grafiteWindow()
        .onChange(of: store.page) { _, _ in selected = nil }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Status()
            Spacer()
            Brightness(width: 110)
        }
    }

    private var pageBar: some View {
        HStack(spacing: 10) {
            Button { store.turnPage(by: -1) } label: { Image(systemName: "chevron.left") }
                .disabled(store.page == 0)
            Text("Página \(store.page + 1) de \(store.config.pages.count)").monospacedDigit().font(.system(size: 12))
            Button { store.turnPage(by: 1) } label: { Image(systemName: "chevron.right") }
                .disabled(store.page == store.config.pages.count - 1)
            Spacer()
            Chip(title: "+ Nova página") { store.addPage() }
            Button { confirmDeletePage = true } label: { Image(systemName: "trash") }
                .disabled(store.config.pages.count == 1)
                .help("Apagar esta página")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Grafite.ghostText)
        .deletePageAlert($confirmDeletePage)
    }

    private var grid: some View {
        KeyGrid(spacing: 8) { KeyTile(index: $0, selected: $selected) }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Grafite.deck, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Grafite.border, lineWidth: 1))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if deck.popover.showsUpdate {
                HStack {
                    Text("Atualização pronta — entra ao sair").font(.system(size: 11)).foregroundStyle(Grafite.accent)
                    Spacer()
                    GPill(title: "Reiniciar agora") { deck.relaunch() }
                }
            }
            HStack(spacing: 6) {
                if deck.popover.showsLoginItem { LoginToggle() }
                Spacer()
                Chip(title: "Importar do app da fifine") { confirmImport = true }
                    .disabled(Importer.profile() == nil)
                if deck.popover.showsSettings { Chip(title: "Configurações…") { deck.showSettings() } }
                if deck.popover.showsQuit { Chip(title: "Sair") { NSApp.terminate(nil) } }
            }
        }
        .importAlert($confirmImport)
    }
}

struct LoginToggle: View {
    @ViewState var on = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack(spacing: 2) {
            GSwitch(isOn: Binding(get: { on }, set: { value in
                do {
                    if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    Log.write("abrir ao iniciar: \(error)")
                }
                on = SMAppService.mainApp.status == .enabled
            }), label: "Abrir ao iniciar")
            Text("Abrir ao iniciar").font(.system(size: 11)).foregroundStyle(Grafite.muted).fixedSize()
        }
    }
}

// MARK: Peças comuns (popover e tela)

struct Status: View {
    @EnvironmentObject var deck: DeckState
    var font: Font = .system(size: 13, weight: .bold)
    var color: Color = Grafite.strong

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(deck.connected ? Grafite.accent : Grafite.label).frame(width: 7, height: 7)
            Text(deck.connected ? "D6 conectado" : "D6 desconectado").font(font).foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }
}

struct Brightness: View {
    @EnvironmentObject var store: Store
    let width: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sun.min").foregroundStyle(Grafite.muted)
            Slider(value: Binding(get: { Double(store.config.brightness) },
                                  set: { store.config.brightness = Int($0) }), in: 10...100)
                .frame(width: width)
                .help("Brilho das telas")
                .accessibilityLabel("Brilho das telas")
            Image(systemName: "sun.max").foregroundStyle(Grafite.muted)
        }
    }
}

struct OfficialBanner: View {
    @EnvironmentObject var deck: DeckState

    var body: some View {
        Banner(text: "O app da fifine está aberto e segurando o deck.", action: "Fechar o app da fifine") { deck.closeOfficial() }
    }
}

/// Hospedado: a Acessibilidade é do NeyHub; Conceder leva à tela de Permissões dele.
struct AccessibilityBanner: View {
    @EnvironmentObject var deck: DeckState

    var body: some View {
        Banner(text: "Precisa de Acessibilidade pra simular atalhos e teclas de mídia.", action: "Conceder") { deck.grant() }
    }
}

struct Banner: View {
    let text: String
    let action: String
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button(action: perform) { Text(action).bold().underline() }.buttonStyle(.plain)
        }
        .font(.system(size: 11))
        .foregroundStyle(Grafite.warn)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Grafite.warnBg, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Grafite.warnBorder, lineWidth: 1))
    }
}

/// Botão discreto (o ".g" do mockup).
struct Chip: View {
    @Environment(\.isEnabled) private var enabled
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11)).foregroundStyle(Grafite.ghostText).fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Grafite.card, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Grafite.border, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// Divisória no tom da borda do Grafite (o Divider do sistema some no fundo escuro).
struct Line: View {
    var body: some View { Rectangle().fill(Grafite.border).frame(height: 1) }
}

extension View {
    func deletePageAlert(_ shown: Binding<Bool>) -> some View { modifier(DeletePageAlert(shown: shown)) }
    func importAlert(_ shown: Binding<Bool>) -> some View { modifier(ImportAlert(shown: shown)) }
}

private struct DeletePageAlert: ViewModifier {
    @EnvironmentObject var store: Store
    @Binding var shown: Bool

    func body(content: Content) -> some View {
        content.alert("Apagar a página \(store.page + 1)?", isPresented: $shown) {
            Button("Apagar", role: .destructive) { store.removePage() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("As teclas dessa página somem.")
        }
    }
}

private struct ImportAlert: ViewModifier {
    @EnvironmentObject var store: Store
    @Binding var shown: Bool

    func body(content: Content) -> some View {
        content.alert("Importar do app da fifine?", isPresented: $shown) {
            Button("Importar", role: .destructive) { store.importOfficial() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Todas as páginas daqui são trocadas pelas do app da fifine.")
        }
    }
}

extension Grafite {
    // O Grafite não tem cor de alerta nem o fundo do D6; vêm do mockup aprovado.
    static let warn = color(hex: "#ffb03d") ?? .orange
    static let warnBg = color(hex: "#2a2110") ?? .clear
    static let warnBorder = color(hex: "#5a4416") ?? .clear
    static let deck = color(hex: "#0c0d0f") ?? .black
    static let field = color(hex: "#121316") ?? .black
    static let rowOn = color(hex: "#22252b") ?? .clear
    static let tabOn = color(hex: "#2a2d33") ?? .clear
}
