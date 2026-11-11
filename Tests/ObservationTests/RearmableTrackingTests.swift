import Testing
@_spi(Prototype) @_spi(SwiftUI) import Observation

// Re-evaluating with the same dependencies keeps the registration: the
// registrar token is the same `Int`, and only the new tracking is notified.
@Test func testRearmWithUnchangedDependenciesKeepsRegistration() {
  let log = CapturedState(state: [String]())
  let person = Person()

  let first = _withObservationTracking(rearming: nil) {
    _blackHole(person.firstName)
  } onChange: {
    log.state.append("first")
  }
  let firstTokens = first.tracking._registrationTokens
  #expect(firstTokens.count == 1)

  let second = _withObservationTracking(rearming: first.tracking) {
    _blackHole(person.firstName)
  } onChange: {
    log.state.append("second")
  }
  #expect(second.tracking._registrationTokens == firstTokens)
  #expect(first.tracking._registrationTokens.isEmpty)

  // Cancelling the consumed tracking must not cancel the kept registration.
  first.tracking.cancel()
  person.firstName = "a"
  person.firstName = "b"

  #expect(log.state == ["second"])
}

// Re-evaluating with different properties of the same object replaces the
// registration: a new token, and only the new property notifies.
@Test func testRearmWithChangedPropertiesReplacesRegistration() {
  let log = CapturedState(state: [String]())
  let person = Person()

  let first = _withObservationTracking(rearming: nil) {
    _blackHole(person.firstName)
  } onChange: {
    log.state.append("first")
  }
  let firstTokens = first.tracking._registrationTokens

  let second = _withObservationTracking(rearming: first.tracking) {
    _blackHole(person.lastName)
  } onChange: {
    log.state.append("second")
  }
  #expect(second.tracking._registrationTokens.count == 1)
  #expect(second.tracking._registrationTokens != firstTokens)

  person.firstName = "a"
  #expect(log.state.isEmpty)
  person.lastName = "b"
  #expect(log.state == ["second"])
}

// Per object: a registration on an object still accessed is kept, one on an
// object no longer accessed is cancelled, and a newly accessed object is
// registered.
@Test func testRearmDiffsPerObject() {
  let log = CapturedState(state: [String]())
  let kept = Person()
  let dropped = Person()
  let added = Person()

  let first = _withObservationTracking(rearming: nil) {
    _blackHole(kept.firstName)
    _blackHole(dropped.firstName)
  } onChange: {
    log.state.append("first")
  }
  let firstTokens = first.tracking._registrationTokens
  #expect(firstTokens.count == 2)

  let second = _withObservationTracking(rearming: first.tracking) {
    _blackHole(added.firstName)
    _blackHole(kept.firstName)
  } onChange: {
    log.state.append("second")
  }
  let secondTokens = second.tracking._registrationTokens
  #expect(secondTokens.count == 2)
  #expect(secondTokens[1] == firstTokens[0])

  dropped.firstName = "a"
  #expect(log.state.isEmpty)
  kept.firstName = "b"
  #expect(log.state == ["second"])
}

// A tracking that already fired (and so cancelled itself) has no
// registrations to keep; re-arming it registers anew, and notifies again.
@Test func testRearmAfterChangeRegistersAgain() {
  let log = CapturedState(state: [String]())
  let person = Person()

  let first = _withObservationTracking(rearming: nil) {
    _blackHole(person.firstName)
  } onChange: {
    log.state.append("first")
  }
  let firstTokens = first.tracking._registrationTokens
  person.firstName = "a"
  #expect(log.state == ["first"])

  let second = _withObservationTracking(rearming: first.tracking) {
    _blackHole(person.firstName)
  } onChange: {
    log.state.append("second")
  }
  #expect(second.tracking._registrationTokens.count == 1)
  #expect(second.tracking._registrationTokens != firstTokens)

  person.firstName = "b"
  person.firstName = "c"
  #expect(log.state == ["first", "second"])
}
