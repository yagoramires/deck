import NeyKit
import SwiftUI

/// Configurações (card no NeyHub, janela no avulso). As teclas e páginas ficam no popover e na tela.
struct SettingsView: View {
    let version: String
    let hosted: Bool
    /// nil hospedado: o modo é do NeyHub.
    let presence: Presence?
    let onPresence: (Presence) -> Void
    let grant: () -> Void
    /// O --snapshots fixa a permissão; senão vem do sistema (só leitura, nunca pede).
    let trusted: () -> Bool
    @ViewState private var shown: Presence
    @ViewState private var granted: Bool

    init(version: String, hosted: Bool, presence: Presence?, onPresence: @escaping (Presence) -> Void,
         grant: @escaping () -> Void, trusted: @escaping () -> Bool = { Perform.isTrusted() }) {
        self.version = version; self.hosted = hosted; self.presence = presence; self.onPresence = onPresence
        self.grant = grant; self.trusted = trusted
        _shown = ViewState(wrappedValue: presence ?? Presence(screen: false, menuBar: true))
        _granted = ViewState(wrappedValue: trusted())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deck").font(.system(size: 16, weight: .bold)).foregroundStyle(Grafite.strong)
            Text("Controle do fifine AmpliGame D6 · \(version)").font(.system(size: 12)).foregroundStyle(Grafite.muted)
                .padding(.bottom, 6)
            if presence != nil {
                GCard {
                    VStack(alignment: .leading, spacing: 6) {
                        title("Onde aparece")
                        mode("Janela", note: "Ícone no Dock e a tela do Deck.", \.screen)
                        mode("Barra de menus", note: "O ícone do Deck com o popover.", \.menuBar)
                        Text("O D6 funciona em qualquer modo, enquanto o Deck estiver aberto.")
                            .font(.system(size: 11)).foregroundStyle(Grafite.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            GCard {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        title("Acessibilidade")
                        Spacer()
                        if granted {
                            Text("Concedida").font(.system(size: 11)).foregroundStyle(Grafite.accent)
                        } else {
                            Text("Não concedida").font(.system(size: 11)).foregroundStyle(Grafite.warn)
                            GPill(title: "Conceder", action: grant)
                        }
                    }
                    Text(hosted ? "Só pras teclas de atalho e de mídia. A permissão é do NeyHub."
                                : "Só pras teclas de atalho e de mídia. O macOS pede na primeira vez.")
                        .font(.system(size: 11)).foregroundStyle(Grafite.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .frame(minWidth: 420, maxWidth: 520, alignment: .leading)
        .grafiteWindow()
        // A permissão chega pelos Ajustes com a tela aberta.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in granted = trusted() }
    }

    /// Desligar os dois não vale: o outro volta a ligar (`normalized`).
    private func mode(_ label: String, note: String, _ key: WritableKeyPath<Presence, Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 12))
                Text(note).font(.system(size: 11)).foregroundStyle(Grafite.muted)
            }
            Spacer()
            GSwitch(isOn: Binding(get: { shown[keyPath: key] }, set: {
                var next = shown
                next[keyPath: key] = $0
                next = next.normalized(hasScreen: true)
                shown = next
                onPresence(next)
            }), label: label)
        }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Grafite.strong)
    }
}
