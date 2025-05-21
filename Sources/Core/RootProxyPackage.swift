import os
import Foundation
import Basics
import PackageModel
import PackageLoading
@preconcurrency import PackageGraph
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
      targets: manifest.targets.map(convert(_:))
    )
    try pkgDir.appending(".Sources").symlink(to: bare.path.appending(".Sources"))
    try proxy.write(to: pkgDir.appending("Package.swift"))

    // Create symlink to binaries dir so that this dir is showing up on Xcode
    try pkgDir.appending("binaries").symlink(to: cache.dir)
  }

  private func recursiveDependencies() -> [PackageDependency] {
    manifest.dependencies.flatMap { dep in
      return graph.recursiveDependencies(for: dep.identity).map { pkg -> PackageDependency in
        .fileSystem(
          identity: pkg.identity,
          nameForTargetDependencyResolutionOnly: nil,
          path: pkgDir.appending(components: [".proxies", pkg.slug]),
          productFilter: dep.productFilter // FIXME: Hmm. What should be here???
        )
      }
    }.unique()
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
