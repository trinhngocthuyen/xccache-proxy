import Foundation
import Basics
import TSCBasic
import PackageModel
import PackageGraph

typealias AbsolutePath = Basics.AbsolutePath

extension URL {
  func subDirs() -> [URL] {
    FileManager.default.enumerator(
      at: self,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
    )?.compactMap { $0 as? URL } ?? []
  }
}
extension AbsolutePath {
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
  static let logging = ObservabilitySystem { scope, diagnostic in log.debug("\(diagnostic)") }.topScope
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
    targets: [TargetDescription]
  ) -> Manifest {
    return Manifest(
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
      traits: traits
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
        additionalImportModuleNames: additionalImportModuleNames
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
    settings: [TargetBuildSettingDescription.Setting]? = nil
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
      pluginUsages: pluginUsages
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
    switch self {
    case let .byName(name: name, condition: _), let .target(name: name, condition: _):
      return name
    case let .product(name: name, package: pkgName, moduleAliases: _, condition: _):
      if let pkgName { return "\(pkgName)/\(name)" }
      return name
    }
  }
}

extension ResolvedPackage {
  var slug: String { path.basename }
}

extension ModulesGraph {
  func product(for name: String, pkgName: String?) -> ResolvedProduct? {
    guard let pkgName, let pkg = package(for: .plain(pkgName)) else { return product(for: name) }
    return pkg.products.first { $0.name == name }
  }

  func modules(for dep: TargetDescription.Dependency) -> [ResolvedModule] {
    switch dep {
    case let .product(name: name, package: pkgName, moduleAliases: _, condition: _):
      if let product = product(for: name, pkgName: pkgName) { return Array(product.modules) }
      log.warning("Cannot find module of: \(dep)")
    case let .target(name: name, condition: _), let .byName(name: name, condition: _):
      if let module =  module(for: name) { return [module] }
    }
    return []
  }

  func product(for dep: TargetDescription.Dependency) -> ResolvedProduct? {
    switch dep {
    case let .product(name: name, package: pkgName, moduleAliases: _, condition: _):
      return product(for: name, pkgName: pkgName)
    case let .byName(name: name, condition: _):
      return product(for: name)
    case let .target(name: name, condition: _):
      return nil
    }
  }

  func recursiveDependencies(for identity: PackageIdentity) -> [ResolvedPackage] {
    guard let pkg = package(for: identity) else { return [] }
    return [pkg] + pkg.dependencies.flatMap { recursiveDependencies(for: $0) }
  }
}

extension ResolvedModule {
  private func recursiveModules(
    includingSelf: Bool = true,
    successors: (Dependency
  ) -> [ResolvedModule.Dependency]) throws -> [ResolvedModule] {
    let result = try topologicalSort(dependencies, successors: successors).compactMap(\.module)
    return includingSelf ? [self] + result : result
  }

  func recursiveModules(includingSelf: Bool = true, excludeMacros: Bool = false) throws -> [ResolvedModule] {
    return try recursiveModules(includingSelf: includingSelf) { d in
      if excludeMacros, d.module?.type == .macro { return [] }
      return d.dependencies
    }
  }

  func recursiveSiblingModules(includingSelf: Bool = true) throws -> [ResolvedModule] {
    return try recursiveModules(includingSelf: includingSelf) { d in
      d.dependencies.filter { $0.module?.id == self.id }
    }
  }
}

extension Sequence where Element: Identifiable {
  func toIdentifiableSet() -> IdentifiableSet<Element> { IdentifiableSet(self) }
  func unique() -> [Element] { Array(toIdentifiableSet()) }
}
