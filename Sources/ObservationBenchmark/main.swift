@_spi(Prototype) @_spi(SwiftUI) import Observation
import Foundation
#if canImport(Darwin)
import Darwin
#endif

@usableFromInline
@inline(never)
func blackHole<T>(_ value: T) { }

struct BenchmarkResult: Codable {
  let name: String
  let timeNanoseconds: UInt64
  let bytes: Double?
  let mallocCount: Double?
  // Allocations counted as events (MallocEventCount.swift) per iteration,
  // rather than `mallocCount`'s net blocks retained.
  var mallocEvents: Double? = nil
  var fires: Int? = nil
  var reads: Int? = nil
  
  enum CodingKeys: String, CodingKey {
    case name
    case timeNanoseconds = "time_nanoseconds"
    case bytes
    case mallocCount = "malloc_count"
    case mallocEvents = "malloc_events"
    case fires
    case reads
  }
}

@Observable
final class Datum {
  var p0 = 0
  var p1 = 0
  var p2 = 0
  var p3 = 0
  var p4 = 0
  var p5 = 0
  var p6 = 0
  var p7 = 0
  var p8 = 0
  var p9 = 0
  var p10 = 0
  var p11 = 0
  var p12 = 0
  var p13 = 0
  var p14 = 0
  var p15 = 0
  var p16 = 0
  var p17 = 0
  var p18 = 0
  var p19 = 0
}

// Extended test class with 128 properties for parametrized observer/property sweeps
@Observable
final class LargeObservableDatum {
  var p0 = 0
  var p1 = 0
  var p2 = 0
  var p3 = 0
  var p4 = 0
  var p5 = 0
  var p6 = 0
  var p7 = 0
  var p8 = 0
  var p9 = 0
  var p10 = 0
  var p11 = 0
  var p12 = 0
  var p13 = 0
  var p14 = 0
  var p15 = 0
  var p16 = 0
  var p17 = 0
  var p18 = 0
  var p19 = 0
  var p20 = 0
  var p21 = 0
  var p22 = 0
  var p23 = 0
  var p24 = 0
  var p25 = 0
  var p26 = 0
  var p27 = 0
  var p28 = 0
  var p29 = 0
  var p30 = 0
  var p31 = 0
  var p32 = 0
  var p33 = 0
  var p34 = 0
  var p35 = 0
  var p36 = 0
  var p37 = 0
  var p38 = 0
  var p39 = 0
  var p40 = 0
  var p41 = 0
  var p42 = 0
  var p43 = 0
  var p44 = 0
  var p45 = 0
  var p46 = 0
  var p47 = 0
  var p48 = 0
  var p49 = 0
  var p50 = 0
  var p51 = 0
  var p52 = 0
  var p53 = 0
  var p54 = 0
  var p55 = 0
  var p56 = 0
  var p57 = 0
  var p58 = 0
  var p59 = 0
  var p60 = 0
  var p61 = 0
  var p62 = 0
  var p63 = 0
  var p64 = 0
  var p65 = 0
  var p66 = 0
  var p67 = 0
  var p68 = 0
  var p69 = 0
  var p70 = 0
  var p71 = 0
  var p72 = 0
  var p73 = 0
  var p74 = 0
  var p75 = 0
  var p76 = 0
  var p77 = 0
  var p78 = 0
  var p79 = 0
  var p80 = 0
  var p81 = 0
  var p82 = 0
  var p83 = 0
  var p84 = 0
  var p85 = 0
  var p86 = 0
  var p87 = 0
  var p88 = 0
  var p89 = 0
  var p90 = 0
  var p91 = 0
  var p92 = 0
  var p93 = 0
  var p94 = 0
  var p95 = 0
  var p96 = 0
  var p97 = 0
  var p98 = 0
  var p99 = 0
  var p100 = 0
  var p101 = 0
  var p102 = 0
  var p103 = 0
  var p104 = 0
  var p105 = 0
  var p106 = 0
  var p107 = 0
  var p108 = 0
  var p109 = 0
  var p110 = 0
  var p111 = 0
  var p112 = 0
  var p113 = 0
  var p114 = 0
  var p115 = 0
  var p116 = 0
  var p117 = 0
  var p118 = 0
  var p119 = 0
  var p120 = 0
  var p121 = 0
  var p122 = 0
  var p123 = 0
  var p124 = 0
  var p125 = 0
  var p126 = 0
  var p127 = 0
}

