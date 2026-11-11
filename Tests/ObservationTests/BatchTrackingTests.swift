import Testing
@_spi(Prototype) @_spi(SwiftUI) import Observation

// Trackings installed together, sharing objects, are each notified exactly
// as if each had been installed on its own.
@Test func testBatchInstallNotifiesEachTracking() {
  let log = CapturedState(state: [String]())
  let shared = Person()
  let other = Person()

  var pass = _TrackingPass()
  let a = pass.track {
    _blackHole(shared.firstName)
    _blackHole(other.firstName)
  } onChange: {
    log.state.append("a")
  }
  let b = pass.track {
    _blackHole(shared.firstName)
  } onChange: {
    log.state.append("b")
  }
  let c = pass.track {
    _blackHole(other.lastName)
  } onChange: {
    log.state.append("c")
  }
  // Nothing is installed until the pass installs.
  #expect(a.tracking._registrationTokens.isEmpty)
  pass.install()

  #expect(a.tracking._registrationTokens.count == 2)
  #expect(b.tracking._registrationTokens.count == 1)
  #expect(c.tracking._registrationTokens.count == 1)

  shared.firstName = "x"
  #expect(log.state.sorted() == ["a", "b"])
  other.lastName = "y"
  #expect(log.state.sorted() == ["a", "b", "c"])
  // Each onChange fired once and cancelled its tracking.
  shared.firstName = "z"
  other.firstName = "z"
  #expect(log.state.count == 3)
}

// A batch cancel stops every tracking in it, and only those: a tracking of
// the same objects outside the batch is still notified.
@Test func testBatchCancelCancelsOnlyTheBatch() {
  let log = CapturedState(state: [String]())
  let shared = Person()
  let other = Person()

  var pass = _TrackingPass()
  let a = pass.track {
    _blackHole(shared.firstName)
    _blackHole(other.firstName)
  } onChange: {
    log.state.append("a")
  }
  let b = pass.track {
    _blackHole(shared.firstName)
  } onChange: {
    log.state.append("b")
  }
  pass.install()
  let outside = _withObservationTracking(rearming: nil) {
    _blackHole(shared.firstName)
  } onChange: {
    log.state.append("outside")
  }

  ObservationTracking._cancel([a.tracking, b.tracking])
  #expect(a.tracking._registrationTokens.isEmpty)
  #expect(b.tracking._registrationTokens.isEmpty)

  other.firstName = "x"
  #expect(log.state.isEmpty)
  shared.firstName = "y"
  #expect(log.state == ["outside"])
  _blackHole(outside)
}

// A batch cancel may include trackings already cancelled (here, one that
// fired) and trackings installed one at a time.
@Test func testBatchCancelOfFiredAndSingleInstalledTrackings() {
  let log = CapturedState(state: [String]())
  let person = Person()

  let fired = _withObservationTracking(rearming: nil) {
    _blackHole(person.lastName)
  } onChange: {
    log.state.append("fired")
  }
  let single = _withObservationTracking(rearming: nil) {
    _blackHole(person.firstName)
  } onChange: {
    log.state.append("single")
  }
  person.lastName = "x"
  #expect(log.state == ["fired"])

  ObservationTracking._cancel([fired.tracking, single.tracking])
  person.firstName = "y"
  person.lastName = "z"
  #expect(log.state == ["fired"])
}
