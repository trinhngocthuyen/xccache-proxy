import ArgumentParser
import Foundation
import XCCacheProxy

extension CLI {
  struct Resolve: AsyncParsableCommand, CommandRunning {
    @OptionGroup var parent: CLI
    var rootDir: AbsolutePath? { parent.rootDir }

    @Option(name: [.customLong("pkg")], help: "Path to the package", transform: toAbsolutePath)
    var pkgDir: AbsolutePath?

    @Option(name: [.customLong("metadata")], help: "Path to the metadata dir", transform: toAbsolutePath)
    var metadataDir: AbsolutePath?

    func run() async throws {
      try await log.liveSection("Resolving umbrella package dependencies".blue) {
        parent.handleUniversalArgs()

        try await Resolver(
          pkgDir: pkgDir ?? defaultSandboxDir(name: "umbrella"),
          metadataDir: metadataDir,
        ).run()
      }
    }
  }
}
