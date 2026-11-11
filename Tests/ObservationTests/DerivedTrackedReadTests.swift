import Testing
@_spi(Prototype) @_spi(SwiftUI) import Observation
import Synchronization

// Tracked reads of `@ObservationDerived` properties run each derived value's
// `input` once per tracking, however many paths reach it.

@_silgen_name("_swift_observation_tls_get")
private func tlsGet() -> UnsafeMutableRawPointer?

@_silgen_name("_swift_observation_tls_set")
private func tlsSet(_ value: UnsafeMutableRawPointer?)

// As SwiftUI collects an access list: a pointer to an `_AccessList?`
// installed untagged in the observation thread-local.
private func collect<T>(
  _ work: () -> T
) -> (value: T, accessList: ObservationTracking._AccessList?) {
  var accessList: ObservationTracking._AccessList? = nil
  let value = withUnsafeMutablePointer(to: &accessList) { ptr in
    let previous = tlsGet()
    tlsSet(UnsafeMutableRawPointer(ptr))
    defer { tlsSet(previous) }
    return work()
  }
  return (value, accessList)
}

// Six stages of a diamond, each four derived values: `sN` (the stage's
// source), `lN` and `rN` (both read `sN`), and `jN` (joins `lN` and `rN`).
// `s1` reads `root`; `sN` reads `j(N-1)`. Reading `jN` costs 4N inputs.
@available(SwiftStdlib 6.5, *)
@Observable
final class DiamondChain: @unchecked Sendable {
  var root = 1
  @ObservationIgnored let counts = CacheCounts()

  @ObservationDerived var s1: Int {
    input {
      counts.record("s.input")
      return root
    }
    update {
      counts.record("s.update")
      return $0
    }
  }

  @ObservationDerived var l1: Int {
    input {
      counts.record("l.input")
      return s1
    }
    update {
      counts.record("l.update")
      return $0 + 1
    }
  }

  @ObservationDerived var r1: Int {
    input {
      counts.record("r.input")
      return s1
    }
    update {
      counts.record("r.update")
      return $0 + 2
    }
  }

  @ObservationDerived var j1: Int {
    input {
      counts.record("j.input")
      return (l1, r1)
    }
    update {
      counts.record("j.update")
      return $0.0 + $0.1
    }
  }

  @ObservationDerived var s2: Int {
    input {
      counts.record("s.input")
      return j1
    }
    update {
      counts.record("s.update")
      return $0
    }
  }

  @ObservationDerived var l2: Int {
    input {
      counts.record("l.input")
      return s2
    }
    update {
      counts.record("l.update")
      return $0 + 1
    }
  }

  @ObservationDerived var r2: Int {
    input {
      counts.record("r.input")
      return s2
    }
    update {
      counts.record("r.update")
      return $0 + 2
    }
  }

  @ObservationDerived var j2: Int {
    input {
      counts.record("j.input")
      return (l2, r2)
    }
    update {
      counts.record("j.update")
      return $0.0 + $0.1
    }
  }

  @ObservationDerived var s3: Int {
    input {
      counts.record("s.input")
      return j2
    }
    update {
      counts.record("s.update")
      return $0
    }
  }

  @ObservationDerived var l3: Int {
    input {
      counts.record("l.input")
      return s3
    }
    update {
      counts.record("l.update")
      return $0 + 1
    }
  }

  @ObservationDerived var r3: Int {
    input {
      counts.record("r.input")
      return s3
    }
    update {
      counts.record("r.update")
      return $0 + 2
    }
  }

  @ObservationDerived var j3: Int {
    input {
      counts.record("j.input")
      return (l3, r3)
    }
    update {
      counts.record("j.update")
      return $0.0 + $0.1
    }
  }

  @ObservationDerived var s4: Int {
    input {
      counts.record("s.input")
      return j3
    }
    update {
      counts.record("s.update")
      return $0
    }
  }

  @ObservationDerived var l4: Int {
    input {
      counts.record("l.input")
      return s4
    }
    update {
      counts.record("l.update")
      return $0 + 1
    }
  }

  @ObservationDerived var r4: Int {
    input {
      counts.record("r.input")
      return s4
    }
    update {
      counts.record("r.update")
      return $0 + 2
    }
  }