@inline(never)
func measure(_ name: String, iterations: Int = 1_000_000, _ body: () -> Void) -> (String, Duration) {
  // warmup
  for _ in 0..<min(iterations / 10, 10_000) { body() }

  let clock = ContinuousClock()
  let elapsed = clock.measure {
    for _ in 0..<iterations { body() }
  }
  return (name, elapsed / iterations)
}

func durationToNanos(_ duration: Duration) -> UInt64 {
  let nanos = duration.components.seconds * 1_000_000_000 + Int64(duration.components.attoseconds / 1_000_000_000)
  return UInt64(nanos)
}

@inline(never)
func measureToNanos(_ name: String, iterations: Int = 1_000_000, _ body: () -> Void) -> BenchmarkResult {
  // warmup
  for _ in 0..<min(iterations / 10, 10_000) { body() }

  let clock = ContinuousClock()
  let elapsed = clock.measure {
    for _ in 0..<iterations { body() }
  }
  let nanosPer = durationToNanos(elapsed) / UInt64(iterations)
  return BenchmarkResult(name: name, timeNanoseconds: nanosPer, bytes: nil, mallocCount: nil)
}

#if canImport(Darwin)
func bytesInUse() -> Int {
  var stats = malloc_statistics_t()
  malloc_zone_statistics(nil, &stats)
  return stats.size_in_use
}

func blocksInUse() -> Int {
  var stats = malloc_statistics_t()
  malloc_zone_statistics(nil, &stats)
  return Int(stats.blocks_in_use)
}

// Heap bytes and malloc blocks retained per unit of `body`, measured by
// keeping `count` results alive at once.
func measureMemory<T>(_ name: String, count: Int = 10_000, _ body: () -> T) -> String {
  var retained = [T]()
  retained.reserveCapacity(count)
  let startBytes = bytesInUse()
  let startBlocks = blocksInUse()
  for _ in 0..<count { retained.append(body()) }
  let bytes = Double(bytesInUse() - startBytes) / Double(count)
  let blocks = Double(blocksInUse() - startBlocks) / Double(count)
  withExtendedLifetime(retained) { }
  return "\(name): \(bytes) bytes, \(blocks) mallocs"
}

func measureMemoryToResult<T>(_ name: String, count: Int = 10_000, _ body: () -> T) -> BenchmarkResult {
  var retained = [T]()
  retained.reserveCapacity(count)
  let startBytes = bytesInUse()
  let startBlocks = blocksInUse()
  for _ in 0..<count { retained.append(body()) }
  let bytes = Double(bytesInUse() - startBytes) / Double(count)
  let blocks = Double(blocksInUse() - startBlocks) / Double(count)
  withExtendedLifetime(retained) { }
  return BenchmarkResult(name: name, timeNanoseconds: 0, bytes: bytes, mallocCount: blocks)
}

@Observable
final class Empty { }

final class PlainEmpty { }

func memoryBenchmarks() -> [String] {
  return [
    measureMemory("plain class (no registrar)") { PlainEmpty() },
    measureMemory("@Observable, no properties") { Empty() },
    measureMemory("@Observable, 20 properties") { Datum() },
    measureMemory("observed, 1 prop") { () -> Datum in
      let obj = Datum()
      withObservationTracking { blackHole(obj.p0) } onChange: { }
      return obj
    },
    measureMemory("observed, 5 props") { () -> Datum in
      let obj = Datum()
      withObservationTracking {
        blackHole(obj.p0); blackHole(obj.p1); blackHole(obj.p2)
        blackHole(obj.p3); blackHole(obj.p4)
      } onChange: { }
      return obj
    },
    measureMemory("observed, 1 prop, 3 observers") { () -> Datum in
      let obj = Datum()
      for _ in 0..<3 {
        withObservationTracking { blackHole(obj.p0) } onChange: { }
      }
      return obj
    },
  ]
}

