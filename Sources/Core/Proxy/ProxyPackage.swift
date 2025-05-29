import Basics
import Foundation
import os
@preconcurrency import PackageGraph
import PackageLoading
import PackageModel
@preconcurrency import Workspace

struct ProxyPackage: ProxyPackageProtocol {
  let bare: ResolvedPackage
  let pkgDir: AbsolutePath
  let proxiesDir: AbsolutePath
  let cache: BinariesCache
  let graph: ModulesGraph

  init(bare: ResolvedPackage, pkgDir: AbsolutePath, cache: BinariesCache, graph: ModulesGraph) {
    self.bare = bare
    self.pkgDir = pkgDir
    self.proxiesDir = pkgDir.parentDirectory
    self.cache = cache
    self.graph = graph
  }

  func generate() throws {
    log.debug("📦 Generate proxy for: \(bare.id.description.green)")

    try pkgDir.recreate()
    let proxy = try manifest.withChanges(
      pkgDir: pkgDir,
      dependencies: recursiveDependencies(),
      products: reachableProducts().map(convert(_:)),
      targets: reachableTargets().map(convert(_:)),
    )
    try proxy.write(
      to: pkgDir.appending("Package.swift"),
      additionalImportModuleNames: manifest.hasMacro() ? ["CompilerPluginSupport"] : [],
    )
    try pkgDir.appending("xccache.src").symlink(to: bare.path)

    // NOTE: This is a workaround to make dirs in a bare package show up in Xcode.
    // It's very strange that sometimes Xcode only displays the manifest for this case.
    // Here, we're creating symlinks to files/folders under the bare package.
    // Note that for manifests (Package.swift) under the bare package, we're using `bare.swift`
    // so that Xcode doesn't recognize them as manifests and display files/folders accordingly.
    try bare.path.subPaths().forEach { p in
      let basename = if p.basename.starts(with: "Package"), p.extension == "swift" {
        "\(p.basenameWithoutExt).bare.swift"
      } else { p.basename }
      try pkgDir.appending(basename).symlink(to: p)
    }
  }

  private func convert(_ this: ProductDescription) throws -> ProductDescription {
    // Only applicable to library (among library, executable, plugin)
    guard case .library = this.type else { return this }

    // Since `binaryTarget` cannot contain any `dependencies`, if target X depends on X1 and X2,
    // we need to add X1 and X2 to product of X so that when binaries of X, X1 and X2 are shipped together.
    //
    // NOTE: Here we can only gather targets within this package. How about cross-package dependencies?
    // -> They are taken care by RootProxyPackage so that, at the end, all is included
    let modules = try recursiveSiblingModules(for: this, excludeBinaryMacros: true).unique(\.name)
    return try .init(name: this.name, type: .library(.automatic), targets: modules)
  }

  private func convert(_ this: TargetDescription) throws -> TargetDescription {
    if let xcframeworkPath = cache.binaryPath(for: this.name) {
      let relativePath = xcframeworkPath.relative(to: proxiesDir.appending(bare.slug))
      return try .init(name: this.name, path: relativePath.pathString, type: .binary)
    }
    return try this.withChanges(
      path: "xccache.src/\(this.srcPath)",
      dependencies: recursiveTargetDependencies(for: this),
      settings: buildSettings(for: this),
    )
  }
}
