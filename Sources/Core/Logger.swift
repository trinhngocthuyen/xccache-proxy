import Foundation
import os
import Rainbow

package nonisolated(unsafe) let log = Logger()

private class LogHandler {
  var level: Logger.Level = .info
  func handle(_ msg: String, level: Logger.Level) {}
}

private final class OSLogHandler: LogHandler {
  private let underlying = os.Logger(subsystem: "xccache-proxy", category: "main")
  override func handle(_ msg: String, level: Logger.Level) {
    switch level {
    case .error: underlying.error("\(msg, privacy: .public)")
    case .warning: underlying.warning("\(msg, privacy: .public)")
    default: underlying.log("\(msg, privacy: .public)")
    }
  }
}

private final class ConsoleLogHandler: LogHandler {
  class StandardError: TextOutputStream {
    func write(_ string: String) {
      guard let data = string.data(using: .utf8) else { return }
      try? FileHandle.standardError.write(contentsOf: data)
    }
  }

  private var stderr = StandardError()

  override func handle(_ msg: String, level: Logger.Level) {
    guard level >= self.level else { return }

    let formatted: String = switch level {
    case .error: "🚫 \(msg)".red
    case .warning: "⚠️ \(msg)".yellow
    default: msg
    }

    if level >= .warning {
      print(formatted, to: &stderr)
    } else {
      print(formatted)
    }
  }
}

private class CompositeLogHandler: LogHandler {
  private let children: [LogHandler]
  override var level: Logger.Level {
    didSet { children.forEach { $0.level = level } }
  }

  override init() {
    let isRunningInXcode = ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] != nil
    children = isRunningInXcode ? [OSLogHandler()] : [OSLogHandler(), ConsoleLogHandler()]
  }

  override func handle(_ msg: String, level: Logger.Level) {
    children.forEach { $0.handle(msg, level: level) }
  }
}

package struct Logger {
  package enum Level: Int, Comparable {
    case debug = 0, info, warning, error
    package static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  private let handler: LogHandler = CompositeLogHandler()

  package func setLevel(_ level: Level) { handler.level = level }
  package func debug(_ msg: String) { handler.handle(msg, level: .debug) }
  package func info(_ msg: String) { handler.handle(msg, level: .info) }
  package func warning(_ msg: String) { handler.handle(msg, level: .warning) }
  package func error(_ msg: String) { handler.handle(msg, level: .error) }

  package func log(format: String, _ arguments: any CVarArg..., level: Level = .info) {
    handler.handle(String(format: format, arguments: arguments), level: level)
  }
}
