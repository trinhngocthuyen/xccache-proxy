import Foundation

struct Lockfile {
  typealias Model = [String: LockfileModel.ProjectConfig]

  let path: AbsolutePath
  private let underlying: Model

  init(path: AbsolutePath) throws {
    self.path = path
    self.underlying = try JSONDecoder().decode(Model.self, from: Data(contentsOf: path.asURL))
  }

  func packages() -> [LockfileModel.Package] {
    underlying.values.flatMap(\.packages).unique()
  }

  func dependencies() -> [String: [String]] {
    underlying.values.reduce([:]) { acc, x in
      acc.merging(x.dependencies, uniquingKeysWith: { ($0 + $1).unique() })
    }
  }

  func platforms() -> [String: String] {
    underlying.values.reduce([:]) { acc, x
      in acc.merging(x.platforms ?? [:], uniquingKeysWith: { min($0, $1) })
    }
  }
}

enum LockfileModel {
  struct ProjectConfig: Codable {
    let packages: [Package]
    let dependencies: [String: [String]]
    let platforms: [String: String]?
  }

  struct Package: Codable, Hashable {
    let pathFromRoot: String?
    let repositoryURL: String?
    let requirement: [String: String]?

    enum CodingKeys: String, CodingKey {
      case pathFromRoot = "path_from_root"
      case repositoryURL
      case requirement
    }
  }
}
