import XCCacheProxy

protocol CommandRunning {
  var rootDir: AbsolutePath? { get }
}

extension CommandRunning {
  static func toAbsolutePath(_ string: String) throws -> AbsolutePath {
    try .init(validating: string, relativeTo: .pwd())
  }

  func projectRootDir() throws -> AbsolutePath {
    try rootDir ?? .pwd()
  }

  func defaultSandboxDir(name: String) throws -> AbsolutePath {
    try projectRootDir().appending(components: ["xccache", "packages", name])
  }

  func withLoggingError(_ block: () async throws -> Void) async rethrows {
    do {
      try await block()
    } catch {
      log.error("Fail to generate proxy. Error: \(error)".bold)
      throw error
    }
  }
}
