// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ARISE",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(
            url: "https://github.com/groue/GRDB.swift",
            from: "6.29.3"
        )
    ],
    targets: [
        .executableTarget(
            name: "ARISE",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: ".",
            exclude: [
                "Package.swift"
            ],
            sources: [
                "App",
                "Core",
                "UI"
            ],
            resources: [
                .copy("Resources/arise_system_prompt.txt")
            ]
        )
    ]
)
