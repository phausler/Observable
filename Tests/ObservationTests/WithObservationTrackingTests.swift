import Testing
import Observation

// MARK: - Tests

@Test func testTrackingFiresOnceThenCancels() {
  let changed = CapturedState(state: false)
  
  let test = MiddleNamePerson()
  withObservationTracking {
    _blackHole(test.firstName)
  } onChange: {
    changed.state = true
  }
  
  test.firstName = "c"
  #expect(changed.state == true)
  changed.state = false
  test.firstName = "c"
  #expect(changed.state == false)
}

@Test func testTrackingIgnoresUnreadProperty() {
  let changed = CapturedState(state: false)
  
  let test = MiddleNamePerson()
  withObservationTracking {
    _blackHole(test.lastName)
  } onChange: {
    changed.state = true
  }
  
  test.firstName = "c"
  #expect(changed.state == false)
}

@Test func testTrackingComputedPropertyFiresOnDependencyChange() {
  let changed = CapturedState(state: false)
  
  let test = MiddleNamePerson()
  withObservationTracking {
    _blackHole(test.fullName)
  } onChange: {
    changed.state = true
  }
  
  test.middleName = "c"
  #expect(changed.state == true)
  changed.state = false
  test.middleName = "c"
  #expect(changed.state == false)
}

@Test func testTrackingAcrossObjectGraphFollowsActualAccess() {
  let changed = CapturedState(state: false)
  
  let test = MiddleNamePerson()
  let friend = MiddleNamePerson()
  test.friends.append(friend)
  withObservationTracking {
    _blackHole(test.friends.first?.fullName)
  } onChange: {
    changed.state = true
  }

  test.middleName = "c"
  #expect(changed.state == false)
  friend.middleName = "c"
  #expect(changed.state == true)
}

@Test func testNestedWithObservationTrackingBothFireThenInnerCancels() {
  let changedOuter = CapturedState(state: false)
  let changedInner = CapturedState(state: false)
  
  let test = MiddleNamePerson()
  withObservationTracking {
    withObservationTracking {
      _blackHole(test.firstName)
    } onChange: {
      changedInner.state = true
    }
  } onChange: {
    changedOuter.state = true
  }
  
  test.firstName = "c"
  #expect(changedInner.state == true)
  #expect(changedOuter.state == true)
  changedOuter.state = false
  test.firstName = "c"
  #expect(changedOuter.state == false)
}

@Test @MainActor func testTrackingMainActorIsolatedProperty() {
  let changed = CapturedState(state: false)
  
  let test = IsolatedClass()
  withObservationTracking {
    _blackHole(test.test)
  } onChange: {
    changed.state = true
  }
  
  test.test = "c"
  #expect(changed.state == true)
  changed.state = false
  test.test = "c"
  #expect(changed.state == false)
}

// The nonisolated property stands for the property index the two share, so either
// write notifies a tracking of the isolated one.
@Test @MainActor func testSharedPropertyIndexWithMixedIsolationNotifies() {
  let changed = CapturedState(state: 0)

  let test = MixedIsolationObjectClass()
  withObservationTracking {
    _blackHole(test.isolated)
  } onChange: {
    changed.state += 1
  }
  test.plain = 1
  #expect(changed.state == 1)

  withObservationTracking {
    _blackHole(test.plain)
  } onChange: {
    changed.state += 1
  }
  test.isolated = "c"
  #expect(changed.state == 2)
}

@Test @MainActor func testSharedPropertyIndexWithSameIsolationNotifiesOnlyTheGroup() {
  let changed = CapturedState(state: 0)

  let test = SameIsolationGroupClass()
  withObservationTracking {
    _blackHole(test.second)
  } onChange: {
    changed.state += 1
  }
  test.other = 1
  #expect(changed.state == 0)
  test.first = "c"
  #expect(changed.state == 1)
}