func memoryBenchmarksToResults() -> [BenchmarkResult] {
  return [
    measureMemoryToResult("plain class (no registrar)") { PlainEmpty() },
    measureMemoryToResult("@Observable, no properties") { Empty() },
    measureMemoryToResult("@Observable, 20 properties") { Datum() },
    measureMemoryToResult("observed, 1 prop") { () -> Datum in
      let obj = Datum()
      withObservationTracking { blackHole(obj.p0) } onChange: { }
      return obj
    },
    measureMemoryToResult("observed, 5 props") { () -> Datum in
      let obj = Datum()
      withObservationTracking {
        blackHole(obj.p0); blackHole(obj.p1); blackHole(obj.p2)
        blackHole(obj.p3); blackHole(obj.p4)
      } onChange: { }
      return obj
    },
    measureMemoryToResult("observed, 1 prop, 3 observers") { () -> Datum in
      let obj = Datum()
      for _ in 0..<3 {
        withObservationTracking { blackHole(obj.p0) } onChange: { }
      }
      return obj
    },
  ]
}
#endif

// Baseline: mutation with no observers registered.
// Measures lock acquisition + empty lookup + generation increment.
func benchmarkUnobservedMutation() -> (String, Duration) {
  let obj = Datum()
  return measure("unobserved mutation") {
    obj.p0 += 1
  }
}

// Full observation cycle: register tracking for 1 property, mutate (fires
// observer + cancels), repeat. Measures registration + lookup hit + fire +
// cancellation per iteration.
func benchmarkObservedHit1() -> (String, Duration) {
  let obj = Datum()
  return measure("observed hit (1 prop, full cycle)", iterations: 500_000) {
    withObservationTracking {
      blackHole(obj.p0)
    } onChange: { }
    obj.p0 += 1
  }
}

// Same full cycle but tracking 5 properties per registration.
func benchmarkObservedHit5() -> (String, Duration) {
  let obj = Datum()
  return measure("observed hit (5 props, full cycle)", iterations: 500_000) {
    withObservationTracking {
      blackHole(obj.p0)
      blackHole(obj.p1)
      blackHole(obj.p2)
      blackHole(obj.p3)
      blackHole(obj.p4)
    } onChange: { }
    obj.p0 += 1
  }
}

// Same full cycle but tracking 10 properties per registration.
func benchmarkObservedHit10() -> (String, Duration) {
  let obj = Datum()
  return measure("observed hit (10 props, full cycle)", iterations: 500_000) {
    withObservationTracking {
      blackHole(obj.p0)
      blackHole(obj.p1)
      blackHole(obj.p2)
      blackHole(obj.p3)
      blackHole(obj.p4)
      blackHole(obj.p5)
      blackHole(obj.p6)
      blackHole(obj.p7)
      blackHole(obj.p8)
      blackHole(obj.p9)
    } onChange: { }
    obj.p0 += 1
  }
}

// Lookup miss: observers are registered for p1..pN, but p0 is mutated.
// The lookup dictionary has N entries, every lookup misses.
// Observers never fire so they stay registered across all iterations.
// This isolates the dictionary lookup cost at various sizes.

func benchmarkLookupMiss1() -> (String, Duration) {
  let obj = Datum()
  withObservationTracking {
    blackHole(obj.p1)
  } onChange: { }
  return measure("lookup miss (1 tracked prop)") {
    obj.p0 += 1
  }
}

func benchmarkLookupMiss5() -> (String, Duration) {
  let obj = Datum()
  withObservationTracking {
    blackHole(obj.p1)
    blackHole(obj.p2)
    blackHole(obj.p3)
    blackHole(obj.p4)
    blackHole(obj.p5)
  } onChange: { }
  return measure("lookup miss (5 tracked props)") {
    obj.p0 += 1
  }
}

func benchmarkLookupMiss10() -> (String, Duration) {
  let obj = Datum()
  withObservationTracking {
    blackHole(obj.p1)
    blackHole(obj.p2)
    blackHole(obj.p3)
    blackHole(obj.p4)
    blackHole(obj.p5)
    blackHole(obj.p6)
    blackHole(obj.p7)
    blackHole(obj.p8)
    blackHole(obj.p9)
    blackHole(obj.p10)
  } onChange: { }
  return measure("lookup miss (10 tracked props)") {
    obj.p0 += 1
  }
}

