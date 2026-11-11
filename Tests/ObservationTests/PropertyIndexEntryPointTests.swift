import Testing
import Observation
import Dispatch

// MARK: - Fixture

// Calls the registrar's property-index-tagged entry points directly, the way the v2
// macro will, with the property index for each property chosen by `mode`; or, for
// comparison, the key-path-only overloads.
final class PropertyIndexModel: Observable, @unchecked Sendable {
  enum Mode: CaseIterable, CustomStringConvertible {
    case keyPathOnly
    // Declaration order, as the macro assigns.
    case declarationOrder
    // A property index in the table, but another property's.
    case stale
    // Within the 64-bit mask but past every interned key path.
    case pastTable
    // Past the 64-bit mask, so it has no fast bit.
    case pastMask
    case negative

    var description: String {
      switch self {
      case .keyPathOnly: "keyPathOnly"
      case .declarationOrder: "declarationOrder"
      case .stale: "stale"
      case .pastTable: "pastTable"
      case .pastMask: "pastMask"
      case .negative: "negative"
      }
    }
  }

  private let registrar = ObservationRegistrar()
  private let mode: Mode
  private var storage = [0, 0, 0]

  init(_ mode: Mode) {
    self.mode = mode
  }

  private func propertyIndex(_ index: Int) -> Int? {
    switch mode {
    case .keyPathOnly: nil
    case .declarationOrder: index
    case .stale: (index + 1) % 3
    case .pastTable: 40 + index
    case .pastMask: 64 + index
    case .negative: -1 - index
    }
  }

  private func read(_ index: Int, _ keyPath: KeyPath<PropertyIndexModel, Int>) -> Int {
    if let propertyIndex = propertyIndex(index) {
      registrar.access(self, keyPath: keyPath, propertyIndex: propertyIndex)
    } else {
      registrar.access(self, keyPath: keyPath)
    }
    return storage[index]
  }

  // Through `withMutation`.
  private func write(_ index: Int, _ keyPath: KeyPath<PropertyIndexModel, Int>, _ value: Int) {
    if let propertyIndex = propertyIndex(index) {
      registrar.withMutation(of: self, keyPath: keyPath, propertyIndex: propertyIndex) { storage[index] = value }
    } else {
      registrar.withMutation(of: self, keyPath: keyPath) { storage[index] = value }
    }
  }

  // Through separate `willSet` and `didSet` calls.
  private func writeSplit(_ index: Int, _ keyPath: KeyPath<PropertyIndexModel, Int>, _ value: Int) {
    if let propertyIndex = propertyIndex(index) {
      registrar.willSet(self, keyPath: keyPath, propertyIndex: propertyIndex)
      storage[index] = value
      registrar.didSet(self, keyPath: keyPath, propertyIndex: propertyIndex)
    } else {
      registrar.willSet(self, keyPath: keyPath)
      storage[index] = value
      registrar.didSet(self, keyPath: keyPath)
    }
  }

  var a: Int {
    get { read(0, \.a) }
    set { write(0, \.a, newValue) }
  }

  var b: Int {
    get { read(1, \.b) }
    set { write(1, \.b, newValue) }
  }

  var c: Int {
    get { read(2, \.c) }
    set { writeSplit(2, \.c, newValue) }
  }

  // Notifies a mutation of `b` without changing it, so racing threads
  // share no storage.
  func notifyB() {
    if let propertyIndex = propertyIndex(1) {
      registrar.willSet(self, keyPath: \.b, propertyIndex: propertyIndex)
      registrar.didSet(self, keyPath: \.b, propertyIndex: propertyIndex)
    } else {
      registrar.willSet(self, keyPath: \.b)
      registrar.didSet(self, keyPath: \.b)
    }
  }
}

