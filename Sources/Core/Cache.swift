import Basics

final class BinariesCache: @unchecked Sendable {
  let dir: AbsolutePath
  private(set) var modules: [String] = []
  private(set) var binaryModules: Set<String> = []
  private(set) var binaries: [String: AbsolutePath] = [:] {
    didSet { binaryModules = Set(binaries.keys) }
  }

  init(dir: AbsolutePath) {
    self.dir = dir
  }

  func update(modules: [String], artifacts: [AbsolutePath]) throws {
    try artifacts.forEach(createSymlinkToArtifact)
    self.modules = modules
    self.binaries = artifacts.toDictionary { p in (p.basenameWithoutExt, p) }
    for name in modules {
      let xcframeworkPath = dir.appending(components: [name, "\(name).xcframework"])
      let macroPath = dir.appending(components: [name, "\(name).macro"])
      if let p = [xcframeworkPath, macroPath].first(where: { $0.exists() }) {
        self.binaries[name] = p
      }
    }
  }

  func hit(_ modules: String...) -> Bool {
    binaryModules.isSuperset(of: modules)
  }

  func binaryPath(for module: String, ext: String = "xcframework") -> AbsolutePath? {
    guard let path = binaries[module], path.extension == ext || ext == "*" else { return nil }
    return path
  }

  private func createSymlinkToArtifact(_ p: AbsolutePath) throws {
    try dir.appending(components: [p.basenameWithoutExt, p.basename]).symlink(to: p)
  }
}
