// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Clara",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "Clara", targets: ["Clara"])],
    targets: [
        .target(name: "SwiftTerm", path: "Vendor/SwiftTerm/Sources/SwiftTerm", exclude: ["Mac/README.md"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Clara", dependencies: ["SwiftTerm"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ClaraTests", dependencies: ["Clara"], swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
