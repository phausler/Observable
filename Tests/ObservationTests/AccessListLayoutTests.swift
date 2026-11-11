import Testing
@_spi(SwiftUI) import Observation

// SwiftUI (Core/ObservationUtils.swift) depends on `_AccessList`'s layout:
// it collects an access list by installing a pointer to an `_AccessList?` in
// the observation thread-local itself, and merges two by reinterpreting them
// as `[ObjectIdentifier: (AnyObject, Set<AnyKeyPath>)]`. These tests do the
// same, so a layout change fails here instead of crashing SwiftUI.

@_silgen_name("_swift_observation_tls_get")
private func tlsGet() -> UnsafeMutableRawPointer?

@_silgen_name("_swift_observation_tls_set")
private func tlsSet(_ value: UnsafeMutableRawPointer?)

// SwiftUI's mirror of an access list entry.
private struct MirroredEntry: @unchecked Sendable {
  let context: AnyObject
  var properties: Set<AnyKeyPath>
}

// As `ObservationCenter._withObservation(do:)`.
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

// As SwiftUI's `ObservationTracking._AccessList.merge(_:)`.
private func merge(
  _ list: inout ObservationTracking._AccessList,
  _ other: ObservationTracking._AccessList
) {
  withUnsafeMutableBytes(of: &list) { opaque in
    let selfPtr = opaque.baseAddress!.assumingMemoryBound(
      to: [ObjectIdentifier: MirroredEntry].self)
    var otherLocal = other
    withUnsafeBytes(of: &otherLocal) { otherOpaque in
      let otherPtr = otherOpaque.baseAddress!.assumingMemoryBound(
        to: [ObjectIdentifier: MirroredEntry].self)
      selfPtr.pointee.merge(otherPtr.pointee) { existing, entry in
        MirroredEntry(
          context: existing.context,
          properties: existing.properties.union(entry.properties))
      }
    }
  }
}

private func mirrored(
  _ list: ObservationTracking._AccessList
) -> [ObjectIdentifier: MirroredEntry] {
  var local = list
  return withUnsafeBytes(of: &local) {
    $0.baseAddress!.assumingMemoryBound(
      to: [ObjectIdentifier: MirroredEntry].self).pointee
  }
}

@Test func testAccessListHasTheLayoutSwiftUIAssumes() {
  #expect(MemoryLayout<ObservationTracking._AccessList>.size == 8)
  #expect(MemoryLayout<ObservationTracking._AccessList?>.size == 8)
}

