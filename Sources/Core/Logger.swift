import Foundation
import Logging

private struct BasicLogHandler: LogHandler {
  var logLevel: Logger.Level = .debug
  var metadata: Logger.Metadata = [:]
  subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
    get { metadata[metadataKey] }
    set(newValue) { metadata[metadataKey] = newValue }
  }

  func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
    let pre: String, fd: FileHandle
    switch level {
    case .critical, .error:
      fd = .standardError
      pre = "🚫 "
    case .warning, .notice:
      fd = .standardError
      pre = "⚠️ "
    default:
      fd = .standardOutput
      pre = ""
    }

    if let data = "\(pre)\(message)\n".data(using: .utf8) {
      try? fd.write(contentsOf: data)
    }
  }
}

package let log = Logger(label: "xccache-proxy") { _ in BasicLogHandler() }
