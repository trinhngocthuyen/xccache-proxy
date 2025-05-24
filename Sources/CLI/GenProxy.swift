import ArgumentParser
import XCCacheProxy

extension CLI {
  enum InputError: Error {
    case missing(String)
  }

  struct GenProxy: AsyncParsableCommand, CommandRunning {
    @OptionGroup var parent: CLI

    @Option(name: [.customLong("umbrella")], help: "Path to the umbrella package", transform: toAbsolutePath)
    var umbrellaDir: AbsolutePath?

    @Option(name: [.customLong("out")], help: "Path to the proxy packge", transform: toAbsolutePath)
    var outDir: AbsolutePath?

    @Option(name: [.customLong("bin")], help: "Path to the binaries dir", transform: toAbsolutePath)
    var binariesDir: AbsolutePath?

    var rootDir: AbsolutePath? { parent.rootDir }

    func run() async throws {
      try await withLoggingError {
        parent.handleUniversalArgs()

        try await ProxyGenerator(
          umbrellaDir: umbrellaDir ?? defaultSandboxDir(name: "umbrella"),
          outDir: outDir ?? defaultSandboxDir(name: "proxy"),
          binariesDir: binariesDir ?? defaultSandboxDir(name: "binaries"),
        ).generate()
      }
    }
  }
}
