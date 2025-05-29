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
    try exposeHeaders()
    try pkgDir.appending(".Sources").symlink(to: bare.path.appending(".Sources"))
    try proxy.write(to: pkgDir.appending("Package.swift"))

    // Create symlink to binaries dir so that this dir is showing up on Xcode
    try pkgDir.appending("binaries").symlink(to: cache.dir)
  }

  private func exposeHeaders() throws {
    // Here, we expose all headers so that if building from sources, it's very less likly to fail.
    // Header resolution in xcframeworks and in swift packages' bare/source forms behaves differently.
    //
    // While `#import <GoogleUtilities/GULAppEnvironmentUtil.h>` works in the bare form, `GoogleUtilities` is not a module.
    // The actual module it belongs to is `GoogleUtilities_Environment`.
    // This kind of import is valid in the bare form as long as it's visible to SPM search paths.
    // Yet, it's broken if `GoogleUtilities_Environment` is in binary.
    // To tackle this issue, we expose all headers, just like how they are visible to the SPM header resolution system.
    // --------------------------------------------------------------------------------------------------------
    // For every public header, we create a symlink that preserves the relative structure (from the include dir)
    //
    //   include / -- Foo / -- foo1.h     |     .headers / -- Foo / -- foo1.h
    //            |         -- foo2.h     |               |         -- foo2.h
    //            |-- Bar / -- bar1.h     |               |-- Bar / -- bar1.h
    //
    // This enables `#import <Foo/foo1.h>`, `#import <Bar/bar1.h>`
    // --------------------------------------------------------------------------------------------------------
    let headersDir = try pkgDir.appending(".headers").recreate()
    let clangModules = try graph.recursiveModulesFromRoot(excludeMacroDeps: true).compactMap { $0.underlying as? ClangModule }
    try clangModules.forEach { m in
      try m.headersUnderIncludeDir().forEach { p in
        try headersDir.appending(p.relative(to: m.includeDir)).symlink(to: p)
      }
    }
  }

  private func convert(_ this: TargetDescription) throws -> TargetDescription {
    try this.withChanges(
      dependencies: recursiveTargetDependencies(for: this),
      settings: buildSettings(for: this),
    )
  }
}

private extension ClangModule {
  func headersUnderIncludeDir() -> [AbsolutePath] {
    headers.filter { $0.isDescendantOfOrEqual(to: includeDir) }
  }
}
