import Basics
import Foundation
import PackageGraph
import PackageModel
import TSCBasic
import struct TSCUtility.Version

package typealias AbsolutePath = Basics.AbsolutePath
package typealias RelativePath = Basics.RelativePath

extension URL {
  func subPaths() throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
      at: self,
      includingPropertiesForKeys: [],
      options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
    )
  }
}

extension AbsolutePath {
  package static func pwd() throws -> Self {
    try .init(validating: URL.currentDirectory().path())
  }

  func appending(relative component: String) -> AbsolutePath {
    appending(components: component.split(separator: "/").map(String.init))
  }

  func touch() {
    if exists() { return }
    FileManager.default.createFile(atPath: pathString, contents: nil)
  }

  func subPaths() throws -> [AbsolutePath] {
    try asURL.subPaths().map { try .init(validating: $0.path()) }
  }

  func exists() -> Bool {
    FileManager.default.fileExists(atPath: pathString)
  }

  @discardableResult
  func recreate() throws -> Self {
    if exists() { try remove() }
    try mkdir()
    return self
  }

  func remove() throws {
    try FileManager.default.removeItem(at: asURL)
  }

  @discardableResult
  func mkdir() throws -> Self {
    if exists() { return self }
    try FileManager.default.createDirectory(at: asURL, withIntermediateDirectories: true)
    return self
  }

  func symlink(to dst: AbsolutePath) throws {
    if exists() { try remove() }
    try parentDirectory.mkdir()
    try FileManager.default.createSymbolicLink(at: asURL, withDestinationURL: dst.asURL)
  }
}

extension ObservabilityScope {
  static let liveLog = ObservabilitySystem { scope, diagnostic in
    log.liveOutput(diagnostic.message)
  }.topScope
}

extension Manifest {
  var slug: String {
    path.parentDirectory.basename
  }

  func hasMacro() -> Bool {
    targets.contains { $0.type == .macro }
  }

  static func create(
    displayName: String,
    packageIdentity: PackageIdentity? = nil,
    path: AbsolutePath,
    packageKind: PackageReference.Kind,
    packageLocation: String,
    defaultLocalization: String? = nil,
    platforms: [PlatformDescription],
    version: TSCUtility.Version? = nil,
    revision: String? = nil,
    toolsVersion: ToolsVersion = .current,
    pkgConfig: String? = nil,
    providers: [SystemPackageProviderDescription]? = nil,
    cLanguageStandard: String? = nil,
    cxxLanguageStandard: String? = nil,
    swiftLanguageVersions: [SwiftLanguageVersion]? = nil,
    dependencies: [PackageDependency] = [],
    products: [ProductDescription] = [],
    targets: [TargetDescription] = [],
    traits: Set<TraitDescription> = [],
  ) -> Manifest {
    Manifest(
      displayName: displayName,
      packageIdentity: packageIdentity ?? .plain(path.basename.lowercased()),
      path: path,
      packageKind: packageKind,
      packageLocation: packageLocation,
      defaultLocalization: defaultLocalization,
      platforms: platforms,
      version: version,
      revision: revision,
      toolsVersion: toolsVersion,
      pkgConfig: pkgConfig,
      providers: providers,
      cLanguageStandard: cLanguageStandard,
      cxxLanguageStandard: cxxLanguageStandard,
      swiftLanguageVersions: swiftLanguageVersions,
      dependencies: dependencies,
      products: products,
      targets: targets,
      traits: traits,
    )
  }

  func withChanges(
    pkgDir: AbsolutePath? = nil,
    dependencies: [PackageDependency]? = nil,
    products: [ProductDescription]? = nil,
    targets: [TargetDescription]? = nil,
  ) -> Manifest {
    Manifest(
      displayName: displayName,
      packageIdentity: packageIdentity,
      path: pkgDir.map { $0.appending(path.basename) } ?? self.path,
      packageKind: packageKind,
      packageLocation: packageLocation,
      defaultLocalization: defaultLocalization,
      platforms: platforms,
      version: version,
      revision: revision,
      toolsVersion: max(toolsVersion, .v5_3), // lower version (ex. swift 5.0) does not suppport `.binaryTarget`
      pkgConfig: pkgConfig,
      providers: providers,
      cLanguageStandard: cLanguageStandard,
      cxxLanguageStandard: cxxLanguageStandard,
      swiftLanguageVersions: swiftLanguageVersions,
      dependencies: dependencies ?? self.dependencies,
      products: products ?? self.products,
      targets: targets ?? self.targets,
      traits: traits,
    )
  }