  @ObservationDerived var j4: Int {
    input {
      counts.record("j.input")
      return (l4, r4)
    }
    update {
      counts.record("j.update")
      return $0.0 + $0.1
    }
  }

  @ObservationDerived var s5: Int {
    input {
      counts.record("s.input")
      return j4
    }
    update {
      counts.record("s.update")
      return $0
    }
  }

  @ObservationDerived var l5: Int {
    input {
      counts.record("l.input")
      return s5
    }
    update {
      counts.record("l.update")
      return $0 + 1
    }
  }

  @ObservationDerived var r5: Int {
    input {
      counts.record("r.input")
      return s5
    }
    update {
      counts.record("r.update")
      return $0 + 2
    }
  }

  @ObservationDerived var j5: Int {
    input {
      counts.record("j.input")
      return (l5, r5)
    }
    update {
      counts.record("j.update")
      return $0.0 + $0.1
    }
  }

  @ObservationDerived var s6: Int {
    input {
      counts.record("s.input")
      return j5
    }
    update {
      counts.record("s.update")
      return $0
    }
  }

  @ObservationDerived var l6: Int {
    input {
      counts.record("l.input")
      return s6
    }
    update {
      counts.record("l.update")
      return $0 + 1
    }
  }

  @ObservationDerived var r6: Int {
    input {
      counts.record("r.input")
      return s6
    }
    update {
      counts.record("r.update")
      return $0 + 2
    }
  }

  @ObservationDerived var j6: Int {
    input {
      counts.record("j.input")
      return (l6, r6)
    }
    update {
      counts.record("j.update")
      return $0.0 + $0.1
    }
  }
}

// The value `jN` takes for a given root.
private func expectedJoin(root: Int, stages: Int) -> Int {
  var value = root
  for _ in 0..<stages { value = (value + 1) + (value + 2) }
  return value
}

@available(SwiftStdlib 6.5, *)
extension DiamondChain {
  func join(_ stages: Int) -> Int {
    switch stages {
    case 3: j3
    case 6: j6
    default: fatalError("unsupported")
    }
  }

  var inputs: Int {
    counts["s.input"] + counts["l.input"] + counts["r.input"] + counts["j.input"]
  }

  var updates: Int {
    counts["s.update"] + counts["l.update"] + counts["r.update"] + counts["j.update"]
  }
}

// MARK: - Other fixtures

// `.object` resolution gives every stored property index 0. Derived indices
// follow the stored ones.
@available(SwiftStdlib 6.5, *)
@Observable(resolution: .object)
final class ObjectResolutionDerived: @unchecked Sendable {
  var a = 1
  var b = 2
  @ObservationIgnored let counts = CacheCounts()

  @ObservationDerived var sum: Int {
    input {
      counts.record("sum.input")
      return (a, b)
    }
    update {
      counts.record("sum.update")
      return $0.0 + $0.1
    }
  }

  // Reads the stored property `a` only.
  @ObservationDerived var doubled: Int {
    input {
      counts.record("doubled.input")
      return a
    }
    update {
      counts.record("doubled.update")
      return $0 * 2
    }
  }
}

// Grouped stored properties share an index.
@available(SwiftStdlib 6.5, *)
@Observable
final class GroupedDerived: @unchecked Sendable {
  @ObservationTracked(group: 1) var a = 1
  @ObservationTracked(group: 1) var b = 2
  var c = 3
  @ObservationIgnored let counts = CacheCounts()

  @ObservationDerived var total: Int {
    input {
      counts.record("total.input")
      return (a, b, c)
    }
    update {
      counts.record("total.update")
      return $0.0 + $0.1 + $0.2
    }
  }
}

// A derived value that reads nothing observable.
@available(SwiftStdlib 6.5, *)
@Observable
final class ConstantDerived: @unchecked Sendable {
  var unrelated = 0
  @ObservationIgnored let counts = CacheCounts()

  @ObservationDerived var constant: Int {
    input {
      counts.record("constant.input")
      return 5
    }
    update {
      counts.record("constant.update")
      return $0
    }
  }
}

