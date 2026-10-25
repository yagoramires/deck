import NeyKit
import SwiftUI

/// Tela de app: por enquanto o popover no meio da janela (a tela do Deck vem em seguida).
struct ScreenView: View {
    var body: some View {
        ScrollView { RootView().padding(20) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 460, minHeight: 360)
            .background(Grafite.bg)
            .environment(\.colorScheme, .dark)
    }
}