  func write(
    to filePath: AbsolutePath,
    pkgDir: AbsolutePath? = nil,
    additionalImportModuleNames: [String] = [],
  ) throws {
    do {
      let content = try generateManifestFileContents(
        packageDirectory: pkgDir ?? path.parentDirectory,
        additionalImportModuleNames: additionalImportModuleNames,
      )
      try filePath.parentDirectory.mkdir()
      try content.write(toFile: filePath.pathString, atomically: true, encoding: .utf8)
    } catch {
      log.error("Error writing manifest at: \(filePath). Error: \(error)")
      throw error
    }
  }

  func contains(target name: String) -> Bool {
    targets.contains { $0.name == name }
  }

  func contains(product name: String) -> Bool {
    products.contains { $0.name == name }
  }
}

extension TargetDescription {
  func withChanges(
    path: String? = nil,
    dependencies: [TargetDescription.Dependency]? = nil,
    settings: [TargetBuildSettingDescription.Setting]? = nil,
  ) throws -> TargetDescription {
    try TargetDescription(
      name: name,
      dependencies: dependencies ?? self.dependencies,
      path: path ?? self.path,
      url: url,
      exclude: exclude,
      sources: sources,
      resources: resources,
      publicHeadersPath: publicHeadersPath,
      type: type,
      packageAccess: packageAccess,
      pkgConfig: pkgConfig,
      providers: providers,
      pluginCapability: pluginCapability,
      settings: settings ?? self.settings,
      checksum: checksum,
      pluginUsages: pluginUsages,
    )
  }

  var srcPath: String { path ?? "\(type.defaultSrcRoot)/\(name)" }
  var xccacheSrcPath: String { "xccache.src/\(srcPath)" }
}

extension TargetDescription.TargetKind {
  var defaultSrcRoot: String {
    switch self {
    case .test: "Tests"
    case .plugin: "Plugins"
    default: "Sources"
    }
  }
}

extension TargetDescription.Dependency {
  var desc: String {
    pkgName.map { "\($0)/\(name)" } ?? name
  }

  var name: String {
    switch self {
    case
      let .byName(name: name, _),
      let .target(name: name, _),
      let .product(name: name, _, _, _):
      name
    }
  }

  var pkgName: String? {
    switch self {
    case let .product(_, package: pkgName, _, _): pkgName
    default: nil
    }
  }

  var condition: PackageConditionDescription? {
    switch self {
    case
      let .target(_, condition),
      let .product(_, _, _, condition),
      let .byName(_, condition):
      condition
    }
  }

  func relativeTo(pkg pkgName: String) -> Self {
    self.pkgName == pkgName ? .target(name: name, condition: condition) : self
  }
}

extension ResolvedPackage {
  var slug: String { path.basename }
  func localDependency(parent: AbsolutePath) -> PackageDependency {
    .fileSystem(
      identity: identity,
      nameForTargetDependencyResolutionOnly: nil,
      path: parent.appending(slug),
      productFilter: .everything, // FIXME: Hmm. What should be here???
    )
  }
}

extension ModulesGraph {
  func modules(for dep: TargetDescription.Dependency) -> [ResolvedModule] {
    switch dep {
    case .product:
      if let product = product(for: dep) { return product.modules.toArray() }
      log.warning("Cannot find module of: \(dep)")
    case let .target(name: name, condition: _), let .byName(name: name, condition: _):
      if let module = module(for: name) { return [module] }
    }
    return []
  }

  func product(for dep: TargetDescription.Dependency) -> ResolvedProduct? {
    switch dep {
    case let .product(name: name, package: pkgName, moduleAliases: _, condition: _):
      guard let pkgName, let pkg = package(for: .plain(pkgName)) else { return product(for: name) }
      return pkg.products.first { $0.name == name }
    case let .byName(name: name, condition: _):
      return product(for: name)
    case .target:
      return nil
    }
  }

  var rootModules: [ResolvedModule] { rootPackages.flatMap(\.modules) }

