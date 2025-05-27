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
struct CLI: AsyncParsableCommand, CommandRunning {
  nonisolated(unsafe) static var configuration = CommandConfiguration(
    subcommands: [
      GenUmbrella.self,
      GenProxy.self,
      Resolve.self,
    ],
  )

  @Option(name: [.customLong("root")], help: "Project root dir (default: current)", transform: toAbsolutePath)
  var rootDir: AbsolutePath?

  @Flag(name: .long, help: "Show more debugging information")
  var verbose: Bool = false

  func handleUniversalArgs() {
    if verbose {
      log.setLevel(.debug)
    }
  }
}
