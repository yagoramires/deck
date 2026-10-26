// swift-tools-version:6.0
import Foundation
import PackageDescription

// NeyKit vem do neyhub publicado no GitHub. Para desenvolver junto com um checkout local: NEYHUB_PATH=../neyhub
// (a identidade de `.package(path:)` é o nome da pasta em minúsculas, então derivamos dela: funciona com worktrees).
let localNeyhub = ProcessInfo.processInfo.environment["NEYHUB_PATH"]
let hub = localNeyhub.map { URL(fileURLWithPath: $0).lastPathComponent.lowercased() } ?? "neyhub"
let neyhubPackage: Package.Dependency = localNeyhub.map { .package(path: $0) }
    ?? .package(url: "https://github.com/yagoramires/neyhub.git", from: "0.1.0")
let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

// A pasta re/ (engenharia reversa do D6) fica fora de todos os alvos.
let package = Package(
    name: "Deck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Deck", targets: ["Deck"]),
        .library(name: "DeckPlugin", type: .dynamic, targets: ["DeckPlugin"]),
    ],
    dependencies: [neyhubPackage],
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
