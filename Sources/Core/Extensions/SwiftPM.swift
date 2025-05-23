import Basics
import Foundation
import PackageGraph
import PackageModel
import TSCBasic

typealias AbsolutePath = Basics.AbsolutePath

extension URL {
  func subDirs() -> [URL] {
    FileManager.default.enumerator(
      at: self,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
    )?.compactMap { $0 as? URL } ?? []
  }
}

extension AbsolutePath {
  static func pwd() throws -> Self {
    try .init(validating: URL.currentDirectory().path())
  }

  func subDirs() throws -> [AbsolutePath] {
    try asURL.subDirs().map { try .init(validating: $0.path()) }
  }

  func exists() -> Bool {
    FileManager.default.fileExists(atPath: pathString)
  }

  func remove() throws {
    try FileManager.default.removeItem(at: asURL)
  }

  func mkdir() throws {
    if exists() { return }
    try FileManager.default.createDirectory(at: asURL, withIntermediateDirectories: true)
  }

  func symlink(to dst: AbsolutePath) throws {
    if exists() { try remove() }
    try parentDirectory.mkdir()
    try FileManager.default.createSymbolicLink(at: asURL, withDestinationURL: dst.asURL)
  }
}

extension ObservabilityScope {
  static let logging = ObservabilitySystem { scope, diagnostic in
    switch diagnostic.severity {
    case .error: log.error(diagnostic.message)
    case .warning: log.warning(diagnostic.message)
    case .info: log.info(diagnostic.message)
    case .debug: log.debug(diagnostic.message)
    }
  }.topScope
}

extension Manifest {
  var slug: String {
    path.parentDirectory.basename
  }

  func hasMacro() -> Bool {
    targets.contains { $0.type == .macro }
  }

  func withChanges(
    pkgDir: AbsolutePath,
    dependencies: [PackageDependency],
    products: [ProductDescription],
    targets: [TargetDescription],
  ) -> Manifest {
    Manifest(
      displayName: displayName,
      path: pkgDir.appending(path.basename),
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
      dependencies: dependencies,
      products: products,
      targets: targets,
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

  var srcPath: String {
    path ?? "\(type.defaultSrcRoot)/\(name)"
  }
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
    try recursiveProducts(for: dependencies, excludeMacros: excludeMacros)
      .compactMap { p -> TargetDescription.Dependency? in
        guard let pkg = package(for: p.packageIdentity) else { return nil }
        return .product(name: p.name, package: pkg.slug)
      }
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
    try recursiveModules(includingSelf: includingSelf) { d in
      d.dependencies.filter { $0.module?.id == self.id }
    }
  }
}

extension Sequence where Element: Identifiable {
  func toIdentifiableSet() -> IdentifiableSet<Element> { IdentifiableSet(self) }
  func unique() -> [Element] { Array(toIdentifiableSet()) }
}
