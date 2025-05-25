import Foundation

extension ThrowingTaskGroup {
  mutating func addTasks<T: Sendable>(values: any Collection<T>, operation: @Sendable @escaping (T) async throws -> ChildTaskResult) {
    for value in values {
      addTask { try await operation(value) }
    }
  }
}

extension Sequence {
  func toDictionary<Key: Hashable, Value>(_ transform: (Element) throws -> (Key, Value)) rethrows -> [Key: Value] {
    try Dictionary(uniqueKeysWithValues: map(transform))
  }
}

extension Sequence {
  func toArray() -> [Element] { Array(self) }
  func toSet<T: Hashable>(_ f: (Element) throws -> T) rethrows -> Set<T> {
    try map(f).toSet()
  }

  func unique<T: Hashable>(_ f: (Element) throws -> T) rethrows -> [T] {
    try toSet(f).toArray()
  }
}

extension Sequence where Element: Hashable {
  func toSet() -> Set<Element> { Set(self) }
  func unique() -> [Element] { toSet().toArray() }
}

extension Encodable {
  func saveAsJSON(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    try encoder.encode(self).write(to: url)
  }
}
