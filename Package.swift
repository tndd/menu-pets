// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuPup",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MenuPup", targets: ["MenuPup"])],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0")
    ],
    targets: [
        .target(name: "CMetrics"),
        .target(name: "MonitorCore", dependencies: ["CMetrics"],
                linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "MenuPup", dependencies: [
            "MonitorCore", "CMetrics", .product(name: "SwiftTerm", package: "SwiftTerm")
        ]),
        .executableTarget(name: "MonitorChecks", dependencies: ["MonitorCore"], path: "Tests/MonitorCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