// `@ObservationDerived` in a container that is not `@Observable`.
@available(SwiftStdlib 6.5, *)
final class PlainContainerDerived: @unchecked Sendable {
  let source = DerivedSource()
  let counts = CacheCounts()

  @ObservationDerived var doubled: Int {
    input {
      counts.record("doubled.input")
      return source.value
    }
    update {
      counts.record("doubled.update")
      return $0 * 2
    }
  }
}

@available(SwiftStdlib 6.5, *)
@Observable
final class DerivedSource: @unchecked Sendable {
  var value = 4
}

// MARK: - Diamond chains

// Baseline: after a root write, an untracked read of the tail runs one
// `input` and one `update` per derived value.
extension DerivedValueSuites {
  @available(SwiftStdlib 6.5, *)
  @Test(arguments: [3, 6])
  func testUntrackedDiamondReadCostsFourInputsPerStage(stages: Int) {
    let chain = DiamondChain()
    _ = chain.join(stages)
    chain.counts.reset()

    chain.root = 10
    #expect(chain.join(stages) == expectedJoin(root: 10, stages: stages))
    #expect(chain.inputs == 4 * stages)
    #expect(chain.updates == 4 * stages)
    #expect(chain.counts["j.update"] == stages)
  }

  // A tracked read of a stale chain runs 4n inputs and the updates an untracked
  // read runs, and the tracking still observes the root.
  @available(SwiftStdlib 6.5, *)
  @Test(arguments: [3, 6])
  func testTrackedReadOfStaleDiamondRunsFourInputsPerStage(stages: Int) {
    let chain = DiamondChain()
    _ = chain.join(stages)
    chain.root = 10
    chain.counts.reset()

    let fired = CapturedState(state: 0)
    withObservationTracking {
      #expect(chain.join(stages) == expectedJoin(root: 10, stages: stages))
    } onChange: {
      fired.state += 1
    }
    #expect(chain.inputs == 4 * stages)
    #expect(chain.updates == 4 * stages)
    #expect(chain.counts["j.update"] == stages)
    #expect(fired.state == 0)

    chain.root = 11
    #expect(fired.state == 1)
    #expect(chain.join(stages) == expectedJoin(root: 11, stages: stages))
  }

  // The very first read, with nothing cached, costs the same.
  @available(SwiftStdlib 6.5, *)
  @Test(arguments: [3, 6])
  func testTrackedFirstReadOfDiamondRunsFourInputsPerStage(stages: Int) {
    let chain = DiamondChain()
    let fired = CapturedState(state: 0)
    withObservationTracking {
      #expect(chain.join(stages) == expectedJoin(root: 1, stages: stages))
    } onChange: {
      fired.state += 1
    }
    #expect(chain.inputs == 4 * stages)
    #expect(chain.updates == 4 * stages)
    chain.root = 2
    #expect(fired.state == 1)
  }

  // A tracked read of a clean chain runs each `input` once, no `update`, and
  // registers the root.
  @available(SwiftStdlib 6.5, *)
  @Test(arguments: [3, 6])
  func testTrackedReadOfCleanDiamondRunsFourInputsPerStage(stages: Int) {
    let chain = DiamondChain()
    _ = chain.join(stages)
    chain.counts.reset()

    let fired = CapturedState(state: 0)
    withObservationTracking {
      #expect(chain.join(stages) == expectedJoin(root: 1, stages: stages))
    } onChange: {
      fired.state += 1
    }
    #expect(chain.inputs == 4 * stages)
    #expect(chain.updates == 0)
    #expect(fired.state == 0)

    chain.root = 7
    #expect(fired.state == 1)
    #expect(chain.join(stages) == expectedJoin(root: 7, stages: stages))
  }

  // Reading the tail twice in one tracking: the second read finds every pair
  // recorded and the caches clean, so it runs nothing.
  @available(SwiftStdlib 6.5, *)
  @Test func testSecondTrackedReadInOneTrackingRunsNothing() {
    let chain = DiamondChain()
    let fired = CapturedState(state: 0)
    withObservationTracking {
      _ = chain.join(3)
      #expect(chain.inputs == 12)
      #expect(chain.updates == 12)
      _ = chain.join(3)
      #expect(chain.inputs == 12)
      #expect(chain.updates == 12)
    } onChange: {
      fired.state += 1
    }
    chain.root = 2
    #expect(fired.state == 1)
  }

