import ArgumentParser
import Foundation
import XCCacheProxy

extension CLI {
  struct GenMetadata: AsyncParsableCommand, CommandRunning {
    @OptionGroup var parent: CLI
    var rootDir: AbsolutePath? { parent.rootDir }

    @Option(name: [.customLong("umbrella")], help: "Path to the umbrella package", transform: toAbsolutePath)
    var umbrellaDir: AbsolutePath?

    @Option(name: [.customLong("out")], help: "Path to the metadata dir", transform: toAbsolutePath)
    var outDir: AbsolutePath?

    func run() async throws {
      try await withLoggingError {
        parent.handleUniversalArgs()

        try await MetadataGenerator(
          umbrellaDir: umbrellaDir ?? defaultSandboxDir(name: "umbrella"),
          outDir: outDir ?? defaultSandboxDir(name: "metadata"),
        ).generate()
      }
    }
  }
}
