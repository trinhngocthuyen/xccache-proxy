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
    log.info("Resolving package dependencies of \(pkgDir.basename)...".blue)

    let pollingLogTask = Task.detached {
      for i in 3 ..< 20 {
        try await Task.sleep(for: .seconds(i))
        log.info(
          "⏳ Still resolving... This might take a while for the first time. Subsequent runs should be faster...".yellow,
        )
      }
    }

    let graph = try await workspace.loadPackageGraph(rootPath: pkgDir, observabilityScope: .logging)
    pollingLogTask.cancel()

    if let metadataDir {
      try await MetadataGenerator(
        graph: graph,
        pkgDir: pkgDir,
        outDir: metadataDir,
      ).run()
    }
  }
}
