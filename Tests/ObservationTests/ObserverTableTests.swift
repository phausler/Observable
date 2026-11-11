import Testing
import Observation

// MARK: - Tests

// Cancelling an observer swap-removes its record, so the next registration can
// take the same property index. A second, stale cancel of the first tracking must not
// cancel the observer now in that property index.
@available(SwiftStdlib 6.4, *)
@Test func testStaleCancelAfterPropertyIndexReuseDoesNothing() {
  let firstWillSet = CapturedState(state: 0)
  let firstDidSet = CapturedState(state: 0)
  let second = CapturedState(state: 0)

  let test = Person()
  withObservationTracking(options: [.willSet, .didSet]) {
    _blackHole(test.firstName)
  } onChange: { event in
    guard event.kind == .willSet else {
      firstDidSet.state += 1
      return
    }
    firstWillSet.state += 1
    event.cancel()
    withObservationTracking {
      _blackHole(test.firstName)
    } onChange: {
      second.state += 1
    }
    event.cancel()
  }

  test.firstName = "a"
  #expect(firstWillSet.state == 1)
  #expect(firstDidSet.state == 0)
  #expect(second.state == 0)

  test.firstName = "b"
  #expect(firstWillSet.state == 1)
  #expect(firstDidSet.state == 0)
  #expect(second.state == 1)
}

// Every property of a 100-property object fires its observer, including the
// ones interned past the 64-bit mask.
@Test func testOverflowEveryObservedPropertyFires() {
  let test = HundredProperties()
  for keyPath in HundredProperties.keyPaths {
    let changed = CapturedState(state: 0)
    withObservationTracking {
      test.readAll()
    } onChange: {
      changed.state += 1
    }
    test[keyPath: keyPath] += 1
    #expect(changed.state == 1)
  }
}

// With all 100 key paths interned, an observer of one property fires for that
// property only, whether its ordinal is in the mask or in the overflow.
@Test func testOverflowOnlyObservedPropertyFires() {
  let test = HundredProperties()
  withObservationTracking {
    test.readAll()
  } onChange: { }
  test.p0 += 1

  let keyPaths = HundredProperties.keyPaths
  for (index, keyPath) in keyPaths.enumerated() {
    let other = keyPaths[(index + 1) % keyPaths.count]
    let changed = CapturedState(state: 0)
    withObservationTracking {
      _blackHole(test[keyPath: keyPath])
    } onChange: {
      changed.state += 1
    }
    test[keyPath: other] += 1
    #expect(changed.state == 0)
    test[keyPath: keyPath] += 1
    #expect(changed.state == 1)
  }
}

// With one live observer per property, far past the point the observer table
// indexes its records, each observer (mask and overflow ordinals alike) fires
// for its own property only. The order cancels records from the middle, so
// swap-removes move indexed records, and then drops below the index again.
@Test func testManyLiveObserversFireForTheirOwnPropertyOnly() {
  let test = HundredProperties()
  let keyPaths = HundredProperties.keyPaths
  let changed = keyPaths.map { _ in CapturedState(state: 0) }
  for (index, keyPath) in keyPaths.enumerated() {
    withObservationTracking {
      _blackHole(test[keyPath: keyPath])
    } onChange: {
      changed[index].state += 1
    }
  }

  let order = keyPaths.indices.filter { $0 % 2 == 0 }.reversed()
    + keyPaths.indices.filter { $0 % 2 == 1 }
  for (fired, index) in order.enumerated() {
    test[keyPath: keyPaths[index]] += 1
    #expect(changed[index].state == 1)
    #expect(changed.reduce(0) { $0 + $1.state } == fired + 1)
  }

  for keyPath in keyPaths {
    test[keyPath: keyPath] += 1
  }
  #expect(changed.allSatisfy { $0.state == 1 })
}

// With all 100 key paths interned, an observer of several overflow ordinals,
// read out of order and more than once, fires for each of them and for no
// other property. Unfired observers stay registered, so later iterations also
// dispatch through the observer table's index.
@Test func testOverflowUnsortedRepeatedHighOrdinalsFire() {
  let test = HundredProperties()
  withObservationTracking {
    test.readAll()
  } onChange: { }
  test.p0 += 1

  let keyPaths = HundredProperties.keyPaths
  let observed = [99, 70, 99, 64, 81, 70]
  for index in keyPaths.indices {
    let changed = CapturedState(state: 0)
    withObservationTracking {
      for ordinal in observed {
        _blackHole(test[keyPath: keyPaths[ordinal]])
      }
    } onChange: {
      changed.state += 1
    }
    test[keyPath: keyPaths[index]] += 1
    #expect(changed.state == (observed.contains(index) ? 1 : 0))
  }
}

// Every one of many observers of one property fires once: in inline callback
// storage, past it, and past the point the observer table indexes its
// records, for a mask ordinal and an overflow ordinal alike.
@Test(arguments: [2, 14, 15, 20, 33, 40])
func testManyObserversOfOnePropertyEachFireOnce(count: Int) {
  let test = HundredProperties()
  withObservationTracking {
    test.readAll()
  } onChange: { }
  test.p0 += 1

  for keyPath in [\HundredProperties.p1, \HundredProperties.p70] {
    let changed = (0..<count).map { _ in CapturedState(state: 0) }
    for index in 0..<count {
      withObservationTracking {
        _blackHole(test[keyPath: keyPath])
      } onChange: {
        changed[index].state += 1
      }
    }
    test[keyPath: keyPath] += 1
    #expect(changed.allSatisfy { $0.state == 1 })
    test[keyPath: keyPath] += 1
    #expect(changed.allSatisfy { $0.state == 1 })
  }
}
