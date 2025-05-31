import Basics
import Foundation
import os
@preconcurrency import PackageGraph
import PackageLoading
import PackageModel
import struct TSCUtility.Version
@preconcurrency import Workspace

@MainActor
package class UmbrellaGenerator {
  let lockfile: Lockfile
  let projectRootDir: AbsolutePath
  let umbrellaDir: AbsolutePath
  let manifestPath: AbsolutePath

  package init(lockfilePath: AbsolutePath, umbrellaDir: AbsolutePath) throws {
    self.lockfile = try Lockfile(path: lockfilePath)
    self.projectRootDir = lockfile.path.parentDirectory
    self.umbrellaDir = umbrellaDir
    self.manifestPath = umbrellaDir.appending("Package.swift")
  }

  package func run() async throws {
    log.info("Generating umbrella package...".blue)

    let manifest = try Manifest.create(
      displayName: "xccache",
      path: manifestPath,
      packageKind: .fileSystem(umbrellaDir),
      packageLocation: umbrellaDir.pathString,
      platforms: platforms(),
      dependencies: dependencies(),
      products: products(),
      targets: targets(),
    )
    try manifest.write(to: manifestPath)

    // Create auxiliary dirs & files
    try manifest.targets.forEach { target in
      let p = try umbrellaDir.appending(relative: target.srcPath).recreate()
      p.appending("dummy.swift").touch()
    }
    log.info("-> Umbrella manifest: \(manifestPath)".green)
  }

  private func platforms() -> [PlatformDescription] {
    lockfile.platforms().map { .init(name: $0.key.lowercased(), version: $0.value) }
  }

  private func dependencies() throws -> [PackageDependency] {
    try lockfile.packages().map(pkgDependencyFrom)
  }

  private func products() throws -> [ProductDescription] {
    try lockfile.dependencies().keys.map {
      try .init(name: "\($0).xccache", type: .library(.automatic), targets: ["\($0).xccache"])
    }
  }

  private func targets() throws -> [TargetDescription] {
    try lockfile.dependencies().map { name, deps in
      try .init(
        name: "\(name).xccache",
        dependencies: deps.map(targetDependencyFrom),
        path: ".Sources/\(name).xccache",
      )
    }
  }

  private func pkgDependencyFrom(_ model: LockfileModel.Package) throws -> PackageDependency {
    if let pathFromRoot = model.pathFromRoot {
      return try .fileSystem(
        identity: .plain(projectRootDir.basename.lowercased()),
        nameForTargetDependencyResolutionOnly: nil,
        path: projectRootDir.appending(.init(validating: pathFromRoot)),
        productFilter: .everything,
      )
    }
    if let repositoryURL = model.repositoryURL, let requirement = model.requirement {
      return try .sourceControl(
        identity: .plain(repositoryURL),
        nameForTargetDependencyResolutionOnly: nil,
        location: .remote(.init(repositoryURL)),
        requirement: pkgRequirementFrom(requirement),
        productFilter: .everything,
      )
    }
    throw NSError(domain: "Unexpected model: \(model)", code: 123)
  }

  private func pkgRequirementFrom(_ model: [String: String]) throws -> PackageDependency.SourceControl.Requirement {
    guard let kind = model["kind"] else { throw NSError(domain: "Unexpected requirement: \(model)", code: 123) }
    let version: (String) throws -> Version = { try .init(versionString: $0) }
    if kind == "upToNextMajorVersion", let value = model["minimumVersion"] {
      return try .range(.upToNextMajor(from: version(value)))
    } else if kind == "upToNextMinorVersion", let value = model["minimumVersion"] {
      return try .range(.upToNextMinor(from: version(value)))
    } else if kind == "versionRange", let minVersion = model["minimumVersion"], let maxVersion = model["maximumVersion"] {
      return try .range(version(minVersion) ..< version(maxVersion))
    } else if kind == "exactVersion", let value = model["version"] {
      return try .exact(version(value))
    } else if kind == "branch", let value = model["branch"] {
      return .branch(value)
    } else if kind == "revision", let value = model["revision"] {
      return .revision(value)
    }
    throw NSError(domain: "Unexpected requirement: \(model)", code: 123)
  }

  private func targetDependencyFrom(_ s: String) -> TargetDescription.Dependency {
    let cmps = s.split(separator: "/").map(String.init)
    return .product(name: cmps[1], package: cmps[0])
  }
}
