import Foundation

struct Env {
  let env = ProcessInfo.processInfo.environment
  subscript(key: String) -> String? { env[key] }

  func isRunningInsideXcode() -> Bool { self["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil }
}

let ENV = Env()