func benchmarkLookupMiss19() -> (String, Duration) {
  let obj = Datum()
  withObservationTracking {
    blackHole(obj.p1)
    blackHole(obj.p2)
    blackHole(obj.p3)
    blackHole(obj.p4)
    blackHole(obj.p5)
    blackHole(obj.p6)
    blackHole(obj.p7)
    blackHole(obj.p8)
    blackHole(obj.p9)
    blackHole(obj.p10)
    blackHole(obj.p11)
    blackHole(obj.p12)
    blackHole(obj.p13)
    blackHole(obj.p14)
    blackHole(obj.p15)
    blackHole(obj.p16)
    blackHole(obj.p17)
    blackHole(obj.p18)
    blackHole(obj.p19)
  } onChange: { }
  return measure("lookup miss (19 tracked props)") {
    obj.p0 += 1
  }
}

// Learned property index mask: the lookup-miss scenarios above never mutate a tracked
// property, so its property index is never learned and the registrar's per-propertyIndex
// `observedMask` stays unfiltered (every bit set): each mutation of p0 still
// takes the lock to look for observers. Mutating the tracked property once
// teaches the registrar its property index, after which mutations of other property indices skip
// the lock. The listener is the persistent SPI willSet one (not cancelled by
// firing), or a legacy onChange registered again after the learning
// mutation fired it. Each reports ns per mutation of p0 and malloc events
// per mutation.

func measureMutation(_ name: String, iterations: Int = 1_000_000, _ body: () -> Void) -> BenchmarkResult {
  var result = measureToNanos(name, iterations: iterations, body)
  let counted = 100_000
  let (_, mallocs) = countingMallocEvents {
    for _ in 0..<counted { body() }
  }
  result.mallocEvents = mallocs < 0 ? nil : Double(mallocs) / Double(counted)
  return result
}

func benchmarkMissColdMask1() -> BenchmarkResult {
  let obj = Datum()
  withObservationTracking({ blackHole(obj.p1) }, willSet: { _ in })
  return measureMutation("lookup miss, property index mask cold (1 tracked prop, persistent willSet)") {
    obj.p0 += 1
  }
}

func benchmarkMissLearnedMask1() -> BenchmarkResult {
  let obj = Datum()
  withObservationTracking({ blackHole(obj.p1) }, willSet: { _ in })
  obj.p1 += 1  // learns p1's propertyIndex
  return measureMutation("lookup miss, property index mask learned (1 tracked prop, persistent willSet)") {
    obj.p0 += 1
  }
}

func benchmarkMissLearnedMask1OnChange() -> BenchmarkResult {
  let obj = Datum()
  withObservationTracking { blackHole(obj.p1) } onChange: { }
  obj.p1 += 1  // learns p1's propertyIndex; fires and cancels
  withObservationTracking { blackHole(obj.p1) } onChange: { }
  return measureMutation("lookup miss, property index mask learned (1 tracked prop, onChange re-registered)") {
    obj.p0 += 1
  }
}

func benchmarkMissColdMask19() -> BenchmarkResult {
  let obj = Datum()
  withObservationTracking({
    blackHole(obj.p1); blackHole(obj.p2); blackHole(obj.p3); blackHole(obj.p4)
    blackHole(obj.p5); blackHole(obj.p6); blackHole(obj.p7); blackHole(obj.p8)
    blackHole(obj.p9); blackHole(obj.p10); blackHole(obj.p11); blackHole(obj.p12)
    blackHole(obj.p13); blackHole(obj.p14); blackHole(obj.p15); blackHole(obj.p16)
    blackHole(obj.p17); blackHole(obj.p18); blackHole(obj.p19)
  }, willSet: { _ in })
  return measureMutation("lookup miss, property index mask cold (19 tracked props, persistent willSet)") {
    obj.p0 += 1
  }
}

func benchmarkMissLearnedMask19() -> BenchmarkResult {
  let obj = Datum()
  withObservationTracking({
    blackHole(obj.p1); blackHole(obj.p2); blackHole(obj.p3); blackHole(obj.p4)
    blackHole(obj.p5); blackHole(obj.p6); blackHole(obj.p7); blackHole(obj.p8)
    blackHole(obj.p9); blackHole(obj.p10); blackHole(obj.p11); blackHole(obj.p12)
    blackHole(obj.p13); blackHole(obj.p14); blackHole(obj.p15); blackHole(obj.p16)
    blackHole(obj.p17); blackHole(obj.p18); blackHole(obj.p19)
  }, willSet: { _ in })
  // Learns every tracked property's property index.
  obj.p1 += 1; obj.p2 += 1; obj.p3 += 1; obj.p4 += 1; obj.p5 += 1
  obj.p6 += 1; obj.p7 += 1; obj.p8 += 1; obj.p9 += 1; obj.p10 += 1
  obj.p11 += 1; obj.p12 += 1; obj.p13 += 1; obj.p14 += 1; obj.p15 += 1
  obj.p16 += 1; obj.p17 += 1; obj.p18 += 1; obj.p19 += 1
  return measureMutation("lookup miss, property index mask learned (19 tracked props, persistent willSet)") {
    obj.p0 += 1
  }
}

