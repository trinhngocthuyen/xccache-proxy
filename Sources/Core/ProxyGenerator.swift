import Basics
import Foundation
import os
@preconcurrency import PackageGraph
import PackageLoading
import PackageModel
@preconcurrency import Workspace

@MainActor
package class ProxyGenerator {
  let workspace: Workspace
  let rootDir: AbsolutePath
  let outDir: AbsolutePath
  let cache: BinariesCache

  let proxiesDir: AbsolutePath
  private var graph: ModulesGraph!

  package init(
    rootDir root: String,
    outDir out: String? = nil,
    binariesDir binaries: String? = nil
  ) throws {
    self.rootDir = try .init(validating: root)
    self.outDir = try out.map(AbsolutePath.init(validating:)) ?? rootDir.parentDirectory.appending("proxy")
    self.workspace = try Workspace(forRootPackage: self.rootDir)
    self.proxiesDir = self.outDir.appending(".proxies")
    self.cache = try BinariesCache(
      dir: binaries.map(AbsolutePath.init(validating:)) ?? rootDir.parentDirectory.appending("binaries"),
    )
  }

  package func generate() async throws {
    log.info("Umbrella dir: \(rootDir)")
    log.info("Proxy dir: \(outDir)")
    log.info("Loading graph...")

    graph = try await workspace.loadPackageGraph(rootPath: rootDir, observabilityScope: .logging)
    log.info("-> Loaded. \(graph.reachableModules.count) modules")

    try cache.update(
      modules: graph.reachableModules.map(\.name),
      artifacts: graph.binaryArtifacts.flatMap { $1.values.map(\.path) },
    )
    await withThrowingTaskGroup(of: Void.self) { group in
      let nonRootPkgs = graph.packages.filter { !graph.isRootPackage($0) }
      group.addTasks(values: nonRootPkgs) { pkg in
        try await ProxyPackage(
          bare: pkg,
          pkgDir: self.proxiesDir.appending(pkg.slug),
          cache: self.cache,
          graph: self.graph,
        ).generate()
      }
      group.addTasks(values: graph.rootPackages) { pkg in
        try await RootProxyPackage(
          bare: pkg,
          pkgDir: self.outDir,
          cache: self.cache,
          graph: self.graph,
        ).generate()
      }
    }
    log.debug("✔ Done. Proxy manifest: \(outDir)/Package.swift")
  }
}
