import os
import Foundation
import Basics
import Workspace
import PackageModel
import PackageGraph
import PackageLoading
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
