import Testing
@_spi(Prototype) import Observation
import Dispatch
import Synchronization

// Every test that reads derived values sits under this suite: they share the
// process-global epoch, so a concurrent test's write to an object a cache has
// read would race the exact input and update counts.
@Suite(.serialized) struct DerivedValueSuites {}

// Counts each cache's `input` and `update` runs, by name.
final class CacheCounts: Sendable {
  private let counts = Mutex([String: Int]())

  func record(_ name: String) {
    counts.withLock { $0[name, default: 0] += 1 }
  }

  subscript(name: String) -> Int {
    counts.withLock { $0[name, default: 0] }
  }

  func reset() {
    counts.withLock { $0.removeAll() }
  }
}

@available(SwiftStdlib 6.5, *)
@Observable
final class DerivedSignal: @unchecked Sendable {
  var a: Double = 3
  var b: Double = 4

  let counts = CacheCounts()
  private let _length = ObservationDerivedValue<Double>()
  private let _isPositive = ObservationDerivedValue<Bool>()
  private let _label = ObservationDerivedValue<String>()

  var length: Double {
    _length.compute {
      counts.record("length.input")
      return (a, b)
    } update: {
      counts.record("length.update")
      return ($0.0 * $0.0 + $0.1 * $0.1).squareRoot()
    }
  }

  var isPositive: Bool {
    _isPositive.compute {
      counts.record("isPositive.input")
      return a
    } update: {
      counts.record("isPositive.update")
      return $0 > 0
    }
  }

  // Reads another cache only.
  var label: String {
    _label.compute {
      counts.record("label.input")
      return isPositive
    } update: {
      counts.record("label.update")
      return $0 ? "positive" : "negative"
    }
  }
}

// Reads itself from its own `input`.
@available(SwiftStdlib 6.5, *)
final class CyclicCache {
  private let _value = ObservationDerivedValue<Int>()
  var value: Int {
    _value.compute { value } update: { $0 + 1 }
  }
}

// Epochs are compared by their low 30 bits, across wraparound.
extension DerivedValueSuites {
  @Test func testEpochWraparoundCompare() {
    let mask: UInt32 = (1 << 30) - 1
    #expect(_observationEpoch(1, isNewerThan: 0))
    #expect(!_observationEpoch(0, isNewerThan: 1))
    #expect(!_observationEpoch(7, isNewerThan: 7))
    // Wrapped past the mask: 0 follows the largest epoch.
    #expect(_observationEpoch(0, isNewerThan: mask))
    #expect(_observationEpoch(5, isNewerThan: mask - 5))
    #expect(!_observationEpoch(mask, isNewerThan: 0))
    // Up to 2^29 - 1 ahead is newer; 2^29 or more ahead is taken for older.
    #expect(_observationEpoch((1 << 29) - 1, isNewerThan: 0))
    #expect(!_observationEpoch(1 << 29, isNewerThan: 0))
    // The bits above the low 30 are ignored.
    #expect(_observationEpoch(0x4000_0001, isNewerThan: 0))
    #expect(!_observationEpoch(0xC000_0000, isNewerThan: 0))
  }

  // The first read computes; a clean re-read runs no `update`. (Nor `input`,
  // unless another thread's write advanced the process-global epoch meanwhile,
  // as tests running in parallel do; ObservationBenchmark's derived-cache-read
  // scenario measures the clean read itself.)
  @available(SwiftStdlib 6.5, *)
  @Test func testCleanReReadRunsNoUpdate() {
    let signal = DerivedSignal()
    #expect(signal.length == 5)
    #expect(signal.counts["length.input"] == 1)
    #expect(signal.counts["length.update"] == 1)

    for _ in 0..<100 {
      #expect(signal.length == 5)
    }
    #expect(signal.counts["length.update"] == 1)
  }

  // (a) Writing every input and reading nothing runs no update; the next read
  // runs exactly one, with the latest inputs.
  @available(SwiftStdlib 6.5, *)
  @Test func testWritesWithoutReadsRunNoUpdates() {
    let signal = DerivedSignal()
    _ = signal.length
    signal.counts.reset()

    for index in 0..<100 {
      signal.a = Double(index)
      signal.b = Double(index)
    }
    #expect(signal.counts["length.input"] == 0)
    #expect(signal.counts["length.update"] == 0)

    signal.a = 6
    signal.b = 8
    #expect(signal.length == 10)
    #expect(signal.counts["length.input"] == 1)
    #expect(signal.counts["length.update"] == 1)
  }

  // (b) An input rewritten to a value that leaves a cache's result equal
  // leaves the caches that read it un-updated.
  @available(SwiftStdlib 6.5, *)
  @Test func testEqualResultLeavesDependentsUnupdated() {
    let signal = DerivedSignal()
    #expect(signal.label == "positive")
    signal.counts.reset()

    signal.a = 10
    #expect(signal.label == "positive")
    #expect(signal.counts["isPositive.update"] == 1)
    #expect(signal.counts["label.update"] == 0)

    signal.a = -1
    #expect(signal.label == "negative")
    #expect(signal.counts["isPositive.update"] == 2)
    #expect(signal.counts["label.update"] == 1)
  }

  // A write to another object does not recompute a cache that did not read
  // it (its `input` may run, to find that out).
  @available(SwiftStdlib 6.5, *)
  @Test func testWriteToUnreadObjectRunsNoUpdate() {
    let signal = DerivedSignal()
    let other = DerivedSignal()
    _ = signal.length
    _ = other.length
    signal.counts.reset()

    other.a = 100
    #expect(signal.length == 5)
    #expect(signal.counts["length.update"] == 0)
    #expect(other.length == (100.0 * 100 + 16).squareRoot())
  }

  // (e) A tracked read of a cached value observes what it depends on, even
  // when the read finds it clean.
  @available(SwiftStdlib 6.5, *)
  @Test func testTrackedReadOfDerivedValueIsNotified() {
    let signal = DerivedSignal()
    _ = signal.length
    let changes = CapturedState(state: 0)

    withObservationTracking {
      #expect(signal.length == 5)
    } onChange: {
      changes.state += 1
    }
    // Clean, so only `input` ran again, for the tracking.
    #expect(signal.counts["length.update"] == 1)

    signal.b = 0
    #expect(changes.state == 1)
    #expect(signal.length == 3)
  }

  // (d) Concurrent readers of one cache all see its value, and it is computed
  // once per round of writes.
  @available(SwiftStdlib 6.5, *)
  @Test(.timeLimit(.minutes(1)))
  func testConcurrentReadersOfOneCache() async {
    let signal = DerivedSignal()
    let rounds = 20
    let readers = 8
    let reads = 500
    for round in 0..<rounds {
      signal.a = Double(round)
      signal.b = 0
      let wrong = Mutex(0)
      await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().async {
          DispatchQueue.concurrentPerform(iterations: readers) { _ in
            for _ in 0..<reads where signal.length != Double(round) {
              wrong.withLock { $0 += 1 }
            }
          }
          done.resume()
        }
      }
      #expect(wrong.withLock { $0 } == 0)
    }
    #expect(signal.counts["length.update"] == rounds)
  }

  // A cache that reads itself traps rather than deadlocking.
  @available(SwiftStdlib 6.5, *)
  @Test func testDerivedValueCycleTraps() async {
    await #expect(processExitsWith: .failure) {
      _ = CyclicCache().value
    }
  }
}

