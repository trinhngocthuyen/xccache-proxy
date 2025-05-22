@preconcurrency import PackageGraph
import PackageModel

protocol ProxyPackageProtocol {
  var cache: BinariesCache { get }
  var graph: ModulesGraph { get }
  var bare: ResolvedPackage { get }
  var proxiesDir: AbsolutePath { get }

  func generate() throws
}

extension ProxyPackageProtocol {
  var manifest: Manifest { bare.manifest }

  func isBinaryMacro(_ m: ResolvedModule) -> Bool {
    m.type == .macro && cache.hit(m.name)
  }

  func reachableProducts() -> [ProductDescription] {
    manifest.products.filter { p in
      p.targets.allSatisfy { t in graph.reachableModules.contains { $0.name == t } }
    }
  }

  func reachableTargets() -> [TargetDescription] {
    manifest.targets.filter { t in graph.reachableModules.contains { $0.name == t.name } }
  }

  func recursivePackages() throws -> [ResolvedPackage] {
    let recursiveProducts = try reachableTargets()
      .flatMap { try graph.recursiveProducts(for: $0.dependencies, excludeMacros: true) }
    return recursiveProducts
      .unique(\.packageIdentity)
      .filter { $0 != bare.identity }
      .compactMap { graph.package(for: $0) }
  }

  func recursiveDependencies() throws -> [PackageDependency] {
    try recursivePackages().map { $0.localDependency(parent: proxiesDir) }
  }

  func recursiveSiblingModules(
    for this: ProductDescription,
    excludeBinaryMacros: Bool = false,
  ) throws -> [ResolvedModule] {
    let result = try this.targets.compactMap { graph.module(for: $0) }.flatMap { try $0.recursiveSiblingModules() }
    return excludeBinaryMacros ? result.filter { !isBinaryMacro($0) } : result
  }

  func recursiveTargetDependencies(for this: TargetDescription) throws -> [TargetDescription.Dependency] {
    let dependencies = try graph
      .recursiveTargetDependencies(for: this.dependencies, excludeMacros: true)
      .map { $0.relativeTo(pkg: manifest.slug) }
      .sorted { $0.desc.lowercased() < $1.desc.lowercased() } // Make it more readable
    let dependenciesDesc = dependencies.map { "  - \($0.desc)" }.joined(separator: "\n")
    log.debug("🔨 Dependencies for \(this.name):\n\(dependenciesDesc)")
    return dependencies
  }

  func buildSettings(for this: TargetDescription) throws -> [TargetBuildSettingDescription.Setting] {
    let modules = try graph.recursiveModules(for: this.dependencies, excludeMacroDeps: true)
    let macroFlags = modules
      .compactMap { cache.binaryPath(for: $0.name, ext: "macro") }
      .flatMap { p in ["-load-plugin-executable", "\(p.pathString)#\(p.basenameWithoutExt)"] }
    return this.settings + [.init(tool: .swift, kind: .unsafeFlags(macroFlags), condition: nil)]
  }
}
