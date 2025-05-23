import Basics
import Foundation
import os
@preconcurrency import PackageGraph
import PackageLoading
import PackageModel
@preconcurrency import Workspace

struct RootProxyPackage: ProxyPackageProtocol {
  let bare: ResolvedPackage
  let pkgDir: AbsolutePath
  let proxiesDir: AbsolutePath
  let cache: BinariesCache
  let graph: ModulesGraph

  init(bare: ResolvedPackage, pkgDir: AbsolutePath, cache: BinariesCache, graph: ModulesGraph) {
    self.bare = bare
    self.pkgDir = pkgDir
    self.proxiesDir = pkgDir.appending(".proxies")
    self.cache = cache
    self.graph = graph
  }

  func generate() throws {
    let proxy = try manifest.withChanges(
      pkgDir: pkgDir,
      dependencies: recursiveDependencies(),
      products: reachableProducts(),
      targets: reachableTargets().map(convert(_:)),
    )
    try pkgDir.appending(".Sources").symlink(to: bare.path.appending(".Sources"))
    try proxy.write(to: pkgDir.appending("Package.swift"))

    // Create symlink to binaries dir so that this dir is showing up on Xcode
    try pkgDir.appending("binaries").symlink(to: cache.dir)
  }

  private func convert(_ this: TargetDescription) throws -> TargetDescription {
    try this.withChanges(
      dependencies: recursiveTargetDependencies(for: this),
      settings: buildSettings(for: this),
    )
  }
}
