// willSet-burst scenarios (rows A-H, D, D').
//
// Rows A-F and D: N observables, one listener that reads all N, then a burst
// of N writes (one per observable). Reported: listener firings, getter calls
// ("reads") made during the burst, time, and malloc events
// (MallocEventCount.swift). O(n) means reads/N stays flat as N doubles;
// O(n^2) means it doubles. G and H measure dispatch alone.

@_spi(SwiftUI) @_spi(Prototype) import Observation
import Dispatch

nonisolated(unsafe) var burstReads = 0
nonisolated(unsafe) var burstFires = 0

// Hand-written v2 expansion (propertyIndex-tagged entry points), so its getter can
// count reads.
final class BurstLeaf: Observable, @unchecked Sendable {
  let _$observationRegistrar = ObservationRegistrar()
  var _value: Int
  init(_ value: Int) { _value = value }
  var value: Int {
    get {
      burstReads += 1
      _$observationRegistrar.access(self, keyPath: \.value, propertyIndex: 0)
      return _value
    }
    set {
      guard _value != newValue else { return }
      _$observationRegistrar.withMutation(of: self, keyPath: \.value, propertyIndex: 0) { _value = newValue }
    }
  }
}

// One object with N distinct observed properties, spelled as N subscript key paths.
final class BurstWide: Observable, @unchecked Sendable {
  let registrar = ObservationRegistrar()
  var storage: [Int]
  let keyPaths: [KeyPath<BurstWide, Int>]
  init(_ n: Int) {
    storage = Array(0 ..< n)
    keyPaths = (0 ..< n).map { \BurstWide.storage[$0] }
  }
  func get(_ i: Int) -> Int {
    burstReads += 1
    registrar.access(self, keyPath: keyPaths[i], propertyIndex: i)
    return storage[i]
  }
  func set(_ i: Int, _ v: Int) {
    registrar.withMutation(of: self, keyPath: keyPaths[i], propertyIndex: i) { storage[i] = v }
  }
}

func burstReadAll(_ leaves: [BurstLeaf]) -> Int {
  var total = 0
  for leaf in leaves { total &+= leaf.value }
  return total
}

func burst(_ leaves: [BurstLeaf], _ round: Int) {
  for (i, leaf) in leaves.enumerated() { leaf.value = round &* 1_000_003 &+ i &+ 1 }
}

struct BurstMeasurement {
  var fires = 0, reads = 0, nanos: Int64 = 0, mallocs = 0
}

@inline(never)
func measureBurst(_ body: () -> Void) -> BurstMeasurement {
  burstReads = 0
  burstFires = 0
  let clock = ContinuousClock()
  let (elapsed, mallocs) = countingMallocEvents { () -> Duration in
    let start = clock.now
    body()
    return clock.now - start
  }
  let (s, a) = elapsed.components
  return BurstMeasurement(fires: burstFires, reads: burstReads, nanos: s * 1_000_000_000 + a / 1_000_000_000, mallocs: mallocs)
}

// A: public options API, willSet timing, re-armed from inside onChange.
final class BurstRearmOptions: @unchecked Sendable {
  let leaves: [BurstLeaf]
  init(_ leaves: [BurstLeaf]) { self.leaves = leaves }
  func arm() {
    withObservationTracking(options: [.willSet], { _ = burstReadAll(leaves) }, onChange: { [self] _ in
      burstFires += 1
      arm()
    })
  }
}

// B: legacy withObservationTracking(_:onChange:), re-armed from inside onChange.
final class BurstRearmLegacy: @unchecked Sendable {
  let leaves: [BurstLeaf]
  init(_ leaves: [BurstLeaf]) { self.leaves = leaves }
  func arm() {
    withObservationTracking({ _ = burstReadAll(leaves) }, onChange: { [self] in
      burstFires += 1
      arm()
    })
  }
}

