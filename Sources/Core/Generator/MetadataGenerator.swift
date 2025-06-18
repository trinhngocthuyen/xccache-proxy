import Basics
import Foundation
import os
@preconcurrency import PackageGraph
import PackageLoading
import PackageModel
import struct TSCUtility.Version
@preconcurrency import Workspace

@MainActor
package class MetadataGenerator {
  let graph: ModulesGraph?
  let pkgDir: AbsolutePath
  let outDir: AbsolutePath

  package init(
    graph: ModulesGraph? = nil,
    pkgDir: AbsolutePath,
    outDir: AbsolutePath,
  ) throws {
    self.pkgDir = pkgDir
    self.outDir = outDir
    self.graph = graph
  }

  package func run() async throws {
    try await _run()
  }

  private func _run() async throws {
    let graph = try await loadGraph()

    try outDir.mkdir()
    await withThrowingTaskGroup(of: Void.self) { group in
      for pkg in graph.packages {
        group.addTask {
          try pkg.manifest.saveAsJSON(to: self.outDir.appending("\(pkg.slug).json").asURL)
          if pkg.slug != pkg.manifest.displayName {
            try pkg.manifest.saveAsJSON(to: self.outDir.appending("\(pkg.manifest.displayName).json").asURL)
          }
        }
      }
    }
    log.live?.msgOnDone("-> Metadata of packages: \(outDir)".green)
  }

  private func loadGraph() async throws -> ModulesGraph {
    if let graph { return graph }
    return try await Workspace(forRootPackage: pkgDir).loadPackageGraph(rootPath: pkgDir, observabilityScope: .liveLog)
  }
}
