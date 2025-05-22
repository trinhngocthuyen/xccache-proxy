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
  @Option(name: [.customLong("in")], help: "Path to the umbrella package (default: current dir)")
  var rootDir: String?

  @Option(name: [.customLong("out")], help: "Path to the proxy packge")
  var outDir: String?

  @Option(name: [.customLong("bin")], help: "Path to the binaries dir")
  var binariesDir: String?

  func run() async throws {
    do {
      try await ProxyGenerator(
        rootDir: getRootDir(),
        outDir: outDir,
        binariesDir: binariesDir,
      ).generate()
    } catch {
      log.error("Error: \(error)")
    }
  }

  private func getRootDir() throws -> String {
    if let rootDir { return rootDir }
    if let rootDir = ProcessInfo.processInfo.environment["XCCACHE_PROXY_ROOT_DIR"] { return rootDir }
    throw NSError(domain: "Missing rootDir", code: 1, userInfo: nil)
  }
}