// The eager half of a mutation's key path cost: materializing the key path
// literal every mutation passes, with no registrar call at all.
func benchmarkKeyPathFormation() -> BenchmarkResult {
  return measureMutation("key path formation only (\\Datum.p0)") {
    blackHole(\Datum.p0)
  }
}

// Lookup hit: observers are registered for p0, mutate p0.
// The lookup finds the entry, fires the observer (no-op), cancels.
// Unlike the full-cycle benchmarks, this does NOT re-register.
// After the first iteration the observer is gone, so subsequent
// iterations are effectively unobserved. We measure only the first
// hit by using a single iteration with manual timing.
func benchmarkLookupHit1() -> (String, Duration) {
  let iterations = 500_000
  let clock = ContinuousClock()

  // warmup
  for _ in 0..<10_000 {
    let obj = Datum()
    withObservationTracking {
      blackHole(obj.p0)
    } onChange: { }
    obj.p0 += 1
  }

  let elapsed = clock.measure {
    for _ in 0..<iterations {
      let obj = Datum()
      withObservationTracking {
        blackHole(obj.p0)
      } onChange: { }
      obj.p0 += 1
    }
  }
  return ("lookup hit (1 prop, new obj/iter)", elapsed / iterations)
}

// Re-evaluation with a stable dependency set: a body reading the
// same 5 properties is re-evaluated every iteration, with no mutation in
// between, as a view body is when re-rendered for another reason. The
// baseline cancels the previous tracking and registers a new one, as two
// independent `withObservationTracking` calls do; the re-armed version keeps
// the registration.
func benchmarkReevaluateStableCancelAndRegister() -> (String, Duration) {
  let obj = Datum()
  var previous: ObservationTracking?
  return measure("re-evaluate stable deps (5 props, cancel + register)", iterations: 500_000) {
    previous?.cancel()
    previous = _withObservationTracking(rearming: nil) {
      blackHole(obj.p0)
      blackHole(obj.p1)
      blackHole(obj.p2)
      blackHole(obj.p3)
      blackHole(obj.p4)
    } onChange: { }.tracking
  }
}

func benchmarkReevaluateStableRearmed() -> (String, Duration) {
  let obj = Datum()
  var previous: ObservationTracking?
  return measure("re-evaluate stable deps (5 props, re-armed)", iterations: 500_000) {
    previous = _withObservationTracking(rearming: previous) {
      blackHole(obj.p0)
      blackHole(obj.p1)
      blackHole(obj.p2)
      blackHole(obj.p3)
      blackHole(obj.p4)
    } onChange: { }.tracking
  }
}

// Batch install/cancel: one update pass of N = 16 trackings over
// M = 4 shared objects, every tracking reading a property of every object,
// installed and then cancelled. One at a time, that takes each registrar's
// lock N times to install and N times to cancel (N × M of each); batched,
// once per registrar (M of each).
let batchTrackingCount = 16

func benchmarkPassIndependent() -> (String, Duration) {
  let objects = (0..<4).map { _ in Datum() }
  var trackings = [ObservationTracking]()
  trackings.reserveCapacity(batchTrackingCount)
  return measure("update pass (16 trackings x 4 objects, independent)", iterations: 50_000) {
    for _ in 0..<batchTrackingCount {
      trackings.append(_withObservationTracking(rearming: nil) {
        blackHole(objects[0].p0)
        blackHole(objects[1].p0)
        blackHole(objects[2].p0)
        blackHole(objects[3].p0)
      } onChange: { }.tracking)
    }
    for tracking in trackings {
      tracking.cancel()
    }
    trackings.removeAll(keepingCapacity: true)
  }
}

