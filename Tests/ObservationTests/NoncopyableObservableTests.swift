import Testing
@_spi(SwiftUI) @_spi(Prototype) import Observation

// `@Observable` on a noncopyable struct: properties are observed by property index,
// since no key path can name a property of a noncopyable type.

@available(SwiftStdlib 6.5, *)
@Observable
struct NoncopyableCounter: ~Copyable {
  var count = 0
  var label = ""
  @ObservationIgnored let deinits: CapturedState<Int>

  init(deinits: CapturedState<Int> = CapturedState(state: 0)) {
    self.deinits = deinits
  }

  deinit {
    deinits.state += 1
  }
}

@available(SwiftStdlib 6.5, *)
@Observable
struct NoncopyableSignal: ~Copyable {
  var a: Double = 3
  var b: Double = 4
  @ObservationIgnored let counts = CacheCounts()

  @ObservationDerived var length: Double {
    input {
      counts.record("length.input")
      return (a, b)
    }
    update {
      counts.record("length.update")
      return ($0.0 * $0.0 + $0.1 * $0.1).squareRoot()
    }
  }
}

@available(SwiftStdlib 6.5, *)
final class NoncopyableHolder {
  var counter = NoncopyableCounter()
}

@available(SwiftStdlib 6.5, *)
func readCount(_ counter: borrowing NoncopyableCounter) -> Int {
  counter.count
}

@available(SwiftStdlib 6.5, *)
@Test func testNoncopyableWillSetAndDidSet() {
  let kinds = CapturedState(state: [ObservationTracking.Event.Kind]())
  let matched = CapturedState(state: false)
  var counter = NoncopyableCounter()
  withObservationTracking(options: [.willSet, .didSet]) {
    _blackHole(counter.count)
  } onChange: { event in
    kinds.state.append(event.kind)
    // No key path names a property of a noncopyable type, so none matches.
    if event.matches(\MiddleNamePerson.firstName) {
      matched.state = true
    }
  }
  counter.count = 1
  #expect(kinds.state == [.willSet, .didSet])
  #expect(matched.state == false)
  #expect(counter.count == 1)
}

@available(SwiftStdlib 6.5, *)
@Test func testNoncopyableUntrackedPropertyDoesNotNotify() {
  let changes = CapturedState(state: 0)
  var counter = NoncopyableCounter()
  withObservationTracking {
    _blackHole(counter.count)
  } onChange: {
    changes.state += 1
  }
  counter.label = "unobserved"
  #expect(changes.state == 0)
  // Equal values don't notify either.
  counter.count = 0
  #expect(changes.state == 0)
  counter.count += 1
  #expect(changes.state == 1)
  // The legacy form cancels after its first notification.
  counter.count += 1
  #expect(changes.state == 1)
}

// The same property index in two structs is two properties: each struct's registrar
// notifies only its own observers.
@available(SwiftStdlib 6.5, *)
@Test func testNoncopyableInstancesAreIndependent() {
  let changes = CapturedState(state: 0)
  let observed = NoncopyableCounter()
  var other = NoncopyableCounter()
  withObservationTracking {
    _blackHole(observed.count)
  } onChange: {
    changes.state += 1
  }
  other.count = 5
  #expect(changes.state == 0)
  _ = consume observed
}

@available(SwiftStdlib 6.5, *)
@Test func testNoncopyableChangedIsNil() {
  let sawChange = CapturedState(state: false)
  let changedKeyPath = CapturedState<AnyKeyPath?>(state: nil)
  var counter = NoncopyableCounter()
  withObservationTracking {
    _blackHole(counter.count)
  } willSet: { tracking in
    sawChange.state = true
    changedKeyPath.state = tracking.changed
  }
  counter.count = 2
  #expect(sawChange.state)
  #expect(changedKeyPath.state == nil)
}

@available(SwiftStdlib 6.5, *)
@Test func testNoncopyableHeldInClass() {
  let changes = CapturedState(state: 0)
  let holder = NoncopyableHolder()
  withObservationTracking {
    _blackHole(holder.counter.count)
  } onChange: {
    changes.state += 1
  }
  holder.counter.count = 3
  #expect(changes.state == 1)
  #expect(holder.counter.count == 3)
}

@available(SwiftStdlib 6.5, *)
@Test func testNoncopyableBorrowedRead() {
  let changes = CapturedState(state: 0)
  var counter = NoncopyableCounter()
  let value = withObservationTracking {
    readCount(counter)
  } onChange: {
    changes.state += 1
  }
  #expect(value == 0)
  counter.count = 7
  #expect(changes.state == 1)
}

@available(SwiftStdlib 6.5, *)
@Test func testNoncopyableDeinitEvent() {
  let deinitEvents = CapturedState(state: 0)
  let deinits = CapturedState(state: 0)
  var counter = NoncopyableCounter(deinits: deinits)
  withObservationTracking(options: .deinit) {
    _blackHole(counter.count)
  } onChange: { event in
    if event.kind == .deinit {
      deinitEvents.state += 1
    }
  }
  counter.count = 1
  #expect(deinitEvents.state == 0)
  _ = consume counter
  #expect(deinits.state == 1)
  #expect(deinitEvents.state == 1)
}

extension DerivedValueSuites {
  @available(SwiftStdlib 6.5, *)
  @Test func testNoncopyableDerivedProperty() {
    var signal = NoncopyableSignal()
    #expect(signal.length == 5)
    #expect(signal.length == 5)
    #expect(signal.counts["length.update"] == 1)
    signal.a = 6
    signal.b = 8
    #expect(signal.length == 10)
    #expect(signal.counts["length.update"] == 2)

    // A tracked read of the derived property observes what it depends on.
    let changes = CapturedState(state: 0)
    withObservationTracking {
      _blackHole(signal.length)
    } onChange: {
      changes.state += 1
    }
    signal.b = 0
    #expect(changes.state == 1)
    #expect(signal.length == 6)
  }
}
