import Basics
import Foundation
import os
@preconcurrency import PackageGraph
import PackageLoading
import PackageModel
import struct TSCUtility.Version
@preconcurrency import Workspace

final class GraphGenerator {
  let graph: ModulesGraph
  let cache: BinariesCache
  let outPath: AbsolutePath
  init(graph: ModulesGraph, cache: BinariesCache, outPath: AbsolutePath) {
    self.graph = graph
    self.cache = cache
    self.outPath = outPath
  }

  func generate() throws {
    let shortNameToFullName: [String: String] = graph.reachableModules.toDictionary { m in
      let fullName = graph.package(for: m).map { "\($0.slug)/\(m.name)" } ?? m.name
      return (m.name, fullName)
    }
    let fullName: (ResolvedModule) -> String = { shortNameToFullName[$0.name] ?? $0.name }

    let modules = try graph.recursiveModulesFromRoot(excludeMacroDeps: true)
    let directDeps = try modules.toDictionary { m in
      try (fullName(m), m.directModules(excludeMacroDeps: true).map(fullName))
    }
    let macros = try graph.rootModules.toDictionary { m in
      let paths = try m.recursiveModules(excludeMacroDeps: true)
        .compactMap { d in cache.binaryPath(for: d.name, ext: "macro") }
        .map(\.pathString)
      return (fullName(m), paths)
    }
    let json: [String: Any] = [
      "deps": directDeps,
      "cache": modules.toDictionary { m in
        (fullName(m), cache.binaryPath(for: m.name, ext: "*").map(\.pathString))
      },
      "macros": macros,
    ]

    try JSONSerialization.data(
      withJSONObject: json,
      options: [.prettyPrinted, .withoutEscapingSlashes],
    ).write(to: outPath.asURL)
  }
}