// E: re-armed through `_withObservationTracking(rearming:)`, which keeps unchanged registrations instead of cancel + register.
final class BurstRearmPrototype: @unchecked Sendable {
  let leaves: [BurstLeaf]
  var tracking: ObservationTracking?
  init(_ leaves: [BurstLeaf]) { self.leaves = leaves }
  func arm() {
    let previous = tracking
    tracking = nil
    tracking = _withObservationTracking(rearming: previous, { _ = burstReadAll(leaves) }, onChange: { [self] in
      burstFires += 1
      arm()
    }).tracking
  }
}

// H (legacy): firing + re-registering one property.
final class BurstRearmOne: @unchecked Sendable {
  let leaf: BurstLeaf
  init(_ leaf: BurstLeaf) { self.leaf = leaf }
  func arm() {
    withObservationTracking({ _ = leaf.value }, onChange: { [self] in
      burstFires += 1
      arm()
    })
  }
}

// L: a coalesced `Listener` that takes its snapshot again from inside its
// handler, which refreshes what it tracks without re-arming it; `arm()`,
// called from outside the handler, arms it for the next burst.
final class BurstCoalescedListener: @unchecked Sendable {
  let leaves: [BurstLeaf]
  var listener: ObservationTracking.Listener?
  init(_ leaves: [BurstLeaf]) {
    self.leaves = leaves
    listener = ObservationTracking.Listener(options: [.willSet, .coalesced]) { [unowned self] _ in
      burstFires += 1
      track()
    }
  }
  func track() { listener!.track { _ = burstReadAll(leaves) } }
  func arm() { track() }
}

// A read-modify-write burst: the writer reads each value before writing it.
func burstIncrement(_ leaves: [BurstLeaf]) {
  for leaf in leaves { leaf.value += 1 }
}

let burstSizes = [100, 200, 400, 800, 1600]

// One decimal place, without Foundation.
func burstF1(_ x: Double) -> String {
  let tenths = Int((x * 10).rounded())
  return "\(tenths / 10).\(abs(tenths % 10))"
}

func burstRatio(_ a: Int, _ b: Int) -> String { burstF1(Double(a) / Double(b)) }
func burstRatio(_ a: Int64, _ b: Int) -> String { burstF1(Double(a) / Double(b)) }

func burstHeader(_ title: String) {
  print("\n## \(title)")
  print("scenario\tN\tfires\treads\treads/N\tns/write\tmallocs")
}

// Prints a scenario's row and returns it as a JSON result: time and malloc
// events are per write.
func burstRow(_ name: String, _ n: Int, _ r: BurstMeasurement) -> BenchmarkResult {
  print("\(name)\t\(n)\t\(r.fires)\t\(r.reads)\t\(burstRatio(r.reads, n))\t\(burstRatio(r.nanos, n))\t\(r.mallocs)")
  return BenchmarkResult(
    name: "burst \(name) N=\(n)", timeNanoseconds: UInt64(max(r.nanos, 0)) / UInt64(n),
    bytes: nil, mallocCount: nil,
    mallocEvents: r.mallocs < 0 ? nil : Double(r.mallocs) / Double(n), fires: r.fires, reads: r.reads)
}

