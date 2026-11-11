import Testing
import Observation
import Dispatch
import Synchronization

// Holds a listener so its own handler can reach it.
private final class ListenerBox: @unchecked Sendable {
  var listener: ObservationTracking.Listener?
}

// A coalesced listener is told of the first change after it tracks, and not
// again until it tracks again.
@available(SwiftStdlib 6.5, *)
@Test func testCoalescedListenerDeliversOncePerArming() {
  let count = CapturedState(state: 0)
  let person = Person()
  var listener = ObservationTracking.Listener(options: [.willSet, .coalesced]) { _ in
    count.state += 1
  }
  listener.track { _blackHole(person.firstName) }

  person.firstName = "a"
  #expect(count.state == 1)
  person.firstName = "b"
  person.firstName = "c"
  #expect(count.state == 1)

  listener.track { _blackHole(person.firstName) }
  person.firstName = "d"
  person.firstName = "e"
  #expect(count.state == 2)
  listener.cancel()
}

// Tracking from inside the handler refreshes what is tracked without
// re-arming, so a burst of writes notifies once.
@available(SwiftStdlib 6.5, *)
@Test(.timeLimit(.minutes(1)))
func testCoalescedListenerTrackingFromHandlerDoesNotRearm() {
  let count = CapturedState(state: 0)
  let person = Person()
  let box = ListenerBox()
  box.listener = ObservationTracking.Listener(options: [.didSet, .coalesced]) { _ in
    count.state += 1
    box.listener!.track { _blackHole(person.firstName) }
  }
  box.listener!.track { _blackHole(person.firstName) }

  for index in 0..<100 {
    person.firstName = "\(index)"
  }
  #expect(count.state == 1)

  box.listener!.track { _blackHole(person.firstName) }
  person.firstName = "again"
  #expect(count.state == 2)
  box.listener = nil
}

// A call to `track` on one thread arms the listener even while its handler
// is running on another thread: only a call from inside the handler, on the
// thread running it, does not re-arm.
@available(SwiftStdlib 6.5, *)
@Test(.timeLimit(.minutes(1)))
func testCoalescedListenerTrackingOnAnotherThreadDuringDeliveryRearms() {
  let count = Mutex(0)
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
  let finished = DispatchSemaphore(value: 0)
  let person = Person()
  let box = ListenerBox()
  box.listener = ObservationTracking.Listener(options: [.willSet, .coalesced]) { _ in
    let calls = count.withLock { value in
      value += 1
      return value
    }
    // The first delivery stays inside the handler until released.
    if calls == 1 {
      entered.signal()
      _ = release.wait(timeout: .now() + .seconds(10))
    }
  }
  box.listener!.track { _blackHole(person.firstName) }

  DispatchQueue.global().async {
    person.firstName = "a"
    finished.signal()
  }
  #expect(entered.wait(timeout: .now() + .seconds(10)) == .success)

  // This thread is not inside the handler, so it arms the listener.
  box.listener!.track { _blackHole(person.lastName) }
  person.lastName = "b"
  let delivered = count.withLock { $0 }

  release.signal()
  #expect(finished.wait(timeout: .now() + .seconds(10)) == .success)
  #expect(delivered == 2)
  box.listener = nil
}

// Without `.coalesced`, every write is delivered, as with
// `withObservationTracking(options:)` re-installed after each change.
@available(SwiftStdlib 6.5, *)
@Test func testUncoalescedListenerDeliversEveryWrite() {
  let kinds = CapturedState(state: [ObservationTracking.Event.Kind]())
  let person = Person()
  var listener = ObservationTracking.Listener(options: [.willSet, .didSet]) { kind in
    kinds.state.append(kind)
  }
  listener.track { _blackHole(person.firstName) }

  person.firstName = "a"
  person.firstName = "b"
  person.lastName = "c"
  #expect(kinds.state == [.willSet, .didSet, .willSet, .didSet])
  listener.cancel()
}

// Each track replaces what the previous one tracked.
@available(SwiftStdlib 6.5, *)
@Test func testListenerTrackReplacesTrackedProperties() {
  let count = CapturedState(state: 0)
  let person = Person()
  let other = Person()
  var listener = ObservationTracking.Listener { _ in
    count.state += 1
  }
  let name = listener.track { person.firstName + other.firstName }
  #expect(name == "")
  person.firstName = "a"
  other.firstName = "b"
  #expect(count.state == 2)

  listener.track { _blackHole(person.lastName) }
  person.firstName = "c"
  other.firstName = "d"
  #expect(count.state == 2)
  person.lastName = "e"
  #expect(count.state == 3)

  // The same properties again keep the registration.
  listener.track { _blackHole(person.lastName) }
  listener.track { _blackHole(person.lastName) }
  person.lastName = "f"
  #expect(count.state == 4)
  listener.cancel()
}

// A cancelled or dropped listener is not told of changes.
@available(SwiftStdlib 6.5, *)
@Test func testListenerCancelAndDropStopDelivery() {
  let count = CapturedState(state: 0)
  let person = Person()
  var listener = ObservationTracking.Listener { _ in
    count.state += 1
  }
  listener.track { _blackHole(person.firstName) }
  listener.cancel()
  person.firstName = "a"
  #expect(count.state == 0)

  do {
    var dropped = ObservationTracking.Listener { _ in
      count.state += 1
    }
    dropped.track { _blackHole(person.firstName) }
  }
  person.firstName = "b"
  #expect(count.state == 0)
}

private let listenerCallCount = CapturedState(state: [Int]())

// A C-convention handler is passed its context and the kind code.
@available(SwiftStdlib 6.5, *)
@Test func testListenerWithCConventionHandler() {
  listenerCallCount.state = []
  let person = Person()
  var marker = 7
  withUnsafeMutablePointer(to: &marker) { pointer in
    var listener = ObservationTracking.Listener(
      options: [.willSet, .didSet],
      context: UnsafeMutableRawPointer(pointer)
    ) { context, code in
      let value = context!.assumingMemoryBound(to: Int.self).pointee
      listenerCallCount.state.append(value * 10 + code)
    }
    listener.track { _blackHole(person.firstName) }
    person.firstName = "a"
    listener.cancel()
  }
  #expect(listenerCallCount.state == [
    70 + ObservationTracking.Listener.willSetCode,
    70 + ObservationTracking.Listener.didSetCode,
  ])
}
