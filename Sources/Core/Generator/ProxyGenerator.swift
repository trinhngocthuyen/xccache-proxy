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
  let umbrellaDir: AbsolutePath
  let outDir: AbsolutePath
  let cache: BinariesCache

  let proxiesDir: AbsolutePath
  private var graph: ModulesGraph!

  package init(
    umbrellaDir: AbsolutePath,
    outDir: AbsolutePath,
    binariesDir: AbsolutePath,
  ) throws {
    self.umbrellaDir = umbrellaDir
    self.outDir = outDir
    self.workspace = try Workspace(forRootPackage: umbrellaDir)
    self.proxiesDir = self.outDir.appending(".proxies")
    self.cache = BinariesCache(dir: binariesDir)
  }

  package func run() async throws {
    log.info("Generating proxy packages...".blue)

    graph = try await workspace.loadPackageGraph(rootPath: umbrellaDir, observabilityScope: .logging)

    log.log(
      format: "-> Loaded graph with %@, %@",
      "\(graph.packages.count) packages".green,
      "\(graph.reachableModules.count) modules".cyan,
    )

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
    try GraphGenerator(graph: graph, cache: cache, outPath: outDir.appending("graph.json")).generate()
    log.info("-> Proxy manifest: \(outDir)/Package.swift".green)
  }
}
