// Derived-state scenarios for `ObservationDerivedValue`: lazy recompute,
// repeated diamond, triangular DAG and derived-cache read. Each reports
// time, the number of `update` runs, and malloc events
// (MallocEventCount.swift).

@_spi(Prototype) import Observation

nonisolated(unsafe) var derivedUpdates = 0

@Observable
final class DerivedInput {
  var value = 0
}

// A cache over some inputs and some other caches: `input` sums them, and
// `update` applies `transform` to the sum.
final class DerivedNode {
  private let cache = ObservationDerivedValue<Int>()
  let sources: [DerivedInput]
  let inputs: [DerivedNode]
  let transform: (Int) -> Int

  init(sources: [DerivedInput] = [], inputs: [DerivedNode] = [], transform: @escaping (Int) -> Int = { $0 }) {
    self.sources = sources
    self.inputs = inputs
    self.transform = transform
  }

  var value: Int {
    cache.compute {
      var sum = 0
      for source in sources { sum &+= source.value }
      for input in inputs { sum &+= input.value }
      return sum
    } update: {
      derivedUpdates += 1
      return transform($0)
    }
  }
}

struct DerivedMeasurement {
  var nanos: Int64
  var updates: Int
  var mallocs: Int
}

func measureDerived(_ body: () -> Void) -> DerivedMeasurement {
  derivedUpdates = 0
  let clock = ContinuousClock()
  let start = clock.now
  let (_, mallocs) = countingMallocEvents(body)
  let elapsed = clock.now - start
  return DerivedMeasurement(
    nanos: elapsed.components.seconds * 1_000_000_000 + elapsed.components.attoseconds / 1_000_000_000,
    updates: derivedUpdates, mallocs: mallocs)
}

func derivedRow(_ name: String, _ n: Int, per: Int, _ r: DerivedMeasurement) -> BenchmarkResult {
  print("\(name)\t\(n)\t\(r.updates)\t\(burstRatio(r.nanos, per))\t\(r.mallocs)")
  return BenchmarkResult(
    name: "derived \(name) N=\(n)", timeNanoseconds: UInt64(max(r.nanos, 0)) / UInt64(per),
    bytes: nil, mallocCount: nil,
    mallocEvents: r.mallocs < 0 ? nil : Double(r.mallocs) / Double(per))
}

func derivedStateScenarios() -> [BenchmarkResult] {
  var results = [BenchmarkResult]()
  print("\n## Derived state (ObservationDerivedValue)")
  print("scenario\tN\tupdates\tns/op\tmallocs")

  // lazy-recompute: N inputs, one cache over all of them. A burst of N
  // writes runs no update and advances the epoch once; the read after it
  // runs one. ns/op is per write, then per read.
  for n in [100, 1_000, 10_000] {
    let sources = (0..<n).map { _ in DerivedInput() }
    let node = DerivedNode(sources: sources)
    _ = node.value
    for source in sources { source.value = 1 }   // warm
    _ = node.value
    let burst = measureDerived {
      for (index, source) in sources.enumerated() { source.value = index + 2 }
    }
    results.append(derivedRow("lazy-recompute burst", n, per: n, burst))
    let read = measureDerived { blackHole(node.value) }
    results.append(derivedRow("lazy-recompute read after burst", n, per: 1, read))
  }

  // repeated-diamond: D diamonds in a chain (a fork into two caches and a
  // join of both), under one input. A write and a read of the last join
  // update each of the 3D + 1 caches once; a write that leaves the first
  // cache's result equal updates only that one.
  for depth in [10, 100] {
    let source = DerivedInput()
    func chain(_ first: DerivedNode) -> DerivedNode {
      var last = first
      for _ in 0..<depth {
        let left = DerivedNode(inputs: [last], transform: { $0 &+ 1 })
        let right = DerivedNode(inputs: [last], transform: { $0 &* 2 })
        last = DerivedNode(inputs: [left, right])
      }
      return last
    }
    let changing = chain(DerivedNode(sources: [source]))
    _ = changing.value
    source.value = 1; _ = changing.value   // warm
    let changed = measureDerived {
      source.value += 1
      blackHole(changing.value)
    }
    results.append(derivedRow("repeated-diamond write+read", depth, per: 1, changed))

    let signSource = DerivedInput()
    signSource.value = 1
    let equal = chain(DerivedNode(sources: [signSource], transform: { $0 > 0 ? 1 : 0 }))
    _ = equal.value
    signSource.value = 2; _ = equal.value   // warm
    let unchanged = measureDerived {
      signSource.value += 1
      blackHole(equal.value)
    }
    results.append(derivedRow("repeated-diamond equal-result write+read", depth, per: 1, unchanged))
  }

  // triangular-dag: cache i reads caches 0..<i, and cache 0 an input. A
  // write and a read of the last cache update each of the N caches once;
  // the N(N-1)/2 edges are clean reads after that.
  for n in [10, 50, 100] {
    let source = DerivedInput()
    var nodes = [DerivedNode(sources: [source])]
    for _ in 1..<n {
      nodes.append(DerivedNode(inputs: nodes, transform: { $0 & 0xFFFF }))
    }
    _ = nodes.last!.value
    source.value = 1; _ = nodes.last!.value   // warm
    let r = measureDerived {
      source.value += 1
      blackHole(nodes.last!.value)
    }
    results.append(derivedRow("triangular-dag write+read", n, per: 1, r))
  }

  // derived-cache-read: a clean read, with nothing written since the last.
  do {
    let sources = [DerivedInput(), DerivedInput()]
    let node = DerivedNode(sources: sources)
    _ = node.value
    let reads = 1_000_000
    let r = measureDerived {
      for _ in 0..<reads { blackHole(node.value) }
    }
    results.append(derivedRow("derived-cache-read clean", 2, per: reads, r))
  }

  // The epoch stamps' cost on the write path: an object no cache has read
  // (two relaxed loads), and one a cache has read (the first write of a
  // burst advances the epoch; the rest are two loads again).
  do {
    let writes = 1_000_000
    let unread = DerivedInput()
    let r = measureDerived {
      for index in 0..<writes { unread.value = index }
    }
    results.append(derivedRow("write, object unread by caches", 1, per: writes, r))

    let read = DerivedInput()
    let node = DerivedNode(sources: [read])
    let r2 = measureDerived {
      for index in 0..<writes {
        read.value = index
        if index % 1000 == 0 { blackHole(node.value) }
      }
    }
    results.append(derivedRow("write, object read by a cache every 1000 writes", 1, per: writes, r2))
  }
  return results
}