func willSetBurstScenarios() -> [BenchmarkResult] {
  var results = [BenchmarkResult]()
  burstHeader("Burst of N writes against a listener that reads all N (N separate objects)")
  for n in burstSizes {
    do {
      let leaves = (0 ..< n).map { BurstLeaf($0) }
      let l = BurstRearmOptions(leaves); l.arm(); burst(leaves, 0)   // warm
      results.append(burstRow("A options(.willSet)+rearm", n, measureBurst { burst(leaves, 1) }))
    }
    do {
      let leaves = (0 ..< n).map { BurstLeaf($0) }
      let l = BurstRearmLegacy(leaves); l.arm(); burst(leaves, 0)
      results.append(burstRow("B legacy onChange+rearm", n, measureBurst { burst(leaves, 1) }))
    }
    do {
      // C: SPI willSet listener (SwiftUI's shape): installed once, never cancelled by firing; the
      // listener reads all N from inside the callback, as a pre-change snapshot must.
      let leaves = (0 ..< n).map { BurstLeaf($0) }
      withObservationTracking({ _ = burstReadAll(leaves) }, willSet: { _ in
        burstFires += 1
        _ = burstReadAll(leaves)
      })
      burst(leaves, 0)
      results.append(burstRow("C SPI persistent willSet", n, measureBurst { burst(leaves, 1) }))
    }
    do {
      let leaves = (0 ..< n).map { BurstLeaf($0) }
      let l = BurstRearmPrototype(leaves); l.arm(); burst(leaves, 0)
      results.append(burstRow("E WS6 rearming prototype", n, measureBurst { burst(leaves, 1) }))
    }
    do {
      // F: one-shot, never re-armed. O(n), but it hears only the first write of the first burst.
      let leaves = (0 ..< n).map { BurstLeaf($0) }
      withObservationTracking({ _ = burstReadAll(leaves) }, onChange: { burstFires += 1 })
      results.append(burstRow("F one-shot, no rearm", n, measureBurst { burst(leaves, 1) }))
    }
    do {
      let leaves = (0 ..< n).map { BurstLeaf($0) }
      let l = BurstCoalescedListener(leaves); l.arm(); burst(leaves, 0); l.arm()   // warm, re-arm
      results.append(burstRow("L Listener(.coalesced)", n, measureBurst { burst(leaves, 1) }))
      l.arm()
      // The writer's own N reads are counted too: reads - N is the listener's.
      results.append(burstRow("L Listener(.coalesced), += burst", n, measureBurst { burstIncrement(leaves) }))
    }
  }

  burstHeader("Dispatch cost only: one object, N observed properties, a persistent listener that reads nothing")
  for n in [32, 64, 128, 256, 512, 1024, 2048] {
    let wide = BurstWide(n)
    let install = measureBurst {
      withObservationTracking({ for i in 0 ..< n { _ = wide.get(i) } }, willSet: { _ in burstFires += 1 })
    }
    for i in 0 ..< n { wide.set(i, -i) }   // warm
    let r = measureBurst { for i in 0 ..< n { wide.set(i, i) } }
    print("G wide dispatch\t\(n)\t\(r.fires)\t-\t-\t\(burstRatio(r.nanos, n))\t\(r.mallocs)\t(install: \(install.nanos / 1000) us, \(install.mallocs) mallocs)")
    results.append(BenchmarkResult(
      name: "burst G wide dispatch N=\(n)", timeNanoseconds: UInt64(max(r.nanos, 0)) / UInt64(n),
      bytes: nil, mallocCount: nil,
      mallocEvents: r.mallocs < 0 ? nil : Double(r.mallocs) / Double(n), fires: r.fires, reads: nil))
  }

  burstHeader("Allocations per dispatched write: one property, K persistent willSet listeners that read nothing")
  let writes = 1000
  for k in [1, 2, 3, 8, 33, 64] {
    let leaf = BurstLeaf(0)
    for _ in 0 ..< k {
      withObservationTracking({ _ = leaf.value }, willSet: { _ in burstFires += 1 })
    }
    leaf.value = 1   // warm
    let r = measureBurst { for i in 0 ..< writes { leaf.value = i + 2 } }
    print("H K=\(k)\twrites=\(writes)\tfires=\(r.fires)\tmallocs/write=\(burstRatio(r.mallocs, writes))\tns/write=\(r.nanos / Int64(writes))")
    results.append(BenchmarkResult(
      name: "burst H K=\(k) persistent willSet", timeNanoseconds: UInt64(max(r.nanos, 0)) / UInt64(writes),
      bytes: nil, mallocCount: nil,
      mallocEvents: r.mallocs < 0 ? nil : Double(r.mallocs) / Double(writes), fires: r.fires, reads: nil))
  }
  do {
    let leaf = BurstLeaf(0)
    let one = BurstRearmOne(leaf); one.arm(); leaf.value = 1
    let r = measureBurst { for i in 0 ..< writes { leaf.value = i + 2 } }
    print("H legacy onChange+rearm, 1 prop\twrites=\(writes)\tfires=\(r.fires)\tmallocs/write=\(burstRatio(r.mallocs, writes))\tns/write=\(r.nanos / Int64(writes))")
    results.append(BenchmarkResult(
      name: "burst H legacy onChange+rearm, 1 prop", timeNanoseconds: UInt64(max(r.nanos, 0)) / UInt64(writes),
      bytes: nil, mallocCount: nil,
      mallocEvents: r.mallocs < 0 ? nil : Double(r.mallocs) / Double(writes), fires: r.fires, reads: nil))
  }
  return results
}

