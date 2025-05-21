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
  let cache: BinariesCache
  let graph: ModulesGraph

  init(bare: ResolvedPackage, pkgDir: AbsolutePath, cache: BinariesCache, graph: ModulesGraph) {
    self.bare = bare
    self.pkgDir = pkgDir
    self.cache = cache
    self.graph = graph
  }

  func generate() throws {
    log.debug("Generate root proxy for: \(bare.id)")
    let proxy = try manifest.withChanges(
      pkgDir: pkgDir,
      dependencies: recursiveDependencies(),
      products: manifest.products,
      targets: manifest.targets.map(convert(_:)),
    )
    try pkgDir.appending(".Sources").symlink(to: bare.path.appending(".Sources"))
    try proxy.write(to: pkgDir.appending("Package.swift"))

    // Create symlink to binaries dir so that this dir is showing up on Xcode
    try pkgDir.appending("binaries").symlink(to: cache.dir)
  }

  private func recursiveDependencies() throws -> [PackageDependency] {
    graph
      .reachableProducts
      .filter { $0.packageIdentity != bare.identity }
      .compactMap { graph.package(for: $0.packageIdentity) }
      .unique()
      .map { pkg in
        .fileSystem(
          identity: pkg.identity,
          nameForTargetDependencyResolutionOnly: nil,
          path: pkgDir.appending(components: [".proxies", pkg.slug]),
          productFilter: .everything, // FIXME: Hmm. What should be here???
        )
      }
  }

  private func convert(_ this: TargetDescription) throws -> TargetDescription {
    let modules = try this.dependencies.flatMap { d in
      try graph.modules(for: d).flatMap { try $0.recursiveModules(excludeMacros: true) }
    }.unique()
    let products = modules.flatMap { m in m.dependencies.compactMap(\.product) }.unique()
    let extraDependencies = products.compactMap { p -> TargetDescription.Dependency? in
      guard let pkg = graph.package(for: p.packageIdentity) else { return nil }
      return .product(name: p.name, package: pkg.slug)
    }
    let dependencies = (this.dependencies + extraDependencies)
      .unique()
      .sorted { $0.desc.lowercased() < $1.desc.lowercased() } // Make it more readable
    let dependenciesDesc = dependencies.map { "  - \($0.desc)" }.joined(separator: "\n")
    log.debug("🔨 Dependencies for \(this.name):\n\(dependenciesDesc)")
    return try this.withChanges(dependencies: dependencies)
  }
}
