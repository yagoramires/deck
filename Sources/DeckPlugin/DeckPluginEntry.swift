import AppKit
import DeckCore
import NeyKit

/// Deck dentro do NeyHub. Linka só DeckCore e NeyKit (nunca NeyKitApp).
final class DeckEntry: NSObject, NeyPlugin {
    private lazy var app = DeckApp(defaults: AppDefaults.forApp("local.deck"), hosted: true, version: PluginLocation.version(dso: #dsohandle))

    var contractVersion: Int { neyPluginContractVersion }

    func start(host: NeyHost) {
        app.onOpenPermissions = { host.openPermissions() }
        app.start()
    }

    func stop() { app.stop() }
    func setMenuBarVisible(_ visible: Bool) { app.setMenuBarVisible(visible) }
    func makeScreen() -> NSViewController? { app.makeScreen() }
    func makeSettings() -> NSViewController { app.makeSettings() }
}

@_cdecl("neyhub_plugin_v1") public func neyhubPluginV1() -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(DeckEntry()).toOpaque()
}
