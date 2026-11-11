import Testing
@_spi(Prototype) @_spi(SwiftUI) import Observation
import Dispatch
import Synchronization

// A body touching more objects than the access list searches linearly, each
// more than once and not consecutively, and some within a nested tracking,
// still registers exactly once per object and is notified by any of them.
@Test func testManyObjectsAreDeduplicatedAndMerged() {
  let people = (0..<40).map { _ in Person() }
  let log = CapturedState(state: 0)

  let tracked = _withObservationTracking(rearming: nil) {
    for person in people {
      _blackHole(person.firstName)
    }
    for person in people.reversed() {
      _blackHole(person.lastName)
    }
    withObservationTracking {
      for person in people[10..<30] {
        _blackHole(person.firstName)
      }
    } onChange: { }
  } onChange: {
    log.state += 1
  }
  #expect(tracked.tracking._registrationTokens.count == people.count)

  people[25].lastName = "x"
  #expect(log.state == 1)
  people[39].firstName = "x"
  #expect(log.state == 1)
}

final class AtomicFlagAndCount: Sendable {
  let stop = Atomic<Bool>(false)
  let count = Atomic<Int>(0)
}

// A tracking whose onChange fires, and so cancels it, while
// `withObservationTracking(_:onChange:)` is still installing it leaves no
// registration behind to fire again.
@Test(.timeLimit(.minutes(1)))
func testCancelDuringPlainInstallLeavesNoRegistration() {
  let queue = DispatchQueue(label: "test.cancel-during-install")
  for _ in 0..<200 {
    let people = (0..<64).map { _ in Person() }
    let first = people[0]
    let state = AtomicFlagAndCount()
    let started = DispatchSemaphore(value: 0)
    let group = DispatchGroup()

    withObservationTracking {
      for person in people {
        _blackHole(person.age)
      }
      // The body is done reading, so the mutations race only the install.
      queue.async(group: group) {
        started.signal()
        var value = 0
        while !state.stop.load(ordering: .acquiring) {
          value += 1
          first.age = value
        }
      }
      started.wait()
    } onChange: {
      state.count.add(1, ordering: .relaxed)
    }

    let deadline = DispatchTime.now() + .seconds(10)
    while state.count.load(ordering: .relaxed) == 0 && DispatchTime.now() < deadline { }
    state.stop.store(true, ordering: .releasing)
    #expect(group.wait(timeout: .now() + .seconds(10)) == .success)
    let fired = state.count.load(ordering: .relaxed)
    #expect(fired >= 1)

    first.age = -1
    people[63].age = -1
    #expect(state.count.load(ordering: .relaxed) == fired)
  }
}
