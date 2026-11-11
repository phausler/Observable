import Testing
import Observation

// MARK: - Tests

@Test func testContinuousObservationFiresOnEachMutationUntilCancelled() async {
  let changed = CapturedState(state: 0)
  let test: MiddleNamePerson = MiddleNamePerson()
  let token = withContinuousObservation(options: .didSet) { _ in
    _blackHole(test.firstName)
    changed.state += 1
  }
  
  // the sleeps here are intended to be a simulation of returning to the main run loop
  try! await Task.sleep(for: .seconds(0.1))
  #expect(changed.state == 1)
  test.firstName = "c"
  try! await Task.sleep(for: .seconds(0.1))
  #expect(changed.state == 2)
  test.firstName = "d"
  try! await Task.sleep(for: .seconds(0.1))
  #expect(changed.state == 3)
  token.cancel()
  try! await Task.sleep(for: .seconds(0.1)) // ensure a small grace w.r.t. cancellation
  test.firstName = "e"
  try! await Task.sleep(for: .seconds(0.1))
  #expect(changed.state == 3)
}
