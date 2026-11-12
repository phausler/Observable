import Testing
@_spi(SwiftUI) @_spi(Prototype) import Observation

// `@Observable` on an actor that conforms to `SnapshotSource`: observation as
// for any actor, plus a published snapshot of its properties.

@available(SwiftStdlib 6.5, *)
@Observable
actor SnapshotCounter: SnapshotSource {
  var name = "test"
  var value: Int = 0
  var optional: Int?
  @ObservationIgnored var scratch = NonSendableScratch()
  @ObservationIgnored var ignored = 0

  init() {}

  func increment() { value += 1 }

  func setName(_ name: String) { self.name = name }
  /// Cached snapshot as seen from inside the same job that wrote.
  func incrementAndReadCached() -> Int {
    value += 1
    return latestSnapshot.value
  }

  func incrementManyAndReadCached() -> Int {
    value += 1
    value += 1
    value += 1
    return latestSnapshot.value
  }

  /// Cached snapshot after a real suspension, which lets the refresh job run.
  func incrementYieldAndReadCached() async -> Int {
    value += 1
    await Task.yield()
    return latestSnapshot.value
  }

  /// Cached snapshot after `snapshot`, with no suspension in between.
  func incrementSnapshotAndReadCached() async -> (fresh: Int, cached: Int) {
    value += 1
    let fresh = await snapshot.value
    return (fresh, latestSnapshot.value)
  }

  func appendToValueInPlace() -> Int {
    modifyInPlace(&value)
    return value
  }

  private func modifyInPlace(_ value: inout Int) { value += 10 }

  /// Notifications seen by `log` so far, as of the end of the writing job.
  func incrementAndCount(_ log: CapturedState<[String]>) -> Int {
    value += 1
    return log.state.count
  }
}

final class NonSendableScratch {}

@available(SwiftStdlib 6.5, *)
@Observable
actor SnapshotNamed: SnapshotSource {
  var name = ""
  var count = 0

  // `async`, so the initializer is isolated and may call the setters of
  // properties that have default values.
  init(name: String, count: Int) async {
    self.name = name
    self.count = count
  }
}