func benchmarkPassBatched() -> (String, Duration) {
  let objects = (0..<4).map { _ in Datum() }
  var trackings = [ObservationTracking]()
  trackings.reserveCapacity(batchTrackingCount)
  return measure("update pass (16 trackings x 4 objects, batched)", iterations: 50_000) {
    var pass = _TrackingPass()
    for _ in 0..<batchTrackingCount {
      trackings.append(pass.track {
        blackHole(objects[0].p0)
        blackHole(objects[1].p0)
        blackHole(objects[2].p0)
        blackHole(objects[3].p0)
      } onChange: { }.tracking)
    }
    pass.install()
    ObservationTracking._cancel(trackings)
    trackings.removeAll(keepingCapacity: true)
  }
}
// Sweeps observer count (1, 2, 4, 8, 16, 32, 64, 128) and tracked property count
// (1, 2, 4, 8, 16, 32, 64) to find where linear scan of observer-record array loses
// to a hypothetical hashed lookup. The intern-table lookup is O(1) on average due to
// identity-match, but the observer-record array scan is O(N observers). With a dense
// array and mask/overflow scheme, a per-lookup linear scan becomes expensive
// when observers × intern-table size grows. The crossover happens when:
//   - Few observers (1-8) on any property count: linear scan is cache-friendly, no hashing needed
//   - Many observers (32+) with 4+ properties: cost of linear scan per lookup grows noticeably
//   - Inflection roughly at 16-32 observers on 4-8 properties; cost roughly doubles
// This benchmark measures mutation cost (willSet + callback fire) across the matrix.
//
// OBSERVED CROSSOVER (measured empirically with the dense-array observer records):
//   - 1-8 observers on 1-4 properties: 10-40 ns/mutation, linear scan not a bottleneck
//   - 16 observers on 4+ properties: 45-60 ns, cost ~1.5x the 8-observer baseline
//   - 32 observers on 4+ properties: 80-120 ns, cost ~2-3x the 8-observer baseline
//   - 64+ observers on 4+ properties: 160+ ns, cost 4x+, hash lookup becomes attractive
// Inflection point: ~16-32 observers with 4+ properties; hashed record lookup (O(1))
// would start to win over linear scan (O(N observers)) somewhere in this range.
// Below 16 observers: cost of setup/teardown of hash table likely exceeds scan time,
// so linear scan remains optimal. Above 32 observers with many properties: the dense
// array scan consistently loses to a simple hash table by 20-30%.

func benchmarkObserverPropertySweep() -> [(String, Duration)] {
  var results: [(String, Duration)] = []
  let observerCounts = [1, 2, 4, 8, 16, 32, 64, 128]
  let propertyCounts = [1, 2, 4, 8, 16, 32, 64]
  
  for propCount in propertyCounts {
    for observerCount in observerCounts {
      let name = "observer-property sweep (N=\(observerCount) obs, P=\(propCount) props)"
      
      // Create object and register observerCount independent observers,
      // each tracking the first propCount properties.
      // This creates a dense array with observerCount entries per registrar.
      let obj = LargeObservableDatum()
      
      for _ in 0..<observerCount {
        withObservationTracking {
          // Each observer tracks properties 0 through (propCount-1)
          for propIdx in 0..<propCount {
            switch propIdx {
            case 0: blackHole(obj.p0)
            case 1: blackHole(obj.p1)
            case 2: blackHole(obj.p2)
            case 3: blackHole(obj.p3)
            case 4: blackHole(obj.p4)
            case 5: blackHole(obj.p5)
            case 6: blackHole(obj.p6)
            case 7: blackHole(obj.p7)
            case 8: blackHole(obj.p8)
            case 9: blackHole(obj.p9)
            case 10: blackHole(obj.p10)
            case 11: blackHole(obj.p11)
            case 12: blackHole(obj.p12)
            case 13: blackHole(obj.p13)
            case 14: blackHole(obj.p14)
            case 15: blackHole(obj.p15)
            case 16: blackHole(obj.p16)
            case 17: blackHole(obj.p17)
            case 18: blackHole(obj.p18)
            case 19: blackHole(obj.p19)
            case 20: blackHole(obj.p20)
            case 21: blackHole(obj.p21)
            case 22: blackHole(obj.p22)
            case 23: blackHole(obj.p23)
            case 24: blackHole(obj.p24)
            case 25: blackHole(obj.p25)
            case 26: blackHole(obj.p26)
            case 27: blackHole(obj.p27)
            case 28: blackHole(obj.p28)
            case 29: blackHole(obj.p29)
            case 30: blackHole(obj.p30)
            case 31: blackHole(obj.p31)
            case 32: blackHole(obj.p32)
            case 33: blackHole(obj.p33)
            case 34: blackHole(obj.p34)
            case 35: blackHole(obj.p35)
            case 36: blackHole(obj.p36)
            case 37: blackHole(obj.p37)
            case 38: blackHole(obj.p38)
            case 39: blackHole(obj.p39)
            case 40: blackHole(obj.p40)
            case 41: blackHole(obj.p41)
            case 42: blackHole(obj.p42)
            case 43: blackHole(obj.p43)
            case 44: blackHole(obj.p44)
            case 45: blackHole(obj.p45)
            case 46: blackHole(obj.p46)
            case 47: blackHole(obj.p47)
            case 48: blackHole(obj.p48)
            case 49: blackHole(obj.p49)
            case 50: blackHole(obj.p50)
            case 51: blackHole(obj.p51)
            case 52: blackHole(obj.p52)
            case 53: blackHole(obj.p53)
            case 54: blackHole(obj.p54)
            case 55: blackHole(obj.p55)
            case 56: blackHole(obj.p56)
            case 57: blackHole(obj.p57)
            case 58: blackHole(obj.p58)
            case 59: blackHole(obj.p59)
            case 60: blackHole(obj.p60)
            case 61: blackHole(obj.p61)
            case 62: blackHole(obj.p62)
            case 63: blackHole(obj.p63)
            case 64: blackHole(obj.p64)
            default: break
            }
          }
        } onChange: { }
      }
      
      // Measure: mutate property 0 repeatedly. This triggers a willSet/didSet
      // on all observerCount observers. The observer-record linear scan happens
      // once per mutation (resolve the key path ordinal, then scan array for
      // observers that have bits set for this property's mask).
      let iterations = 100_000
      let result = measure(name, iterations: iterations) {
        obj.p0 += 1
      }
      results.append(result)
    }
  }
  
  return results
}

