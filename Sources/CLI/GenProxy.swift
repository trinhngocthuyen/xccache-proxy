import ArgumentParser
import XCCacheProxy

extension CLI {
  enum InputError: Error {
    case missing(String)
  }

  struct GenProxy: AsyncParsableCommand, CommandRunning {
    @OptionGroup var parent: CLI
    var rootDir: AbsolutePath? { parent.rootDir }

    @Option(name: [.customLong("umbrella")], help: "Path to the umbrella package", transform: toAbsolutePath)
    var umbrellaDir: AbsolutePath?

    @Option(name: [.customLong("out")], help: "Path to the proxy packge", transform: toAbsolutePath)
    var outDir: AbsolutePath?

    @Option(name: [.customLong("bin")], help: "Path to the binaries dir", transform: toAbsolutePath)
    var binariesDir: AbsolutePath?

    func run() async throws {
      try await log.liveSection("Generating proxy packages".blue) {
        parent.handleUniversalArgs()

        try await ProxyGenerator(
          umbrellaDir: umbrellaDir ?? defaultSandboxDir(name: "umbrella"),
          outDir: outDir ?? defaultSandboxDir(name: "proxy"),
          binariesDir: binariesDir ?? defaultSandboxDir(name: "binaries"),
        ).run()
      }
    }
  }
}