  // A write between two reads in one tracking invalidates the caches: the
  // second read recomputes them, once each, and sees the new value.
  @available(SwiftStdlib 6.5, *)
  @Test func testWriteBetweenTrackedReadsInOneTrackingIsNotMissed() {
    let chain = DiamondChain()
    withObservationTracking {
      #expect(chain.join(3) == expectedJoin(root: 1, stages: 3))
      chain.root = 5
      #expect(chain.join(3) == expectedJoin(root: 5, stages: 3))
      #expect(chain.inputs == 24)
      #expect(chain.updates == 24)
      #expect(chain.join(3) == expectedJoin(root: 5, stages: 3))
      #expect(chain.inputs == 24)
      #expect(chain.updates == 24)
    } onChange: { }
  }

  // Two objects of one type share property indices, but not contexts.
  @available(SwiftStdlib 6.5, *)
  @Test func testDerivedVisitsOfDifferentObjectsAreDistinct() {
    let first = DiamondChain()
    let second = DiamondChain()
    let fired = CapturedState(state: 0)
    withObservationTracking {
      _ = first.join(3)
      _ = second.join(3)
    } onChange: {
      fired.state += 1
    }
    #expect(first.inputs == 12)
    #expect(second.inputs == 12)
    #expect(second.updates == 12)

    second.root = 3
    #expect(fired.state == 1)
  }

  // MARK: - SwiftUI-style collection

  @available(SwiftStdlib 6.5, *)
  @Test(arguments: [3, 6])
  func testSwiftUICollectionOfStaleDiamondRunsFourInputsPerStage(stages: Int) {
    let chain = DiamondChain()
    _ = chain.join(stages)
    chain.root = 10
    chain.counts.reset()

    let (value, list) = collect { chain.join(stages) }
    #expect(value == expectedJoin(root: 10, stages: stages))
    #expect(chain.inputs == 4 * stages)
    #expect(chain.updates == 4 * stages)

    let fired = CapturedState(state: 0)
    let tracking = ObservationTracking(list)
    ObservationTracking._installTracking(tracking, willSet: { _ in
      fired.state += 1
    })
    chain.root = 11
    #expect(fired.state == 1)
    tracking.cancel()
  }

  @available(SwiftStdlib 6.5, *)
  @Test(arguments: [3, 6])
  func testSwiftUICollectionOfCleanDiamondRunsFourInputsPerStage(stages: Int) {
    let chain = DiamondChain()
    _ = chain.join(stages)
    chain.counts.reset()

    let (_, list) = collect { chain.join(stages) }
    #expect(chain.inputs == 4 * stages)
    #expect(chain.updates == 0)

    let fired = CapturedState(state: 0)
    let tracking = ObservationTracking(list)
    ObservationTracking._installTracking(tracking, willSet: { _ in
      fired.state += 1
    })
    chain.root = 11
    #expect(fired.state == 1)
    tracking.cancel()
  }

  // The SPI collection used by SwiftUI-facing clients.
  @available(SwiftStdlib 6.5, *)
  @Test func testTrackedAccessListCollectionRunsFourInputsPerStage() {
    let chain = DiamondChain()
    let (_, list) = ObservationTracking._collectAccessList { chain.join(6) }
    #expect(chain.inputs == 24)
    #expect(chain.updates == 24)

    let fired = CapturedState(state: 0)
    let tracking = ObservationTracking(list)
    ObservationTracking._installTracking(tracking, willSet: { _ in
      fired.state += 1
    })
    chain.root = 9
    #expect(fired.state == 1)
    tracking.cancel()
  }

  // A second read in a SwiftUI collection finds the first one's visits.
  @available(SwiftStdlib 6.5, *)
  @Test func testSecondReadInSwiftUICollectionRunsNothing() {
    let chain = DiamondChain()
    let (_, list) = collect {
      _ = chain.join(3)
      _ = chain.join(3)
    }
    #expect(list != nil)
    #expect(chain.inputs == 12)
    #expect(chain.updates == 12)
  }

  // MARK: - Nested collections

