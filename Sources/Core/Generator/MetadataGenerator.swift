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
  let workspace: Workspace
  let umbrellaDir: AbsolutePath
  let outDir: AbsolutePath

  package init(umbrellaDir: AbsolutePath, outDir: AbsolutePath) throws {
    self.umbrellaDir = umbrellaDir
    self.workspace = try Workspace(forRootPackage: umbrellaDir)
    self.outDir = outDir
  }

  package func generate() async throws {
    log.info("🪄 Generating metadata...".blue)
    let graph = try await workspace.loadPackageGraph(rootPath: umbrellaDir, observabilityScope: .logging)

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
    log.info("-> Metadata of packages: \(outDir)".bold.green)
  }
}