  func recursiveModulesFromRoot(excludeMacroDeps: Bool = false) throws -> [ResolvedModule] {
    try rootPackages
      .flatMap(\.modules)
      .flatMap { try $0.recursiveModules(excludeMacroDeps: excludeMacroDeps) }
      .unique()
  }

  func recursiveModules(
    for dependencies: [TargetDescription.Dependency],
    excludeMacroDeps: Bool = false,
  ) throws -> [ResolvedModule] {
    try dependencies
      .flatMap { d in modules(for: d) }
      .flatMap { try $0.recursiveModules(excludeMacroDeps: excludeMacroDeps) }
      .unique()
  }

  func recursiveProducts(
    for dependencies: [TargetDescription.Dependency],
    excludeMacros: Bool = false,
  ) throws -> [ResolvedProduct] {
    let products = dependencies.compactMap { product(for: $0) }
    let recursive = try products
      .flatMap(\.modules)
      .flatMap { try $0.recursiveProducts(excludeMacroDeps: true) }
      .filter { !(excludeMacros && $0.type == .macro) }
    return (products + recursive).unique()
  }

  func recursiveTargetDependencies(
    for dependencies: [TargetDescription.Dependency],
    excludeMacros: Bool = false,
  ) throws -> [TargetDescription.Dependency] {
    // Dependencies can be: a sibling target, or a product of a downstream package.
    // A downstream product can be implicitly declared by name.
    // We're trying to resolve downstream products (both explicit & implicit) first.
    // Sibling dependencies are determined by chosing implicit ones that are not in the downstream products.
    // ----------------------------------------------------------------------------
    // dependencies: [
    //   "X1", // <-- sibling
    //   "Y1", // <-- downstream, implicit
    //   .product(name: "21", package: "Y"), // <-- downstream, explicit
    // ]
    // ----------------------------------------------------------------------------
    let downstream = try recursiveProducts(for: dependencies, excludeMacros: excludeMacros)
      .compactMap { p -> TargetDescription.Dependency? in
        guard let pkg = package(for: p.packageIdentity) else { return nil }
        return .product(name: p.name, package: pkg.slug)
      }
    let siblings = dependencies.filter { d in d.pkgName == nil && !downstream.contains(where: { $0.name == d.name }) }
    return siblings + downstream
  }
}

extension ResolvedModule {
  private func recursiveModules(
    includingSelf: Bool = true,
    successors: (Dependency
    ) -> [ResolvedModule.Dependency],
  ) throws -> [ResolvedModule] {
    let result = try topologicalSort(dependencies, successors: successors).compactMap(\.module)
    return includingSelf ? [self] + result : result
  }

  func recursiveProducts(excludeMacroDeps: Bool = false) throws -> [ResolvedProduct] {
    try topologicalSort(dependencies) { d in
      if excludeMacroDeps, d.module?.type == .macro { return [] }
      return d.dependencies
    }.compactMap(\.product)
  }

  func recursiveModules(includingSelf: Bool = true, excludeMacroDeps: Bool = false) throws -> [ResolvedModule] {
    try recursiveModules(includingSelf: includingSelf) { d in
      if excludeMacroDeps, d.module?.type == .macro { return [] }
      return d.dependencies
    }
  }

  func recursiveSiblingModules(includingSelf: Bool = true) throws -> [ResolvedModule] {
    try recursiveModules(includingSelf: includingSelf, excludeMacroDeps: true).filter { $0.id.pkgId == self.id.pkgId }
  }

  func directModules(excludeMacroDeps: Bool = false) throws -> [ResolvedModule] {
    if excludeMacroDeps, type == .macro { return [] }
    return dependencies.flatMap { d in
      if let module = d.module { return [module] }
      if let product = d.product { return product.modules.toArray() }
      return []
    }
  }
}

extension Sequence where Element: Identifiable {
  func toIdentifiableSet() -> IdentifiableSet<Element> { IdentifiableSet(self) }
  func unique() -> [Element] { Array(toIdentifiableSet()) }
}

extension ResolvedModule.ID {
  // Workaround: to retrieve the internal value of `packageIdentity` for some computations/comparisons
  // Otherwise, we need to obtain the `packageIdentity` from `graph`
  var pkgId: String? {
    Mirror(reflecting: self).children.first(where: { $0.label == "packageIdentity" }).map { "\($0)" }
  }
}
