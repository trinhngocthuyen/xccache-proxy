import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

private nonisolated(unsafe) var liveLog: LiveLog?
private let liveLogLock = NSLock()

package extension Logger {
  var live: LiveLog? { liveLogLock.withLock { liveLog } }
  func liveSection(_ header: String, block: @Sendable () async throws -> Void) async rethrows {
    let this = LiveLog()
    liveLogLock.withLock { liveLog = this }
    try await this.with(header: header) { try await block() }
  }

  func liveOutput(_ msg: String, sticky: Bool = false) {
    live?.output(msg, sticky: sticky)
  }
}

package final class LiveLog {
  struct Cursor {
    func csi(_ s: String) -> String { "\u{1B}[\(s)" }
    func up(_ n: Int = 1) -> String { n > 0 ? csi("\(n)A") : "" }
    func down(_ n: Int = 1) -> String { n > 0 ? csi("\(n)B") : "" }
    func column(_ n: Int) -> String { csi("\(n)G") }
    func clearLine() -> String { up() + csi("2K") + column(1) }
    func clear(_ n: Int = 1) -> String {
      n > 0 ? Array(repeating: clearLine(), count: n).joined() : ""
    }

    static let maxTerminalColums: Int = {
      var w = winsize()
      guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0, w.ws_col > 0 else { return 1000 }
      return Int(w.ws_col)
    }()
  }

  let maxLines: Int
  let cursor = Cursor()

  private let lock = NSLock()
  private let dataLock = NSLock()
  private var nSticky: Int = 0
  private var lines: [String] = []
  private var msgOnDone: [(String, Logger.Level)] = []

  init(maxLines: Int = 5) {
    self.maxLines = maxLines
  }

  @MainActor
  func with(header: String, _ block: () async throws -> Void) async rethrows {
    updateHeader(header)
    do {
      try await block()
      clear()
      updateHeader(header + " ✔".green)
      msgOnDone.forEach { log.log($0.0, level: $0.1) }
    } catch {
      updateHeader("\(header.removingColor()) ✖".red) // highlight header
      throw error
    }
  }

  private func updateHeader(_ header: String) {
    commit {
      if lines.isEmpty { return print(header) }
      let n = lines.count + nSticky + 1
      print(cursor.up(n) + header + cursor.column(1) + cursor.down(n))
    } ifInsideXcode: {
      log.info(header)
    }
  }

  func clear() {
    commit {
      print(cursor.clear(lines.count + nSticky + 1), terminator: "")
      lines = []
      nSticky = 0
    } ifInsideXcode: { /* Do nothing */ }
  }

  func msgOnDone(_ msg: String, level: Logger.Level = .debug) {
    dataLock.withLock {
      msgOnDone.append((msg, level))
    }
  }

  func output(_ msg: String, sticky: Bool = false) {
    commit {
      // Trim msg based on screen size
      let msg = msg.count <= Cursor.maxTerminalColums ? msg : "\(msg.prefix(Cursor.maxTerminalColums - 3))..."
      print(cursor.clear(lines.count), terminator: "")
      if sticky {
        nSticky += 1
        print(msg)
      } else {
        if lines.count >= maxLines { lines.removeFirst() }
        lines.append(msg)
      }
      lines.forEach { print($0) }
    } ifInsideXcode: {
      log.debug(msg)
    }
  }

  private func commit(_ block: () -> Void, ifInsideXcode fallback: () -> Void) {
    if ENV.isRunningInsideXcode() { return fallback() }
    lock.withLock {
      block()
      fflush(stdout)
    }
  }
}
