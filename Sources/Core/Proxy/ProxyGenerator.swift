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
    rootDir: AbsolutePath,
    outDir: AbsolutePath,
    binariesDir: AbsolutePath,
  ) throws {
    self.rootDir = rootDir
    self.outDir = outDir
    self.workspace = try Workspace(forRootPackage: self.rootDir)
    self.proxiesDir = self.outDir.appending(".proxies")
    self.cache = BinariesCache(dir: binariesDir)
  }

  package func generate() async throws {
    log.info("""
    🔍 Loading graph...
    ⏳ This might take a while for the first time. Subsequent runs should be faster\n
    """.blue + """
       Umbrella: \(rootDir)
       Proxy: \(outDir)
       Binaries: \(cache.dir)
    """.dim)

    graph = try await workspace.loadPackageGraph(rootPath: rootDir, observabilityScope: .logging)

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
    log.info("-> Proxy manifest: \(outDir)/Package.swift".bold.green)
  }
}