// D, D': the listener runs asynchronously after the synchronous burst, on
// the global executor (see `runWillSetBurstAsyncScenarios()`), so it is
// deferred until the burst is done.
func willSetBurstAsyncScenarios() async -> [BenchmarkResult] {
  var results = [BenchmarkResult]()
  burstHeader("Deferred re-arm (async): listener runs after the synchronous burst")
  for n in burstSizes {
    let leaves = (0 ..< n).map { BurstLeaf($0) }
    burstReads = 0; burstFires = 0
    let token = withContinuousObservation(options: [.willSet]) { _ in
      burstFires += 1
      _ = burstReadAll(leaves)
    }
    for _ in 0 ..< 50 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(20))
    let initialReads = burstReads, initialFires = burstFires
    burstReads = 0; burstFires = 0
    let clock = ContinuousClock(); let start = clock.now
    burst(leaves, 1)
    let burstNanos = (clock.now - start).components.attoseconds / 1_000_000_000
    for _ in 0 ..< 50 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(20))
    print("D withContinuousObservation\t\(n)\t\(burstFires)\t\(burstReads)\t\(burstRatio(burstReads, n))\t\(burstNanos / Int64(n))\t-\t(initial: \(initialFires) fire, \(initialReads) reads)")
    results.append(BenchmarkResult(
      name: "burst D withContinuousObservation N=\(n)", timeNanoseconds: UInt64(max(burstNanos, 0)) / UInt64(n),
      bytes: nil, mallocCount: nil, mallocEvents: nil, fires: burstFires, reads: burstReads))
    token.cancel()
  }
  for n in burstSizes {
    let leaves = (0 ..< n).map { BurstLeaf($0) }
    burstReads = 0; burstFires = 0
    let sequence = Observations { burstReadAll(leaves) }
    let consumer = Task {
      for await _ in sequence { burstFires += 1 }
    }
    for _ in 0 ..< 50 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(20))
    let initialFires = burstFires
    burstReads = 0; burstFires = 0
    burst(leaves, 1)
    for _ in 0 ..< 50 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(20))
    print("D' Observations async seq\t\(n)\t\(burstFires)\t\(burstReads)\t\(burstRatio(burstReads, n))\t-\t-\t(initial: \(initialFires) element)")
    results.append(BenchmarkResult(
      name: "burst D' Observations async seq N=\(n)", timeNanoseconds: 0,
      bytes: nil, mallocCount: nil, mallocEvents: nil, fires: burstFires, reads: burstReads))
    consumer.cancel()
  }
  return results
}

// Runs D and D' from the synchronous `main()`, blocking until they finish.
// Nothing they run needs the main thread, so blocking it is safe.
func runWillSetBurstAsyncScenarios() -> [BenchmarkResult] {
  final class Box: @unchecked Sendable { var results = [BenchmarkResult]() }
  let box = Box()
  let done = DispatchSemaphore(value: 0)
  Task {
    box.results = await willSetBurstAsyncScenarios()
    done.signal()
  }
  done.wait()
  return box.results
}
