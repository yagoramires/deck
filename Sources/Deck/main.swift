import AppKit
import DeckCore
import NeyKit

let arguments = CommandLine.arguments
if arguments.contains("--selftest") {
    NeyKitSelfTest.run()
    DeckApp.selfTest()
    print("selftest ok")
    exit(0)
}

if let flag = arguments.firstIndex(of: "--icon"), arguments.indices.contains(flag + 2) {
    DeckApp.styleIcon(arguments[flag + 1], to: arguments[flag + 2])
    exit(0)
}

let app = NSApplication.shared
/// Desenha a janelinha e a tela em PNG (teclas de exemplo) pra conferir a interface sem abrir nada na tela.
if let flag = arguments.firstIndex(of: "--snapshots"), arguments.indices.contains(flag + 1) {
    app.setActivationPolicy(.prohibited)
    DeckApp.runSnapshots(into: URL(fileURLWithPath: arguments[flag + 1]))
    exit(0)
}
let delegate = DeckAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
