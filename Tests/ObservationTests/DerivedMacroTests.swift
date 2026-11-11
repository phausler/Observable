import Testing
@_spi(Prototype) import Observation

@available(SwiftStdlib 6.5, *)
@Observable
final class MacroDerivedSignal: @unchecked Sendable {
  var a: Double = 3
  var b: Double = 4

  @ObservationIgnored let counts = CacheCounts()

  @ObservationDerived var length: Double {
    input {
      counts.record("length.input")
      return (a, b)
    }
    update {
      counts.record("length.update")
      return ($0.0 * $0.0 + $0.1 * $0.1).squareRoot()
    }
  }

  @ObservationDerived var isPositive: Bool {
    input {
      counts.record("isPositive.input")
      return a
    }
    update {
      counts.record("isPositive.update")
      return $0 > 0
    }
  }

  // Reads another cache only.
  @ObservationDerived var label: String {
    input {
      counts.record("label.input")
      return isPositive
    }
    update {
      counts.record("label.update")
      return $0 ? "positive" : "negative"
    }
  }
}

// Single-expression blocks, written as in the macro's documentation.
@available(SwiftStdlib 6.5, *)
@Observable
final class HasDerived {
  var a: Float = 0
  var b: Float = 0
  @ObservationDerived
  var rms: Float {
    input {
      (a, b)
    }
    update {
      (($0.0 * $0.0 + $0.1 * $0.1) / 2).squareRoot()
    }
  }
}

// A derived property that is not a direct member of its type (inside `#if`)
// takes the expansion without a registrar or index.
@available(SwiftStdlib 6.5, *)
@Observable
final class ConditionalDerived {
  var a: Int = 1
  #if true
  @ObservationDerived
  var doubled: Int {
    input { a }
    update { $0 * 2 }
  }
  #endif
}

// The first read computes; a clean re-read runs no `update`; writes without
// reads run nothing, and the next read runs one `update` on the latest inputs.
extension DerivedValueSuites {
  @available(SwiftStdlib 6.5, *)
  @Test func testDerivedMacroComputesLazilyAndOnce() {
    let signal = MacroDerivedSignal()
    #expect(signal.length == 5)
    #expect(signal.counts["length.update"] == 1)
    for _ in 0..<100 {
      #expect(signal.length == 5)
    }
    #expect(signal.counts["length.update"] == 1)

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

  // An input rewritten so a cache's result stays equal leaves the caches that
  // read it un-updated.
  @available(SwiftStdlib 6.5, *)
  @Test func testDerivedMacroEqualResultLeavesDependentsUnupdated() {
    let signal = MacroDerivedSignal()
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

  @available(SwiftStdlib 6.5, *)
  @Test func testDerivedMacroSingleExpressionBlocks() {
    let value = HasDerived()
    #expect(value.rms == 0)
    value.a = 3
    value.b = 4
    #expect(value.rms == (12.5 as Float).squareRoot())
  }

  // A tracked read of a `@ObservationDerived` property observes what it depends
  // on.
  @available(SwiftStdlib 6.5, *)
  @Test func testDerivedMacroTrackedReadIsNotified() {
    let signal = MacroDerivedSignal()
    _ = signal.length
    let changes = CapturedState(state: 0)

    withObservationTracking {
      #expect(signal.length == 5)
    } onChange: {
      changes.state += 1
    }
    #expect(signal.counts["length.update"] == 1)

    signal.b = 0
    #expect(changes.state == 1)
    #expect(signal.length == 3)
  }

  @available(SwiftStdlib 6.5, *)
  @Test func testDerivedMacroInsideConditionalCompilation() {
    let value = ConditionalDerived()
    #expect(value.doubled == 2)
    let changes = CapturedState(state: 0)
    withObservationTracking {
      #expect(value.doubled == 2)
    } onChange: {
      changes.state += 1
    }
    value.a = 5
    #expect(changes.state == 1)
    #expect(value.doubled == 10)
  }
}
