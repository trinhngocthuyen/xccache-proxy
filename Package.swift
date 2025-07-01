// swift-tools-version: 6.0

import PackageDescription

let SPM_BRANCH = "release/6.2"

let package = Package(
  name: "xccache-proxy",
  platforms: [.iOS(.v16), .macOS(.v14)],
  products: [
    .library(name: "XCCacheProxy", targets: ["XCCacheProxy"]),
    .executable(name: "xccache-proxy", targets: ["XCCacheProxyCLI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-package-manager.git", branch: SPM_BRANCH),
    .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "1.5.0")),
    .package(url: "https://github.com/onevcat/Rainbow", .upToNextMajor(from: "4.1.0")),
  ],
  targets: [
    .target(
      name: "XCCacheProxy",
      dependencies: [
        // Use SwiftPM-auto (static) instead of SwiftPM (dynamic) to create a standalone binary
        .product(name: "SwiftPM-auto", package: "swift-package-manager"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Rainbow", package: "Rainbow"),
      ],
      path: "Sources/Core",
    ),
    .executableTarget(
      name: "XCCacheProxyCLI",
      dependencies: [
        "XCCacheProxy",
      ],
      path: "Sources/CLI",
    ),
  ],
)
