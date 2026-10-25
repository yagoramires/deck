import AppKit
import SwiftUI

let app = NSApplication.shared
let arguments = CommandLine.arguments

/// Argumento depois de uma opção, ex.: `--snapshots <pasta>`.
func option(_ name: String, _ offset: Int = 1) -> String? {
    guard let flag = arguments.firstIndex(of: name), arguments.indices.contains(flag + offset) else { return nil }
    return arguments[flag + offset]
}

/// Store temporário com a config importada do app da fifine, sem tocar na config de verdade.
func scratchStore() -> Store {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deck-\(UUID().uuidString)")
    let store = Store(dir: dir)
    store.persist = false
    store.importOfficial()
    return store
}

if arguments.contains("--selftest") {
    Log.enabled = false
    precondition(D6.imageSlot(0) == 11 && D6.imageSlot(4) == 15 && D6.imageSlot(10) == 1 && D6.imageSlot(14) == 5)
    precondition(Importer.index("4,1") == 9 && Importer.index("0,2") == 0 && Importer.index("0,0") == 10 && Importer.index("5,0") == nil)
    precondition(D6.command("LIG", [10: 80]) == Array("CRT".utf8) + [0, 0] + Array("LIG".utf8) + [0, 0, 80])
    let key = Key(action: .hotkey(keyCode: 0, modifiers: 1 << 20, label: "⌘A"), title: "x")
    precondition(try! JSONDecoder().decode(Key.self, from: JSONEncoder().encode(key)) == key)
    if Importer.profile() != nil {
        let store = scratchStore()
        for (number, page) in store.config.pages.enumerated() {
            print("página \(number + 1):", page.enumerated().compactMap { i, k in k.map { "\(i + 1)=\($0.action)" } })
        }
    }
    print("selftest ok")
    exit(0)
}

if let input = option("--icon"), let output = option("--icon", 2) {
    guard let image = NSImage(contentsOfFile: input) else { fatalError("não abriu \(input)") }
    let styled = IconStyle.make(image)
    let png = NSBitmapImageRep(cgImage: styled.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        .representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: output))
    exit(0)
}

/// Desenha a janelinha em PNG (dados importados do app da fifine) pra conferir a interface sem abrir nada na tela.
if let dir = option("--snapshots") {
    app.setActivationPolicy(.prohibited)
    Log.enabled = false
    let store = scratchStore()
    let deck = DeckState()
    deck.connected = true
    let folder = URL(fileURLWithPath: dir)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for (name, selected) in [("inicio", nil), ("tecla-app", 5), ("tecla-site", 1), ("tecla-audio", 0)] as [(String, Int?)] {
        let root = RootView(selected: selected).environmentObject(store).environmentObject(deck)
        let host = NSHostingView(rootView: root.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.contentView = host
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        // Os controles do AppKit só desenham depois de uma volta no runloop.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("\(name).png"))
    }
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
