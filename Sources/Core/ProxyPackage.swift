import Basics
import Foundation
import os
@preconcurrency import PackageGraph
import PackageLoading
import PackageModel
@preconcurrency import Workspace

protocol ProxyPackageProtocol {
  var bare: ResolvedPackage { get }
  func generate() throws
}

extension ProxyPackageProtocol {
  var manifest: Manifest { bare.manifest }
}

struct ProxyPackage: ProxyPackageProtocol {
  let bare: ResolvedPackage
  let pkgDir: AbsolutePath
  let proxiesDir: AbsolutePath
  let cache: BinariesCache
  private let graph: ModulesGraph

  init(bare: ResolvedPackage, pkgDir: AbsolutePath, cache: BinariesCache, graph: ModulesGraph) {
    self.bare = bare
    self.pkgDir = pkgDir
    self.proxiesDir = pkgDir.parentDirectory
    self.cache = cache
    self.graph = graph
  }

  func generate() throws {
    log.debug("Generate proxy for: \(bare.id)")

    let targets = try manifest.targets.map(convert(_:))
    let products = try manifest.products.map(convert(_:))
    let proxy = try manifest.withChanges(
      pkgDir: pkgDir,
      dependencies: manifest.dependencies.map(convert(_:)),
      products: products,
      targets: targets,
    )
    try proxy.write(
      to: pkgDir.appending("Package.swift"),
      additionalImportModuleNames: manifest.hasMacro() ? ["CompilerPluginSupport"] : [],
    )
    try pkgDir.appending("src").symlink(to: bare.path)
    try pkgDir.appending("src.\(bare.slug)").symlink(to: bare.path)
  }

  private func convert(_ this: PackageDependency) throws -> PackageDependency {
    // If this dependency is not reachable -> don't transform it
    guard graph.package(for: this.identity) != nil else { return this }
    return .fileSystem(
      identity: this.identity,
      nameForTargetDependencyResolutionOnly: nil,
      path: pkgDir.parentDirectory.appending(this.nameForModuleDependencyResolutionOnly),
      productFilter: this.productFilter,
    )
  }

  private func convert(_ this: ProductDescription) throws -> ProductDescription {
    // Only applicable to library (among library, executable, plugin)
    guard case .library = this.type else { return this }

    // NOTE: Include all binary-cache dependencies into associated targets of this product
    // Here, we can only include sibling targets (ie. within this package)
    // FIXME: Hmmm. How about binary-cache across packages??? -> Taken care by RootProxyPackage
    let modules = try this.targets
      .compactMap { graph.module(for: $0) }
      .flatMap { try $0.recursiveSiblingModules() }
      .unique(\.name)
    return try .init(name: this.name, type: .library(.automatic), targets: modules)
  }

  private func convert(_ this: TargetDescription) throws -> TargetDescription {
    if let xcframeworkPath = cache.binaryPath(for: this.name) {
      let relativePath = xcframeworkPath.relative(to: proxiesDir.appending(bare.slug))
      return try .init(name: this.name, path: relativePath.pathString, type: .binary)
    }

    let dependencies = this.dependencies.map { dep in
      guard case let .byName(name: name, condition: condition) = dep else { return dep }
      // Referencing by name within package is ok
      if bare.manifest.targets.contains(where: { $0.name == name }) { return dep }

      if let module = graph.module(for: name), let depPkg = graph.package(for: module) {
        log.debug("[\(this.name)] Implicit dependency by name: \(name) -> product of \(depPkg.slug)")
        return .product(name: name, package: depPkg.slug, condition: condition)
      }
      log.warning("[\(this.name)] Cannot resolve implicit dependency: \(name)")
      return dep
    }

    // FIXME: Include binaries of cross-package targets (for compilation) in case this target is not cache-hit

    return try this.withChanges(path: "src/\(this.srcPath)", dependencies: dependencies)
  }
}