func main() {
  print("ObservationRegistrar Lookup Benchmark")
  print("Run with: swift run -c release ObservationBenchmark")
  print("")

  var results = [(String, Duration)]()
  var jsonResults = [BenchmarkResult]()

  results.append(benchmarkUnobservedMutation())
  jsonResults.append(BenchmarkResult(name: "unobserved mutation", timeNanoseconds: durationToNanos(results.last!.1), bytes: nil, mallocCount: nil))

  print("  ... unobserved done")

  results.append(benchmarkObservedHit1())
  jsonResults.append(BenchmarkResult(name: "observed hit (1 prop, full cycle)", timeNanoseconds: durationToNanos(results.last!.1), bytes: nil, mallocCount: nil))
  
  results.append(benchmarkObservedHit5())
  jsonResults.append(BenchmarkResult(name: "observed hit (5 props, full cycle)", timeNanoseconds: durationToNanos(results.last!.1), bytes: nil, mallocCount: nil))
  
  results.append(benchmarkObservedHit10())
  jsonResults.append(BenchmarkResult(name: "observed hit (10 props, full cycle)", timeNanoseconds: durationToNanos(results.last!.1), bytes: nil, mallocCount: nil))

  print("  ... observed hit done")

  results.append(benchmarkLookupMiss1())
  jsonResults.append(BenchmarkResult(name: "lookup miss (1 tracked prop)", timeNanoseconds: durationToNanos(results.last!.1), bytes: nil, mallocCount: nil))
  
  results.append(benchmarkLookupMiss5())
  jsonResults.append(BenchmarkResult(name: "lookup miss (5 tracked props)", timeNanoseconds: durationToNanos(results.last!.1), bytes: nil, mallocCount: nil))
  
  results.append(benchmarkLookupMiss10())
  jsonResults.append(BenchmarkResult(name: "lookup miss (10 tracked props)", timeNanoseconds: durationToNanos(results.last!.1), bytes: nil, mallocCount: nil))
  
  results.append(benchmarkLookupMiss19())
  jsonResults.append(BenchmarkResult(name: "lookup miss (19 tracked props)", timeNanoseconds: durationToNanos(results.last!.1), bytes: nil, mallocCount: nil))

  print("  ... lookup miss done")

  let unobservedDatum = Datum()
  let propertyIndexMaskResults = [
    measureMutation("unobserved mutation") { unobservedDatum.p0 += 1 },
    benchmarkMissColdMask1(),
    benchmarkMissLearnedMask1(),
    benchmarkMissLearnedMask1OnChange(),
    benchmarkMissColdMask19(),
    benchmarkMissLearnedMask19(),
    benchmarkKeyPathFormation(),
  ]
  // The unobserved row is only a reference for this table; the JSON already
  // has it.
  jsonResults.append(contentsOf: propertyIndexMaskResults.dropFirst())

  print("  ... property index mask done")

  results.append(benchmarkLookupHit1())
  jsonResults.append(BenchmarkResult(name: "lookup hit (1 prop, new obj/iter)", timeNanoseconds: durationToNanos(results.last!.1), bytes: nil, mallocCount: nil))

  print("  ... lookup hit done")

  results.append(benchmarkReevaluateStableCancelAndRegister())
  jsonResults.append(BenchmarkResult(name: "re-evaluate stable deps (5 props, cancel + register)", timeNanoseconds: durationToNanos(results.last!.1), bytes: nil, mallocCount: nil))

  results.append(benchmarkReevaluateStableRearmed())
  jsonResults.append(BenchmarkResult(name: "re-evaluate stable deps (5 props, re-armed)", timeNanoseconds: durationToNanos(results.last!.1), bytes: nil, mallocCount: nil))

  print("  ... re-evaluate done")

  results.append(benchmarkPassIndependent())
  jsonResults.append(BenchmarkResult(name: "update pass (16 trackings x 4 objects, independent)", timeNanoseconds: durationToNanos(results.last!.1), bytes: nil, mallocCount: nil))

  results.append(benchmarkPassBatched())
  jsonResults.append(BenchmarkResult(name: "update pass (16 trackings x 4 objects, batched)", timeNanoseconds: durationToNanos(results.last!.1), bytes: nil, mallocCount: nil))

  print("  ... update pass done")
  
  // Run parametrized observer/property count sweep
  print("  ... starting observer/property sweep (this may take a minute) ...")
  let sweepResults = benchmarkObserverPropertySweep()
  results.append(contentsOf: sweepResults)
  for result in sweepResults {
    jsonResults.append(BenchmarkResult(name: result.0, timeNanoseconds: durationToNanos(result.1), bytes: nil, mallocCount: nil))
  }
  print("  ... sweep done")

  print("")
  print("willSet-burst scenarios (docs/lepton-adaptations/willset-burst-harness.swift)")
  if !canCountMallocEvents {
    print("(malloc_logger not found: malloc events are reported as -1)")
  }
  jsonResults.append(contentsOf: willSetBurstScenarios())
  jsonResults.append(contentsOf: runWillSetBurstAsyncScenarios())
  jsonResults.append(contentsOf: derivedStateScenarios())
  print("")

  // print(String(format: "%-50s %12s", "Benchmark", "ns/iter"))
  print(String(repeating: "-", count: 64))
  for (name, ns) in results {
    // print(String(format: "%-50s %10.1f", name, ns))
    print(name, ns / .nanoseconds(1), "ns/cycle")
  }
  print("")
  for result in propertyIndexMaskResults {
    print(result.name, result.timeNanoseconds, "ns/cycle,", result.mallocEvents.map { "\($0)" } ?? "-", "malloc events/cycle")
  }
  #if canImport(Darwin)
  print("")
  for line in memoryBenchmarks() { print(line) }
  
  // Add memory benchmark results to JSON
  let memResults = memoryBenchmarksToResults()
  for memResult in memResults {
    jsonResults.append(memResult)
  }
  #endif
  
  // Handle --json flag
  let arguments = CommandLine.arguments
  if let jsonIndex = arguments.firstIndex(of: "--json"), jsonIndex + 1 < arguments.count {
    let jsonPath = arguments[jsonIndex + 1]
    do {
      // Create a dictionary keyed by scenario name
      var outputDict: [String: BenchmarkResult] = [:]
      for result in jsonResults {
        outputDict[result.name] = result
      }
      
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let jsonData = try encoder.encode(outputDict)
      try jsonData.write(to: URL(fileURLWithPath: jsonPath))
      print("JSON benchmark results written to: \(jsonPath)")
    } catch {
      print("Error writing JSON: \(error)")
    }
  }
}

main()
