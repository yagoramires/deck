import NeyKit
import SwiftUI

/// Tela de app (janela do NeyHub, ou do avulso no modo Janela): o popover em tamanho grande. O D6 desenhado com as
/// 15 teclas na posição real, páginas em abas e o editor da tecla escolhida sempre aberto ao lado.
struct ScreenView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var deck: DeckState
    @ViewState private var selected: Int? = 0
    @ViewState private var confirmDeletePage = false
    @ViewState private var confirmImport = false

    init(selected: Int = 0) { _selected = ViewState(wrappedValue: selected) }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 700
            let inner = geometry.size.width - 44
            let banners = CGFloat((deck.officialRunning ? 1 : 0) + (deck.needsAccessibility ? 1 : 0)) * 48
            VStack(alignment: .leading, spacing: 14) {
                header(wide: wide)
                if deck.officialRunning { OfficialBanner() }
                if deck.needsAccessibility { AccessibilityBanner() }
                if wide {
                    HStack(alignment: .top, spacing: 14) {
                        deckColumn(width: inner - 314, height: geometry.size.height - 130 - banners)
                        ScrollView(showsIndicators: false) { editor.padding(.bottom, 20) }.frame(width: 300)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            deckColumn(width: inner, height: .infinity)
                            editor
                        }
                        .frame(width: inner)
                        .padding(.bottom, 20)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
        }
        .frame(minWidth: 460, minHeight: 360)
        .foregroundStyle(Grafite.text)
        .background(Grafite.bg)
        .tint(Grafite.accent)
        .environment(\.colorScheme, .dark)
        .deletePageAlert($confirmDeletePage)
        .importAlert($confirmImport)
    }

    // MARK: Cabeçalho

    @ViewBuilder private func header(wide: Bool) -> some View {
        let title = HStack(spacing: 12) {
            Text("Deck").font(.system(size: 18, weight: .bold)).foregroundStyle(Grafite.strong)
            Status(font: .system(size: 12), color: Grafite.muted)
        }
        let controls = HStack(spacing: 12) {
            Brightness(width: 90)
            pager
        }
        if wide {
            HStack(spacing: 12) { title; Spacer(minLength: 8); controls }
        } else {
            VStack(alignment: .leading, spacing: 10) { title; controls }
        }
    }

    /// ‹ Página 1 2 3 › +
    private var pager: some View {
        HStack(spacing: 6) {
            tab("‹", on: false, help: "Página anterior") { store.turnPage(by: -1) }
                .disabled(store.page == 0)
            ForEach(store.config.pages.indices, id: \.self) { page in
                tab(page == store.page ? "Página \(page + 1)" : "\(page + 1)", on: page == store.page, help: "Página \(page + 1)") {
                    store.page = page
                }
            }
            tab("›", on: false, help: "Próxima página") { store.turnPage(by: 1) }
                .disabled(store.page == store.config.pages.count - 1)
            tab("+", on: false, help: "Nova página") { store.addPage() }
        }
        .padding(3)
        .background(Grafite.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Grafite.border, lineWidth: 1))
    }

    private func tab(_ title: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12)).monospacedDigit().fixedSize()
                .foregroundStyle(on ? Grafite.strong : Grafite.muted)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(on ? Grafite.tabOn : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: O D6

    private func deckColumn(width: CGFloat, height: CGFloat) -> some View {
        // 18 de margem e 12 entre as teclas; o rodapé fica embaixo.
        let side = max(44, min((width - 36 - 48) / 5, (height - 36 - 24 - 44) / 3))
        return VStack(alignment: .leading, spacing: 12) {
            KeyGrid(spacing: 12) { KeyTile(index: $0, selected: $selected, side: side, numbered: true) }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(Grafite.deck, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Grafite.border, lineWidth: 1))
            HStack(spacing: 8) {
                Chip(title: "Importar do app da fifine…") { confirmImport = true }
                    .disabled(Importer.profile() == nil)
                Chip(title: "Apagar página") { confirmDeletePage = true }
                    .disabled(store.config.pages.count == 1)
                Spacer(minLength: 8)
                Text("Arraste uma tecla pra trocar de lugar · solte uma imagem pra virar ícone")
                    .font(.system(size: 11)).foregroundStyle(Grafite.muted)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: width)
    }

    private var editor: some View {
        let index = selected ?? 0
        return KeyEditor(index: index, wide: true).id("\(store.page)-\(index)")
    }
}
