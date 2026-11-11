import Testing
import Observation

// MARK: - Tests

@Test func testOnlyInstantiate() {
  _ = MiddleNamePerson()
  // Just instantiation should not crash
}

@Test func testUnobservedValueChanges() {
  let test = MiddleNamePerson()
  for i in 0..<100 {
    test.firstName = "\(i)"
  }
  // 100 unobserved mutations should run cleanly
}

@Test func testObservableConformanceOverloadResolution() {
  func testConformance<O: Observable>(_ o: O) -> Bool {
    return true
  }
  
  func testConformance<O>(_ o: O) -> Bool {
    return false
  }
  
  let test = Person()
  #expect(testConformance(test) == true)
}

@Test func testAccessAndWithMutationHooksReceiveKeyPath() {
  let accessKeyPath = CapturedState<PartialKeyPath<ImplementsAccessAndMutation>?>(state: nil)
  let mutationKeyPath = CapturedState<PartialKeyPath<ImplementsAccessAndMutation>?>(state: nil)
  let test = ImplementsAccessAndMutation { keyPath in
    accessKeyPath.state = keyPath
  } withMutationCalled: { keyPath in
    mutationKeyPath.state = keyPath
  }
  
  #expect(accessKeyPath.state == nil)
  _blackHole(test.field)
  #expect(accessKeyPath.state == \.field)
  #expect(mutationKeyPath.state == nil)
  accessKeyPath.state = nil
  test.field = 123
  #expect(accessKeyPath.state == nil)
  #expect(mutationKeyPath.state == \.field)
}

@Test func testIgnoredPropertyMutationDoesNotNotify() {
  let changed = CapturedState(state: false)
  
  let test = HasIgnoredProperty()
  withObservationTracking {
    _blackHole(test.ignored)
  } onChange: {
    changed.state = true
  }
  
  test.ignored = 122112
  #expect(changed.state == false)
  changed.state = false
  test.field = 3429
  #expect(changed.state == false)
}

@Test func testNonIgnoredPropertyMutationNotifiesDespiteIgnoredSibling() {
  let changed = CapturedState(state: false)
  
  let test = HasIgnoredProperty()
  withObservationTracking {
    _blackHole(test.ignored)
    _blackHole(test.field)
  } onChange: {
    changed.state = true
  }
  
  test.ignored = 122112
  #expect(changed.state == false)
  changed.state = false
  test.field = 3429
  #expect(changed.state == true)
}

@Test func testCopyOnWriteSemanticsPreserved() {
  let subject = CowTest()
  let startId = subject.container.id
  #expect(subject.container.id == startId)
  subject.container.mutate()
  #expect(subject.container.id == startId)
}

@Test func testWillSetThenDidSetOrderingAndEqualityShortCircuit() {
  // This test verifies that user-written willSet/didSet blocks fire in the correct order
  // with the correct old/new values, and that user-side equality short-circuits
  // (guard oldValue != newValue) suppress redundant didSet firing.
  // Based on: Extracted Tests/ObservableDidSetWillSet.swift
  
  // Clear events from any previous test
  WillSetDidSetModel.events.state.removeAll()
  
  let model = WillSetDidSetModel()
  
  // First transition: initializing -> running
  model.state = .running
  #expect(WillSetDidSetModel.events.state.contains("willSet newValue=running"))
  #expect(WillSetDidSetModel.events.state.contains("didSet oldValue=initializing"))
  
  // Second transition: running -> complete
  model.state = .complete
  #expect(WillSetDidSetModel.events.state.contains("willSet newValue=complete"))
  #expect(WillSetDidSetModel.events.state.contains("didSet oldValue=running"))
  
  // Third "transition" (no change): complete -> complete
  // willSet still fires (it always does), but didSet should NOT fire due to equality short-circuit
  let eventCountBefore = WillSetDidSetModel.events.state.count
  model.state = .complete
  let eventCountAfter = WillSetDidSetModel.events.state.count
  
  // Only willSet should have fired (1 more event), didSet should have been suppressed
  #expect(eventCountAfter == eventCountBefore + 1)
  #expect(WillSetDidSetModel.events.state.last == "willSet newValue=complete")
}
