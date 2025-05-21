import Basics
import Foundation
import os
import PackageGraph
import PackageLoading
import PackageModel
import Workspace
import XCCacheProxy

@main
struct CLI {
  static func main() async throws {
    do {
      // FIXME: Hardcoded path for now
      try await ProxyGenerator(rootDir: "/Users/thuyen/projects/xccache/examples/xccache/packages/umbrella").generate()
    } catch {
      log.error("Error: \(error)")
    }
  }
}