  // The outer tracking inherits the inner one's visits: its read of the
  // tail reaches `j3` already visited, so only stages 4-6 run inputs.
  @available(SwiftStdlib 6.5, *)
  @Test func testOuterTrackingAfterNestedTrackingSkipsInnerInputs() {
    let chain = DiamondChain()
    _ = chain.join(6)
    chain.root = 10
    chain.counts.reset()

    let outerFired = CapturedState(state: 0)
    let innerFired = CapturedState(state: 0)
    withObservationTracking {
      withObservationTracking {
        #expect(chain.join(3) == expectedJoin(root: 10, stages: 3))
      } onChange: {
        innerFired.state += 1
      }
      #expect(chain.inputs == 12)
      #expect(chain.join(6) == expectedJoin(root: 10, stages: 6))
    } onChange: {
      outerFired.state += 1
    }
    #expect(chain.inputs == 24)
    #expect(chain.updates == 24)

    chain.root = 11
    #expect(outerFired.state == 1)
    #expect(innerFired.state == 1)
  }

  // Re-reading what the inner tracking visited, from the outer one, runs nothing.
  @available(SwiftStdlib 6.5, *)
  @Test func testOuterRereadAfterNestedTrackingRunsNothing() {
    let chain = DiamondChain()
    let outerFired = CapturedState(state: 0)
    withObservationTracking {
      withObservationTracking {
        _ = chain.join(3)
      } onChange: { }
      #expect(chain.inputs == 12)
      _ = chain.join(3)
      #expect(chain.inputs == 12)
      #expect(chain.updates == 12)
    } onChange: {
      outerFired.state += 1
    }
    chain.root = 2
    #expect(outerFired.state == 1)
  }

  // A SwiftUI collection nested in a tracking, and the tracking after it.
  @available(SwiftStdlib 6.5, *)
  @Test func testTrackingAfterNestedSwiftUICollectionStillRegistersTheChain() {
    let chain = DiamondChain()
    let fired = CapturedState(state: 0)
    withObservationTracking {
      _ = collect { chain.join(3) }
      _ = chain.join(3)
    } onChange: {
      fired.state += 1
    }
    chain.root = 2
    #expect(fired.state == 1)
  }

  // MARK: - Identity and registration

  // Under `.object` resolution every stored property has index 0. Reading a
  // stored property does not count as visiting a derived value, and writing one
  // still notifies.
  @available(SwiftStdlib 6.5, *)
  @Test func testObjectResolutionStoredReadsAreNotDerivedVisits() {
    let model = ObjectResolutionDerived()
    let fired = CapturedState(state: 0)
    withObservationTracking {
      _ = model.a
      _ = model.b
      #expect(model.sum == 3)
      #expect(model.doubled == 2)
    } onChange: {
      fired.state += 1
    }
    #expect(model.counts["sum.input"] == 1)
    #expect(model.counts["doubled.input"] == 1)

    model.b = 5
    #expect(fired.state == 1)
  }

  @available(SwiftStdlib 6.5, *)
  @Test func testObjectResolutionDerivedReadAloneIsNotifiedOfStoredWrite() {
    let model = ObjectResolutionDerived()
    let fired = CapturedState(state: 0)
    withObservationTracking {
      #expect(model.sum == 3)
      #expect(model.sum == 3)
    } onChange: {
      fired.state += 1
    }
    #expect(model.counts["sum.input"] == 1)
    #expect(model.counts["sum.update"] == 1)
    model.a = 10
    #expect(fired.state == 1)
    #expect(model.sum == 12)
  }

  // Derived values of one object are distinct from each other.
  @available(SwiftStdlib 6.5, *)
  @Test func testObjectResolutionDerivedValuesHaveDistinctIdentities() {
    let model = ObjectResolutionDerived()
    withObservationTracking {
      _ = model.sum
      _ = model.doubled
      _ = model.doubled
      _ = model.sum
    } onChange: { }
    #expect(model.counts["sum.input"] == 1)
    #expect(model.counts["doubled.input"] == 1)
  }

