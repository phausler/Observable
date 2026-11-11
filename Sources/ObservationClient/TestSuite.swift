final class TestSuite {
  
  nonisolated(unsafe) static var allTests = [TestSuite]()
  nonisolated(unsafe) static var current: TestSuite?
  
  enum Test {
    case synchronous(String, @MainActor () throws -> Void)
    case asynchronous(String, @MainActor () async throws -> Void)
  }
  
  var tests = [Test]()
  var name: String
  
  init(_ name: String) {
    self.name = name
    TestSuite.allTests.append(self)
  }
  
  func assertionFailure() {
    Swift.assertionFailure()
  }
  
  func caughtFailure(_ error: any Error, _ name: String) {
    assertionFailure()
  }
  
  func runAsync() async {
    TestSuite.current = self
    defer { TestSuite.current = nil }
    for test in tests {
      switch test {
      case .asynchronous(let name, let body):
        do {
          try await body()
          print("test \(name) passed")
        } catch {
          caughtFailure(error, name)
        }
      case .synchronous(let name, let body):
        do {
          try await body()
          print("test \(name) passed")
        } catch {
          caughtFailure(error, name)
        }
      }
    }
  }
  
  func test(_ name: String, _ body: @escaping @MainActor () throws -> Void) {
    tests.append(.synchronous(name, body))
  }
  
  func test(_ name: String, _ body: @escaping @MainActor () async throws -> Void) {
    tests.append(.asynchronous(name, body))
  }
}


func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T) {
  if lhs != rhs {
    TestSuite.current?.assertionFailure()
  }
}

func runAllTestsAsync() async {
  for suite in TestSuite.allTests {
    print("running \(suite.name)")
    await suite.runAsync()
  }
}
