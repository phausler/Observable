import Testing
import Observation

// MARK: - Tests for Observations async sequence

// NOTE: Area (c) - Observations async sequence tests
// According to the porting notes, there are currently NO existing assertions
// for the Observations async sequence in Sources/ObservationClient/main.swift
// or Extracted Tests/*.swift. These are net-new tests that need to be written
// from scratch against Sources/Observation/Observations.swift, covering:
// - transactional coalescing
// - two consecutive consumers
// - cancellation
// - untilFinished
// - error termination
//
// This file is a placeholder for future work on these tests.
// The existing test suite in ObservationClient does not currently exercise
// the Observations async sequence, so there are no assertions to port.

@Test func observationsAsyncSequenceTestsPlaceholder() {
  // TODO: Implement tests for Observations async sequence
  // - testObservationsCoalescesTransactionally
  // - testObservationsTwoConsecutiveConsumers
  // - testObservationsCancellation
  // - testObservationsUntilFinished
  // - testObservationsErrorTermination
}

@MainActor @Observable fileprivate final class Model {
  var value = 0
}

@MainActor
@Test func observationAsyncSequenceTestDuplicates() async throws {


  let model = Model()
  let values = Observations { model.value }   // one instance, iterated twice

  // First iteration: receives the initial value, then is cancelled while waiting for a change.
  let first = Task { for await _ in values {} }
  try await Task.sleep(for: .milliseconds(100))
  first.cancel()
  await first.value

  // Second iteration of the same instance.
  var received: [Int] = []
  let second = Task {
    for await value in values {
      received.append(value)
    }
  }
  try await Task.sleep(for: .milliseconds(100))
  for i in 1...3 {
    model.value = i
    try await Task.sleep(for: .milliseconds(100))
  }
  second.cancel()
  await second.value

  #expect(received == [0, 1, 2, 3])
}
