import ArgumentParser
import Basics
import Foundation
import os
import PackageGraph
import PackageLoading
import PackageModel
import Workspace
import XCCacheProxy

@main
struct CLI: AsyncParsableCommand {
  @Option(name: [.customLong("lockfile")], help: "Path to the lockfile", transform: toAbsolutePath)
  var lockfilePath: AbsolutePath?

  @Option(name: [.customLong("umbrella")], help: "Path to the umbrella package", transform: toAbsolutePath)
  var umbrellaDir: AbsolutePath

  @Option(name: [.customLong("out")], help: "Path to the proxy packge", transform: toAbsolutePath)
  var outDir: AbsolutePath

  @Option(name: [.customLong("bin")], help: "Path to the binaries dir", transform: toAbsolutePath)
  var binariesDir: AbsolutePath?

  @Flag(name: .long, help: "Show more debugging information")
  var verbose: Bool = false

  func run() async throws {
    do {
      if verbose { log.setLevel(.debug) }

      if let lockfilePath {
        try await UmbrellaGenerator(
          lockfilePath: lockfilePath,
          umbrellaDir: umbrellaDir,
        ).generate()
      }

      try await ProxyGenerator(
        rootDir: umbrellaDir,
        outDir: outDir,
        binariesDir: binariesDir ?? umbrellaDir.parentDirectory.appending("binaries"),
      ).generate()
    } catch {
      log.error("Fail to generate proxy. Error: \(error)".bold)
      throw error
    }
  }

  private static func toAbsolutePath(_ string: String) throws -> AbsolutePath {
    try .init(validating: string, relativeTo: .pwd())
  }
}