@Test func testAccessListCollectedThroughTheThreadLocalReadsAsSwiftUIsMirror() {
  let first = Person()
  let second = Person()
  let (_, list) = collect {
    _blackHole(first.firstName)
    _blackHole(first.lastName)
    _blackHole(second.firstName)
  }
  let entries = mirrored(try! #require(list))
  #expect(entries.count == 2)
  #expect(entries.values.map(\.properties.count).sorted() == [1, 2])
}

@Test func testAccessListsMergedAsSwiftUIDoesInstallAndNotify() {
  let first = Person()
  let second = Person()
  let (_, firstList) = collect { _blackHole(first.firstName) }
  let (_, secondList) = collect {
    _blackHole(first.lastName)
    _blackHole(second.firstName)
  }
  var list = try! #require(firstList)
  merge(&list, try! #require(secondList))

  let entries = mirrored(list)
  #expect(entries.count == 2)
  #expect(entries.values.map(\.properties.count).sorted() == [1, 2])

  // As `ObservationCenter.invalidate(_:with:onChangeIn:)`.
  let fired = CapturedState(state: 0)
  let tracking = ObservationTracking(list)
  ObservationTracking._installTracking(tracking, willSet: { _ in
    fired.state += 1
  })
  second.firstName = "changed"
  #expect(fired.state == 1)
  first.lastName = "changed"
  #expect(fired.state == 2)
  tracking.cancel()
  first.firstName = "changed"
  #expect(fired.state == 2)
}

// This module's own collections tag the thread-local; SwiftUI's do not.
// Accesses inside a `withObservationTracking` nested in a SwiftUI
// collection still reach SwiftUI, in its representation.
@Test func testNestedTrackingReportsIntoSwiftUIsCollection() {
  let outer = Person()
  let inner = Person()
  let (_, list) = collect {
    _blackHole(outer.firstName)
    withObservationTracking {
      _blackHole(inner.lastName)
    } onChange: { }
  }
  let entries = mirrored(try! #require(list))
  #expect(entries.count == 2)
  #expect(entries.values.map(\.properties.count) == [1, 1])
}

// A SwiftUI collection nested in this module's restores the tagged
// thread-local, so the enclosing tracking goes on collecting.
@Test func testSwiftUICollectionNestedInTrackingRestoresIt() {
  let outer = Person()
  let inner = Person()
  let fired = CapturedState(state: 0)
  withObservationTracking {
    _blackHole(outer.firstName)
    let (_, list) = collect { _blackHole(inner.firstName) }
    #expect(list != nil)
    _blackHole(outer.lastName)
  } onChange: {
    fired.state += 1
  }
  inner.firstName = "not observed by the outer tracking"
  #expect(fired.state == 0)
  outer.lastName = "observed after the nested collection"
  #expect(fired.state == 1)
}

// The opt-in SPI: collect, merge, and observe without depending on layout.
@Test func testTrackedAccessListCollectsMergesAndInstalls() {
  let first = Person()
  let second = Person()
  let (_, firstList) = ObservationTracking._collectAccessList {
    _blackHole(first.firstName)
  }
  let (_, secondList) = ObservationTracking._collectAccessList {
    _blackHole(second.lastName)
  }
  var list = try! #require(firstList)
  list.merge(try! #require(secondList))

  let fired = CapturedState(state: 0)
  let tracking = ObservationTracking(list)
  ObservationTracking._installTracking(tracking, willSet: { _ in
    fired.state += 1
  })
  second.lastName = "changed"
  first.firstName = "changed"
  #expect(fired.state == 2)
  tracking.cancel()
  first.firstName = "again"
  #expect(fired.state == 2)
}

@Test func testTrackedAccessListIsNilWithoutAccesses() {
  let (value, list) = ObservationTracking._collectAccessList { 42 }
  #expect(value == 42)
  #expect(list == nil)
}

// As SwiftUI's BoundNavigationPathDetector: a tracking is made from the
// optional list as collected, and installed whether or not there was one.
@Test func testTrackingFromOptionalTrackedAccessList() {
  let person = Person()
  let fired = CapturedState(state: 0)
  let (_, list) = ObservationTracking._collectAccessList {
    _blackHole(person.firstName)
  }
  let tracking = ObservationTracking(list)
  ObservationTracking._installTracking(tracking, willSet: { _ in
    fired.state += 1
  })
  person.firstName = "changed"
  #expect(fired.state == 1)
  tracking.cancel()

  let (_, none) = ObservationTracking._collectAccessList { 0 }
  let empty = ObservationTracking(none)
  ObservationTracking._installTracking(empty, willSet: { _ in
    fired.state += 1
  })
  person.firstName = "again"
  #expect(fired.state == 1)
  empty.cancel()
}

// As SwiftUI's `_withObservation(do:)` behaves today: a nested collection
// is not reported to the enclosing one.
@Test func testTrackedAccessListIsNotReportedToAnEnclosingCollection() {
  let outer = Person()
  let inner = Person()
  let (_, list) = collect {
    _blackHole(outer.firstName)
    let (_, nested) = ObservationTracking._collectAccessList {
      _blackHole(inner.firstName)
    }
    #expect(nested != nil)
  }
  #expect(mirrored(try! #require(list)).count == 1)
}

// SwiftUI's collection entry point is `rethrows`.
private func rethrowingCollect<T>(
  _ work: () throws -> T
) rethrows -> (T, ObservationTracking._TrackedAccessList?) {
  let (result, list) = try ObservationTracking._collectAccessList(work)
  return (result, list)
}

private struct Failure: Error { }

@Test func testTrackedAccessListCollectionRethrows() {
  let person = Person()
  let (_, list) = rethrowingCollect { _blackHole(person.firstName) }
  #expect(list != nil)
  #expect(throws: Failure.self) {
    _ = try rethrowingCollect { () throws -> Int in throw Failure() }
  }
}