@available(SwiftStdlib 6.5, *)
@Test func testSnapshotReflectsValuesAssignedInInit() async throws {
  let named = await SnapshotNamed(name: "set in init", count: 7)
  // `snapshot` is always current, whatever the initializer assigned.
  let fresh = await named.snapshot
  #expect(fresh.name == "set in init")
  #expect(fresh.count == 7)
  // And the published one catches up without any further write.
  for _ in 0..<2000 where named.latestSnapshot.count != 7 {
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(named.latestSnapshot.name == "set in init")
  #expect(named.latestSnapshot.count == 7)
}

/// The refresh is a separately scheduled job with no ordering guarantee relative to other
/// actor hops, so "it lands" is asserted by polling rather than by a single hop.
@available(SwiftStdlib 6.5, *)
func eventuallyCached(_ counter: SnapshotCounter, equals expected: Int) async throws -> Bool {
  for _ in 0..<2000 {
    if counter.latestSnapshot.value == expected { return true }
    try await Task.sleep(for: .milliseconds(1))
  }
  return false
}

@available(SwiftStdlib 6.5, *)
@Test func testSnapshotStartsWithInitialValues() {
  let counter = SnapshotCounter()
  #expect(counter.latestSnapshot.name == "test")
  #expect(counter.latestSnapshot.value == 0)
  #expect(counter.latestSnapshot.optional == nil)
}

@available(SwiftStdlib 6.5, *)
@Test func testSnapshotIsStaleWithinTheWritingJob() async {
  let counter = SnapshotCounter()
  #expect(await counter.incrementAndReadCached() == 0)
}

@available(SwiftStdlib 6.5, *)
@Test func testSnapshotRefreshesAfterTheWritingJobFinishes() async throws {
  let counter = SnapshotCounter()
  await counter.increment()
  #expect(try await eventuallyCached(counter, equals: 1))
}

@available(SwiftStdlib 6.5, *)
@Test func testSnapshotRefreshesAtASuspensionPoint() async {
  let counter = SnapshotCounter()
  #expect(await counter.incrementYieldAndReadCached() == 1)
}

@available(SwiftStdlib 6.5, *)
@Test func testBurstOfWritesPublishesFinalValue() async throws {
  let counter = SnapshotCounter()
  #expect(await counter.incrementManyAndReadCached() == 0)
  #expect(try await eventuallyCached(counter, equals: 3))
}

@available(SwiftStdlib 6.5, *)
@Test func testWritesAfterARefreshScheduleAnotherRefresh() async throws {
  let counter = SnapshotCounter()
  await counter.increment()
  #expect(try await eventuallyCached(counter, equals: 1))
  await counter.increment()
  #expect(try await eventuallyCached(counter, equals: 2))
}

@available(SwiftStdlib 6.5, *)
@Test func testSnapshotMethodPublishesToTheCachedSnapshot() async {
  let counter = SnapshotCounter()
  let (fresh, cached) = await counter.incrementSnapshotAndReadCached()
  #expect(fresh == 1)
  #expect(cached == 1)
}

@available(SwiftStdlib 6.5, *)
@Test func testInPlaceMutationInvalidatesTheSnapshot() async throws {
  let counter = SnapshotCounter()
  #expect(await counter.appendToValueInPlace() == 10)
  #expect(try await eventuallyCached(counter, equals: 10))
}

@available(SwiftStdlib 6.5, *)
@Test func testSnapshotSourceStillObserves() async {
  let changes = CapturedState(state: 0)
  let counter = SnapshotCounter()
  await counter.withIsolation { counter in
    withObservationTracking {
      _blackHole(counter.value)
    } onChange: {
      changes.state += 1
    }
    counter.increment()
  }
  #expect(changes.state == 1)
}

/// Polls until `condition` holds; the refresh is a separately scheduled job.
@available(SwiftStdlib 6.5, *)
func eventually(_ condition: () -> Bool) async throws -> Bool {
  for _ in 0..<2000 {
    if condition() { return true }
    try await Task.sleep(for: .milliseconds(1))
  }
  return false
}

// Reading a property of a snapshot under tracking observes it, and the
// observer is notified once the snapshot that has the new value is published:
// `willSet` before it, with the old value still to read, `didSet` after, with
// the new.
@available(SwiftStdlib 6.5, *)
@Test func testSnapshotObserversAreNotifiedAroundPublication() async throws {
  let log = CapturedState(state: [String]())
  let counter = SnapshotCounter()
  withObservationTracking(options: [.willSet, .didSet]) {
    _blackHole(counter.latestSnapshot.value)
  } onChange: { event in
    // Reading the snapshot while notified must not deadlock on its lock.
    let value = counter.latestSnapshot.value
    log.state.append("\(event.kind == .willSet ? "willSet" : "didSet"):\(value)")
  }
  await counter.increment()
  #expect(try await eventually { log.state.count == 2 })
  #expect(log.state == ["willSet:0", "didSet:1"])
}

// The actor's own write notifies the snapshot's observers only on publication,
// not at the write, when the snapshot would still be stale.
@available(SwiftStdlib 6.5, *)
@Test func testSnapshotObserversAreNotNotifiedAtTheWrite() async throws {
  let log = CapturedState(state: [String]())
  let counter = SnapshotCounter()
  withObservationTracking(options: [.willSet, .didSet]) {
    _blackHole(counter.latestSnapshot.value)
  } onChange: { event in
    log.state.append("\(event.kind)")
  }
  #expect(await counter.incrementAndCount(log) == 0)
  #expect(try await eventually { log.state.count == 2 })
}

@available(SwiftStdlib 6.5, *)
@Test func testSnapshotObserverOfAnotherPropertyIsNotNotified() async throws {
  let changes = CapturedState(state: 0)
  let counter = SnapshotCounter()
  withObservationTracking {
    _blackHole(counter.latestSnapshot.name)
  } onChange: {
    changes.state += 1
  }
  await counter.increment()
  #expect(try await eventuallyCached(counter, equals: 1))
  #expect(changes.state == 0)
}

// A write of an equal value isn't a change: observers of the actor aren't
// notified, and neither are those of the snapshot, which isn't refreshed for it.
@available(SwiftStdlib 6.5, *)
@Test func testEqualWriteDoesNotNotifySnapshotObservers() async throws {
  let changes = CapturedState(state: 0)
  let counter = SnapshotCounter()
  withObservationTracking {
    _blackHole(counter.latestSnapshot.name)
  } onChange: {
    changes.state += 1
  }
  await counter.setName("test")
  // A refresh for another property would have carried `name` along, had the
  // equal write invalidated it.
  await counter.increment()
  #expect(try await eventuallyCached(counter, equals: 1))
  #expect(changes.state == 0)
}

@available(SwiftStdlib 6.5, *)
@Test func testBurstOfWritesNotifiesSnapshotObserversOnceWithTheFinalValue() async throws {
  let log = CapturedState(state: [String]())
  let counter = SnapshotCounter()
  withObservationTracking(options: [.didSet]) {
    _blackHole(counter.latestSnapshot.value)
  } onChange: { event in
    log.state.append("\(counter.latestSnapshot.value)")
  }
  _ = await counter.incrementManyAndReadCached()
  #expect(try await eventually { !log.state.isEmpty })
  #expect(log.state == ["3"])
}

@available(SwiftStdlib 6.5, *)
@Test func testInitialSnapshotReadsAreObserved() async throws {
  let changes = CapturedState(state: 0)
  let counter = SnapshotCounter()
  // Read before any refresh: it is the initial snapshot that is observed.
  withObservationTracking(options: [.didSet]) {
    _blackHole(counter.latestSnapshot.value)
  } onChange: { _ in
    changes.state += 1
  }
  await counter.increment()
  #expect(try await eventually { changes.state == 1 })
}

extension Actor {
  fileprivate func withIsolation<T: Sendable>(_ body: @Sendable (isolated Self) -> T) -> T {
    body(self)
  }
}