  @available(SwiftStdlib 6.5, *)
  @Test func testGroupedStoredReadsAreNotDerivedVisits() {
    let model = GroupedDerived()
    let fired = CapturedState(state: 0)
    withObservationTracking {
      _ = model.a
      _ = model.b
      _ = model.c
      #expect(model.total == 6)
      #expect(model.total == 6)
    } onChange: {
      fired.state += 1
    }
    #expect(model.counts["total.input"] == 1)
    #expect(model.counts["total.update"] == 1)

    model.a = 10
    #expect(fired.state == 1)
  }

  @available(SwiftStdlib 6.5, *)
  @Test func testGroupedDerivedReadIsNotifiedOfEachStoredWrite() {
    for write in [0, 1, 2] {
      let model = GroupedDerived()
      let fired = CapturedState(state: 0)
      withObservationTracking {
        _ = model.total
      } onChange: {
        fired.state += 1
      }
      switch write {
      case 0: model.a = 10
      case 1: model.b = 10
      default: model.c = 10
      }
      #expect(fired.state == 1)
      #expect(model.total == [15, 14, 13][write])
    }
  }

  // A collection holding only a derived visit registers nothing, in either
  // collection kind, and does not disturb unrelated writes.
  @available(SwiftStdlib 6.5, *)
  @Test func testDerivedVisitWithoutDependenciesRegistersNothing() {
    let model = ConstantDerived()
    let fired = CapturedState(state: 0)

    let (value, list) = collect { model.constant }
    #expect(value == 5)
    let tracking = ObservationTracking(list)
    ObservationTracking._installTracking(tracking, willSet: { _ in
      fired.state += 1
    })
    model.unrelated = 1
    #expect(fired.state == 0)
    tracking.cancel()

    let (_, spiList) = ObservationTracking._collectAccessList { model.constant }
    let spiTracking = ObservationTracking(spiList)
    ObservationTracking._installTracking(spiTracking, willSet: { _ in
      fired.state += 1
    })
    model.unrelated = 2
    #expect(fired.state == 0)
    spiTracking.cancel()
  }

  // A list with a stored read and a derived visit registers the stored read only.
  @available(SwiftStdlib 6.5, *)
  @Test func testListWithDerivedVisitRegistersStoredPropertiesOnly() {
    let model = ConstantDerived()
    let fired = CapturedState(state: 0)
    let (_, list) = collect {
      _ = model.constant
      _ = model.unrelated
    }
    let tracking = ObservationTracking(list)
    ObservationTracking._installTracking(tracking, willSet: { _ in
      fired.state += 1
    })
    model.unrelated = 1
    #expect(fired.state == 1)
    tracking.cancel()
    model.unrelated = 2
    #expect(fired.state == 1)
  }

  // MARK: - Unchanged behaviour

  // Hand-written `compute(input:update:)` runs `input` on every tracked read.
  @available(SwiftStdlib 6.5, *)
  @Test func testHandWrittenComputeRunsInputOnEveryTrackedRead() {
    let signal = DerivedSignal()
    let fired = CapturedState(state: 0)
    withObservationTracking {
      _ = signal.length
      _ = signal.length
      _ = signal.length
    } onChange: {
      fired.state += 1
    }
    #expect(signal.counts["length.input"] == 3)
    #expect(signal.counts["length.update"] == 1)

    signal.a = 6
    #expect(fired.state == 1)
  }

  // A container that is not `@Observable` keeps running `input` on every
  // tracked read, and still reports its dependencies.
  @available(SwiftStdlib 6.5, *)
  @Test func testDerivedValueInPlainContainerRunsInputOnEveryTrackedRead() {
    let container = PlainContainerDerived()
    let fired = CapturedState(state: 0)
    withObservationTracking {
      #expect(container.doubled == 8)
      #expect(container.doubled == 8)
    } onChange: {
      fired.state += 1
    }
    #expect(container.counts["doubled.input"] == 2)
    #expect(container.counts["doubled.update"] == 1)

    container.source.value = 5
    #expect(fired.state == 1)
    #expect(container.doubled == 10)
  }

  // Untracked reads are unchanged.
  @available(SwiftStdlib 6.5, *)
  @Test func testUntrackedReadsOfDiamondRunNoInputWhenClean() {
    let chain = DiamondChain()
    _ = chain.join(3)
    chain.counts.reset()
    for _ in 0..<10 { _ = chain.join(3) }
    #expect(chain.updates == 0)
  }
}

