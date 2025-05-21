// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "xccache-proxy",
  platforms: [.iOS(.v16), .macOS(.v14)],
  products: [
    .library(name: "XCCacheProxy", targets: ["XCCacheProxy"]),
    .executable(name: "xccache-proxy-cli", targets: ["XCCacheProxyCLI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.6.3")),
    .package(url: "https://github.com/swiftlang/swift-package-manager.git", branch: "swift-6.1-RELEASE"),
  ],
  targets: [
    .target(
      name: "XCCacheProxy",
      dependencies: [
        .product(name: "Logging", package: "swift-log"),
        .product(name: "SwiftPM", package: "swift-package-manager"),
      ],
      path: "Sources/Core"
    ),
    .executableTarget(
      name: "XCCacheProxyCLI",
      dependencies: [
        "XCCacheProxy",
      ],
      path: "Sources/CLI"
    ),
  ]
)
