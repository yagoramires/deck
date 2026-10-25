// swift-tools-version:6.0
import Foundation
import PackageDescription

// NeyKit vem do checkout do neyhub ao lado (ou NEYHUB_PATH). A identidade de `.package(path:)` é o nome
// da pasta em minúsculas, então derivamos dela: funciona com worktrees.
let neyhub = ProcessInfo.processInfo.environment["NEYHUB_PATH"] ?? "../neyhub"
let hub = URL(fileURLWithPath: neyhub).lastPathComponent.lowercased()
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

// A pasta re/ (engenharia reversa do D6) fica fora de todos os alvos.
let package = Package(
    name: "Deck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Deck", targets: ["Deck"]),
        .library(name: "DeckPlugin", type: .dynamic, targets: ["DeckPlugin"]),
    ],
    dependencies: [.package(path: neyhub)],
    targets: [
        .target(name: "DeckCore", dependencies: [.product(name: "NeyKit", package: hub)], path: "Sources/DeckCore", swiftSettings: swift5),
        .executableTarget(
            name: "Deck",
            dependencies: ["DeckCore", .product(name: "NeyKitApp", package: hub)],
            path: "Sources/Deck",
            swiftSettings: swift5
        ),
        // Plugin do NeyHub: nunca linka NeyKitApp (classes duplicadas no processo do NeyHub).
        .target(name: "DeckPlugin", dependencies: ["DeckCore", .product(name: "NeyKit", package: hub)], path: "Sources/DeckPlugin", swiftSettings: swift5),
    ]
)
