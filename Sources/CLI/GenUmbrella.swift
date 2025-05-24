import ArgumentParser
import Foundation
import XCCacheProxy

extension CLI {
  struct GenUmbrella: AsyncParsableCommand, CommandRunning {
    @OptionGroup var parent: CLI

    @Option(name: [.customLong("lockfile")], help: "Path to the lockfile", transform: toAbsolutePath)
    var lockfilePath: AbsolutePath?

    @Option(name: [.customLong("out")], help: "Path to the umbrella packge", transform: toAbsolutePath)
    var outDir: AbsolutePath?

    var rootDir: AbsolutePath? { parent.rootDir }

    func run() async throws {
      try await withLoggingError {
        parent.handleUniversalArgs()

        try await UmbrellaGenerator(
          lockfilePath: lockfilePath ?? projectRootDir().appending("xccache.lock"),
          umbrellaDir: outDir ?? defaultSandboxDir(name: "umbrella"),
        ).generate()
      }
    }
  }
}
