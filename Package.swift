// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Observation",
    platforms: [.macOS(.v26)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Support",
            targets: ["Support"]
        ),
        .library(
            name: "Observation",
            targets: ["Observation"]
        ),
        .executable(
            name: "ObservationClient",
            targets: ["ObservationClient"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0-latest"),
    ],
    targets: [
        .target(
            name: "Support",
            publicHeadersPath: ""
        ),
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        // Macro implementation that performs the source transformation of a macro.
        .macro(
            name: "ObservationMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),

        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(name: "Observation", dependencies: ["ObservationMacros", "Support"]),

        // A client of the library, which is able to use the macro in its own code.
        .executableTarget(name: "ObservationClient", dependencies: ["Observation"]),

        .executableTarget(name: "ObservationBenchmark", dependencies: ["Observation"]),

        .testTarget(name: "ObservationTests", dependencies: ["Observation"]),

        .testTarget(
            name: "ObservationMacrosTests",
            dependencies: [
                "ObservationMacros",
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax")
            ]
        ),
    ]
)
