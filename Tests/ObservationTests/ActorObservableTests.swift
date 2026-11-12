import Distributed
import Testing
@_spi(SwiftUI) @_spi(Prototype) import Observation

// `@Observable` on an actor or distributed actor: properties are observed by
// property index, since no key path can name an isolated property.

@available(SwiftStdlib 6.5, *)
@Observable
actor ActorCounter {
  var count = 0
  var label = ""
  @ObservationIgnored var scratch = 0

  func increment() { count += 1 }
  func readCount() -> Int { count }
}

@available(SwiftStdlib 6.5, *)
@Observable
distributed actor DistributedCounter {
  typealias ActorSystem = LocalTestingDistributedActorSystem

  var count = 0

  init(actorSystem: ActorSystem) {
    self.actorSystem = actorSystem
  }

  func increment() { count += 1 }
  distributed func readCount() -> Int { count }
}

@available(SwiftStdlib 6.5, *)
@Test func testActorWillSetAndDidSet() async {
  let kinds = CapturedState(state: [ObservationTracking.Event.Kind]())
  let counter = ActorCounter()
  await counter.withIsolation { counter in
    withObservationTracking(options: [.willSet, .didSet]) {
      _blackHole(counter.count)
    } onChange: { event in
      kinds.state.append(event.kind)
    }
    counter.increment()
  }
  #expect(kinds.state == [.willSet, .didSet])
  #expect(await counter.readCount() == 1)
}

@available(SwiftStdlib 6.5, *)
@Test func testActorUntrackedPropertyDoesNotNotify() async {
  let changes = CapturedState(state: 0)
  let counter = ActorCounter()
  await counter.withIsolation { counter in
    withObservationTracking {
      _blackHole(counter.count)
    } onChange: {
      changes.state += 1
    }
    counter.label = "other"
    counter.scratch = 1
  }
  #expect(changes.state == 0)
}

@available(SwiftStdlib 6.5, *)
@Test func testDistributedActorNotifies() async throws {
  let changes = CapturedState(state: 0)
  let counter = DistributedCounter(actorSystem: LocalTestingDistributedActorSystem())
  await counter.whenLocal { counter in
    withObservationTracking {
      _blackHole(counter.count)
    } onChange: {
      changes.state += 1
    }
    counter.increment()
  }
  #expect(changes.state == 1)
  #expect(try await counter.readCount() == 1)
}

extension Actor {
  fileprivate func withIsolation<T: Sendable>(_ body: @Sendable (isolated Self) -> T) -> T {
    body(self)
  }
}
