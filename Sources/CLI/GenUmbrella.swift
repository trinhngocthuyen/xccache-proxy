import ArgumentParser
import Foundation
import XCCacheProxy

extension CLI {
  struct GenUmbrella: AsyncParsableCommand, CommandRunning {
    @OptionGroup var parent: CLI
    var rootDir: AbsolutePath? { parent.rootDir }

    @Option(name: [.customLong("lockfile")], help: "Path to the lockfile", transform: toAbsolutePath)
    var lockfilePath: AbsolutePath?

    @Option(name: [.customLong("out")], help: "Path to the umbrella packge", transform: toAbsolutePath)
    var outDir: AbsolutePath?

    func run() async throws {
      try await log.liveSection("Generating umbrella package".blue) {
        parent.handleUniversalArgs()

        try await UmbrellaGenerator(
          lockfilePath: lockfilePath ?? projectRootDir().appending("xccache.lock"),
          umbrellaDir: outDir ?? defaultSandboxDir(name: "umbrella"),
        ).run()
      }
    }
  }
}