@Test func testRecursiveNestedTrackingInnerMutationThenOuter() {
  let obj = RecursiveOuter()
  obj.recursiveTrackingCalls()
  obj.inner.value = "test"
  #expect(obj.innerEventCount == 1)
  #expect(obj.outerEventCount == 1)
  obj.recursiveTrackingCalls()
  obj.value = "test"
  #expect(obj.innerEventCount == 1)
  #expect(obj.outerEventCount == 2)
}

@Test func testRecursiveNestedTrackingOuterMutationThenInner() {
  let obj = RecursiveOuter()
  obj.recursiveTrackingCalls()
  obj.value = "test"
  #expect(obj.innerEventCount == 0)
  #expect(obj.outerEventCount == 1)
  obj.recursiveTrackingCalls()
  obj.inner.value = "test"
  #expect(obj.innerEventCount == 2)
  #expect(obj.outerEventCount == 2)
}

@Test func testTrackingOptionsWillSetFires() {
  let changed = CapturedState(state: false)

  let test = MiddleNamePerson()
  withObservationTracking(options: .willSet) {
    _blackHole(test.firstName)
  } onChange: { _ in
    changed.state = true
  }

  test.firstName = "c"
  #expect(changed.state == true)
  changed.state = false
  test.firstName = "c"
  #expect(changed.state == false)
}

@Test func testTrackingOptionsDidSetFires() {
  let changed = CapturedState(state: false)

  let test = MiddleNamePerson()
  withObservationTracking(options: .didSet) {
    _blackHole(test.firstName)
  } onChange: { _ in
    changed.state = true
  }

  test.firstName = "c"
  #expect(changed.state == true)
  changed.state = false
  test.firstName = "c"
  #expect(changed.state == false)
}

@Test func testTrackingOptionsWillSetAndDidSetFireTwice() {
  let changed = CapturedState(state: 0)

  let test = MiddleNamePerson()
  withObservationTracking(options: [.willSet, .didSet]) {
    _blackHole(test.firstName)
  } onChange: { _ in
    changed.state += 1
  }

  test.firstName = "c"
  #expect(changed.state == 2)
  changed.state = 0
  test.firstName = "c"
  #expect(changed.state == 0)
}

@Test func testTrackingOptionsDeinitFiresOnRelease() {
  let changed = CapturedState(state: false)

  var test: MiddleNamePerson? = MiddleNamePerson()
  withObservationTracking(options: .deinit) {
    _blackHole(test?.firstName)
  } onChange: { _ in
    changed.state = true
  }

  test?.firstName = "c"
  #expect(changed.state == false)
  changed.state = false
  test?.firstName = "c"
  #expect(changed.state == false)
  test = nil
  #expect(changed.state == true)
}

@Test func testRepeatedNonConsecutiveAccessDedup() {
  // Test for SmallArray.appendCompacting dedup behavior (WS3 step 23).
  // When the same property is read multiple times non-consecutively in a
  // tracking body (e.g. read propA, propB, propA, propB, repeated), the
  // raw access list grows with each read. appendCompacting should deduplicate
  // once the array grows significantly (beyond 16-entry threshold), ensuring:
  // 1. Correctness: onChange fires exactly once per mutation (no double-fire, no miss)
  // 2. Robustness: behavior remains correct even after many repeated accesses
  
  let changeCount = CapturedState(state: 0)
  
  let test = MiddleNamePerson()
  
  // Install tracking that reads firstName and lastName alternately,
  // 24 times total (exceeds the 16-entry appendCompacting threshold).
  // This creates a repeated/non-consecutive pattern that exercises the
  // dedup logic.
  withObservationTracking {
    for _ in 0..<12 {
      _blackHole(test.firstName)
      _blackHole(test.lastName)
    }
  } onChange: {
    changeCount.state += 1
  }
  
  // Mutate firstName: onChange should fire exactly once. Because both
  // firstName and lastName were tracked, either mutation will fire onChange.
  test.firstName = "updated"
  #expect(changeCount.state == 1)
  
  // Mutate lastName: onChange should NOT fire because the tracking was
  // already cancelled after the first onChange (withObservationTracking
  // has single-fire semantics).
  test.lastName = "updated again"
  #expect(changeCount.state == 1)
}