// Tracks `b` alone first, so on a fresh model `b` is interned first and its
// ordinal (0) is not its declaration-order property index (1); `a` is interned next
// (ordinal 1, property index 0), and `c` last (ordinal 2, property index 2). So with
// `declarationOrder`, `c` hits the reverse table and `a` and `b` miss it.
// Two passes: the second runs after each key path's property index has been learned.
@available(SwiftStdlib 6.4, *)
private func notifications(_ mode: PropertyIndexModel.Mode) -> [String] {
  let log = CapturedState(state: [String]())
  let model = PropertyIndexModel(mode)
  model.a = 1
  for pass in 0..<2 {
    withObservationTracking(options: [.willSet, .didSet]) {
      _blackHole(model.b)
    } onChange: { event in
      log.state.append("\(pass) b \(event.kind == .willSet ? "willSet" : "didSet")")
    }
    model.a += 1
    model.c += 1
    model.b += 1
    model.b += 1

    withObservationTracking {
      _blackHole(model.a)
      _blackHole(model.b)
      _blackHole(model.c)
    } onChange: {
      log.state.append("\(pass) abc")
    }
    model.c += 1
    model.a += 1

    withObservationTracking {
      _blackHole(model.a)
    } onChange: {
      log.state.append("\(pass) a")
    }
    withObservationTracking {
      _blackHole(model.c)
    } onChange: {
      log.state.append("\(pass) c")
    }
    model.b += 1
    model.c += 1
    model.a += 1
  }
  return log.state
}

// Tracks every property in declaration order first, so every ordinal is its
// property index and every `declarationOrder` mutation hits the reverse table.
private func notificationsInternedInOrder(_ mode: PropertyIndexModel.Mode) -> [String] {
  let log = CapturedState(state: [String]())
  let model = PropertyIndexModel(mode)
  withObservationTracking {
    _blackHole(model.a)
    _blackHole(model.b)
    _blackHole(model.c)
  } onChange: {
    log.state.append("abc")
  }
  model.b += 1
  for (name, mutate) in [("a", { model.a += 1 }), ("b", { model.b += 1 }), ("c", { model.c += 1 })] {
    withObservationTracking {
      _blackHole(model.a)
      _blackHole(model.b)
      _blackHole(model.c)
    } onChange: {
      log.state.append(name)
    }
    mutate()
    mutate()
  }
  return log.state
}

// MARK: - Tests

// The property-index-tagged entry points notify exactly as the key-path-only ones do,
// whether the property index hits the reverse table or misses it and falls back.
@available(SwiftStdlib 6.4, *)
@Test(arguments: [
  PropertyIndexModel.Mode.declarationOrder, .stale, .pastTable, .pastMask, .negative,
])
func testPropertyIndexEntryPointsNotifyLikeKeyPathOnly(_ mode: PropertyIndexModel.Mode) {
  let expected = (0..<2).flatMap { pass in
    ["\(pass) b willSet", "\(pass) b didSet", "\(pass) abc", "\(pass) c", "\(pass) a"]
  }
  #expect(notifications(.keyPathOnly) == expected)
  #expect(notifications(mode) == expected)
}

@Test(arguments: [
  PropertyIndexModel.Mode.declarationOrder, .stale, .pastTable, .pastMask, .negative,
])
func testPropertyIndexEntryPointsNotifyLikeKeyPathOnlyWhenInternedInOrder(_ mode: PropertyIndexModel.Mode) {
  let expected = ["abc", "a", "b", "c"]
  #expect(notificationsInternedInOrder(.keyPathOnly) == expected)
  #expect(notificationsInternedInOrder(mode) == expected)
}

// Registrations and cancels (which rewrite the lock-free mask) race
// property-index-tagged mutations reading it; afterwards the mask still lets an
// observer of `b` through.
@Test(.timeLimit(.minutes(1)))
func testPropertyIndexMaskRacingRegistration() {
  let model = PropertyIndexModel(.declarationOrder)
  DispatchQueue.concurrentPerform(iterations: 4) { worker in
    for _ in 0..<1_000 {
      if worker == 0 {
        withObservationTracking {
          _blackHole(model.b)
        } onChange: { }
        withObservationTracking {
          _blackHole(model.a)
        } onChange: { }
      } else {
        model.notifyB()
      }
    }
  }

  let changed = CapturedState(state: 0)
  withObservationTracking {
    _blackHole(model.b)
  } onChange: {
    changed.state += 1
  }
  model.notifyB()
  #expect(changed.state == 1)
}
