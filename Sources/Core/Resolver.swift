import Basics
import Foundation
import os
@preconcurrency import PackageGraph
import PackageLoading
import PackageModel
import struct TSCUtility.Version
@preconcurrency import Workspace

@MainActor
package class Resolver {
  let workspace: Workspace
  let pkgDir: AbsolutePath
  let metadataDir: AbsolutePath?

  package init(
    workspace: Workspace? = nil,
    pkgDir: AbsolutePath,
    metadataDir: AbsolutePath?,
  ) throws {
    self.workspace = try workspace ?? .init(forRootPackage: pkgDir)
    self.pkgDir = pkgDir
    self.metadataDir = metadataDir
  }

  package func run() async throws {
    log.info("🧩 Resolving package dependencies of \(pkgDir)...".blue)
    let graph = try await workspace.loadPackageGraph(rootPath: pkgDir, observabilityScope: .logging)

    if let metadataDir {
      try await MetadataGenerator(
        graph: graph,
        pkgDir: pkgDir,
        outDir: metadataDir,
      ).run()
    }
  }
}
