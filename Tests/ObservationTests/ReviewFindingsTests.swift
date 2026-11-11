import Testing
@_spi(Prototype) import Observation
import Synchronization

// Pins behavior of what this package adds over the shipping Observation, as
// found by docs/CODE_REVIEW.md. Tests of a known defect wrap the failing
// expectation in `withKnownIssue`, so the suite passes today and the
// `withKnownIssue` itself fails once the defect is fixed.

// MARK: - ObservationDerivedValue epoch wraparound (CODE_REVIEW.md, C1)

@available(SwiftStdlib 6.5, *)
@Observable
final class ReviewCacheSource: @unchecked Sendable {
  var x = 0
}

@available(SwiftStdlib 6.5, *)
final class ReviewCache: @unchecked Sendable {
  let source = ReviewCacheSource()
  private let _value = ObservationDerivedValue<Int>()

  var value: Int {
    _value.compute {
      source.x
    } update: {
      $0
    }
  }
}

// Epochs are 30 bits wide and compared by distance, so once the global epoch
// was 2^29 or more past the epoch a cache last validated in, the cache read
// as clean and returned its stale value. Every write to an object some cache
// visited in the current epoch advances the epoch by one, so a long-running
// process that re-reads a hot cache and writes its sources gets there; a
// cache untouched for that long must still recompute.
//
// The jump of the epoch stands in for those 2^29 advances. It runs in a
// child process because the epoch is process-global and other tests'
// caches would see the jump.
@available(SwiftStdlib 6.5, *)
@Test func reviewDerivedValueGoesStaleAfterHalfEpochRange() async {
  await #expect(processExitsWith: .success) {
    let cache = ReviewCache()
    precondition(cache.value == 0)
    cache.source.x = 1
    _observationEpochJump(by: 1 << 29)
    precondition(cache.value == 1, "stale cached value")
  }
}

// The same cache, with the epoch moved by less than half the range, is
// recomputed.
@available(SwiftStdlib 6.5, *)
@Test func reviewDerivedValueRecomputesWithinHalfEpochRange() async {
  await #expect(processExitsWith: .success) {
    let cache = ReviewCache()
    precondition(cache.value == 0)
    cache.source.x = 1
    _observationEpochJump(by: (1 << 29) - 2)
    precondition(cache.value == 1)
  }
}

// A write made after the epoch has moved 2^29 or more past the source's
// stamps, from a cache computed before, is seen by the very next read. The
// source's stamps used to be compared with each other by distance, so its
// visited stamp was not moved forward, and its write not stamped, until
// some later read happened to bring them back within range.
@available(SwiftStdlib 6.5, *)
@Test(.timeLimit(.minutes(1))) func reviewDerivedValueSeesWriteAfterHalfEpochRange() async {
  await #expect(processExitsWith: .success) {
    let cache = ReviewCache()
    precondition(cache.value == 0)
    let jumps: [UInt32] = [1 << 29, 3 << 28, (1 << 29) + 1]
    for (index, jump) in jumps.enumerated() {
      _observationEpochJump(by: jump)
      cache.source.x = index + 1
      precondition(cache.value == index + 1, "stale cached value")
    }
  }
}

// A source and cache made only after the epoch has moved 2^29 or more past
// a new object's initial stamps see every write. Those stamps used to be
// taken for a write already stamped, so no write to the source was ever
// stamped and the cache kept its first value.
@available(SwiftStdlib 6.5, *)
@Test(.timeLimit(.minutes(1))) func reviewDerivedValueOverNewSourceSeesWritesAfterHalfEpochRange() async {
  await #expect(processExitsWith: .success) {
    _observationEpochJump(by: (1 << 29) + 5)
    let cache = ReviewCache()
    precondition(cache.value == 0)
    for value in 1...15 {
      cache.source.x = value
      precondition(cache.value == value, "stale cached value")
      precondition(cache.value == value, "stale cached value on re-read")
    }
  }
}

// A source on the key-path-only registrar entry points (a hand-written
// observable type, or one compiled with the old macro) stamps its writes
// through the key-path-only didSet, so caches that read it are invalidated.
@available(SwiftStdlib 6.5, *)
final class ReviewManualSource: Observable, @unchecked Sendable {
  private let registrar = ObservationRegistrar()
  private var _x = 0

  var x: Int {
    get {
      registrar.access(self, keyPath: \.x)
      return _x
    }
    set {
      registrar.withMutation(of: self, keyPath: \.x) {
        _x = newValue
      }
    }
  }
}

extension DerivedValueSuites {
  @available(SwiftStdlib 6.5, *)
  @Test func reviewDerivedValueInvalidatedByKeyPathOnlyWrites() {
    let source = ReviewManualSource()
    let cache = ObservationDerivedValue<Int>()
    func read() -> Int {
      cache.compute { source.x } update: { $0 * 10 }
    }
    #expect(read() == 0)
    source.x = 2
    #expect(read() == 20)
    source.x = 3
    source.x = 4
    #expect(read() == 40)
  }
}

// MARK: - Shared property indices change what `changed` reports (CODE_REVIEW.md, D2)

@Observable(resolution: .object)
final class ReviewObjectResolution: @unchecked Sendable {
  var a = 0
  var b = 0
}

@Observable
final class ReviewGrouped: @unchecked Sendable {
  @ObservationTracked(group: 1) var a = 0
  @ObservationTracked(group: 1) var b = 0
  var c = 0
}

// With `.object` resolution every property passes the first property's key
// path, so a tracking of `b` alone is notified of a change to `a`, and the
// event names `a` for a change to `b`. Opt-in, but it means
// `Event.matches(_:)` and `ObservationTracking.changed` stop naming the
// property that changed.
@Test func reviewObjectResolutionReportsRepresentativeKeyPath() {
  let model = ReviewObjectResolution()
  let events = Mutex([(a: Bool, b: Bool)]())
  withObservationTracking(options: [.willSet]) {
    _ = model.b
  } onChange: { event in
    let a = event.matches(\ReviewObjectResolution.a)
    let b = event.matches(\ReviewObjectResolution.b)
    events.withLock { $0.append((a, b)) }
  }
  model.a = 1
  let recorded = events.withLock { $0 }
  #expect(recorded.count == 1)
  #expect(recorded.first?.a == true)
  #expect(recorded.first?.b == false)
}

@Test func reviewGroupSharesNotificationsButNotOutsideTheGroup() {
  let model = ReviewGrouped()
  let fired = Mutex(0)
  withObservationTracking {
    _ = model.b
  } onChange: {
    fired.withLock { $0 += 1 }
  }
  model.c = 1
  #expect(fired.withLock { $0 } == 0)
  model.a = 1
  #expect(fired.withLock { $0 } == 1)
}
