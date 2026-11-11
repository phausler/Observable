import Observation

// MARK: - Shared Fixtures for all tests

@usableFromInline
@inline(never)
func _blackHole<T>(_ value: T) { }

@Observable
class Entity: @unchecked Sendable {
  var age: Int = 0
}

@Observable
class Person: Entity, @unchecked Sendable {
  var firstName = ""
  var lastName = ""
  var friends = [Person]()
  var fullName: String { firstName + " " + lastName }
}

@Observable
class MiddleNamePerson: Person, @unchecked Sendable {
  var middleName = ""
  override var fullName: String { firstName + " " + middleName + " " + lastName }
}

@Observable
class HasIgnoredProperty {
  var field = 3
  @ObservationIgnored var ignored = 4
}

@Observable
class ImplementsAccessAndMutation {
  var field = 3
  let accessCalled: (PartialKeyPath<ImplementsAccessAndMutation>) -> Void
  let withMutationCalled: (PartialKeyPath<ImplementsAccessAndMutation>) -> Void

  init(accessCalled: @escaping (PartialKeyPath<ImplementsAccessAndMutation>) -> Void, withMutationCalled: @escaping (PartialKeyPath<ImplementsAccessAndMutation>) -> Void) {
    self.accessCalled = accessCalled
    self.withMutationCalled = withMutationCalled
  }

  internal func access<Member>(
      keyPath: KeyPath<ImplementsAccessAndMutation , Member>
  ) {
    accessCalled(keyPath)
    _$observationRegistrar.access(self, keyPath: keyPath)
  }

  internal func withMutation<Member, T>(
    keyPath: KeyPath<ImplementsAccessAndMutation , Member>,
    _ mutation: () throws -> T
  ) rethrows -> T {
    withMutationCalled(keyPath)
    return try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
  }
}

struct CowContainer {
  final class Contents { }
  
  var contents = Contents()
  
  mutating func mutate() {
    if !isKnownUniquelyReferenced(&contents) {
      contents = Contents()
    }
  }
  
  var id: ObjectIdentifier {
    ObjectIdentifier(contents)
  }
}

@Observable
final class CowTest {
  var container = CowContainer()
}

@Observable
class IsolatedClass {
  @MainActor var test = "hello"
  
  @MainActor init() { }
}

// Shares one property index between a main-actor-isolated property and a nonisolated
// one, declared first, so the representative's key path must not be the
// isolated one's.
@Observable(resolution: .object)
class MixedIsolationObjectClass {
  @MainActor var isolated = "hello"
  var plain = 0

  @MainActor init() { }
}

// Shares one property index between two properties isolated to the same actor, whose
// key paths each can form.
@Observable
class SameIsolationGroupClass {
  @MainActor @ObservationTracked(group: 1) var first = "hello"
  @MainActor @ObservationTracked(group: 1) var second = 0
  var other = 0

  @MainActor init() { }
}

@Observable
class RecursiveInner {
  var value = "prefix"
}

@Observable
class RecursiveOuter: @unchecked Sendable {
  var inner = RecursiveInner()
  var value = "prefix"
  @ObservationIgnored var innerEventCount = 0
  @ObservationIgnored var outerEventCount = 0

  func recursiveTrackingCalls() {
    withObservationTracking({
      let _ = value
      _ = withObservationTracking({
        inner.value
      }, onChange: {
        self.innerEventCount += 1
      })
    }, onChange: {
      self.outerEventCount += 1
    })
  }
}

class CapturedState<State>: @unchecked Sendable {
  var state: State

  init(state: State) {
    self.state = state
  }
}


// MARK: - Fixture for willSet/didSet ordering test

enum WillSetDidSetState: Equatable, CustomStringConvertible {
  case initializing
  case running
  case complete
  
  var description: String {
    switch self {
    case .initializing: return "initializing"
    case .running: return "running"
    case .complete: return "complete"
    }
  }
}

@Observable
class WillSetDidSetModel {
  // Use a class-level shared list to capture events (thread-safe via sendable wrapper)
  static let events = CapturedState(state: [String]())
  
  var state: WillSetDidSetState = .initializing {
    willSet {
      // willSet fires before the value changes
      Self.events.state.append("willSet newValue=\(newValue)")
    }
    
    didSet {
      // didSet fires after the value changes
      // The equality short-circuit: suppress redundant didSet if value didn't actually change
      guard oldValue != state else { return }
      Self.events.state.append("didSet oldValue=\(oldValue)")
    }
  }
}

// MARK: - Fixture for the registrar's >64-observed-properties overflow path

@Observable
class HundredProperties {
  var p0 = 0; var p1 = 0; var p2 = 0; var p3 = 0; var p4 = 0
  var p5 = 0; var p6 = 0; var p7 = 0; var p8 = 0; var p9 = 0
  var p10 = 0; var p11 = 0; var p12 = 0; var p13 = 0; var p14 = 0
  var p15 = 0; var p16 = 0; var p17 = 0; var p18 = 0; var p19 = 0
  var p20 = 0; var p21 = 0; var p22 = 0; var p23 = 0; var p24 = 0
  var p25 = 0; var p26 = 0; var p27 = 0; var p28 = 0; var p29 = 0
  var p30 = 0; var p31 = 0; var p32 = 0; var p33 = 0; var p34 = 0
  var p35 = 0; var p36 = 0; var p37 = 0; var p38 = 0; var p39 = 0
  var p40 = 0; var p41 = 0; var p42 = 0; var p43 = 0; var p44 = 0
  var p45 = 0; var p46 = 0; var p47 = 0; var p48 = 0; var p49 = 0
  var p50 = 0; var p51 = 0; var p52 = 0; var p53 = 0; var p54 = 0
  var p55 = 0; var p56 = 0; var p57 = 0; var p58 = 0; var p59 = 0
  var p60 = 0; var p61 = 0; var p62 = 0; var p63 = 0; var p64 = 0
  var p65 = 0; var p66 = 0; var p67 = 0; var p68 = 0; var p69 = 0
  var p70 = 0; var p71 = 0; var p72 = 0; var p73 = 0; var p74 = 0
  var p75 = 0; var p76 = 0; var p77 = 0; var p78 = 0; var p79 = 0
  var p80 = 0; var p81 = 0; var p82 = 0; var p83 = 0; var p84 = 0
  var p85 = 0; var p86 = 0; var p87 = 0; var p88 = 0; var p89 = 0
  var p90 = 0; var p91 = 0; var p92 = 0; var p93 = 0; var p94 = 0
  var p95 = 0; var p96 = 0; var p97 = 0; var p98 = 0; var p99 = 0

  nonisolated(unsafe) static let keyPaths: [ReferenceWritableKeyPath<HundredProperties, Int>] = [
    \.p0, \.p1, \.p2, \.p3, \.p4, \.p5, \.p6, \.p7, \.p8, \.p9,
    \.p10, \.p11, \.p12, \.p13, \.p14, \.p15, \.p16, \.p17, \.p18, \.p19,
    \.p20, \.p21, \.p22, \.p23, \.p24, \.p25, \.p26, \.p27, \.p28, \.p29,
    \.p30, \.p31, \.p32, \.p33, \.p34, \.p35, \.p36, \.p37, \.p38, \.p39,
    \.p40, \.p41, \.p42, \.p43, \.p44, \.p45, \.p46, \.p47, \.p48, \.p49,
    \.p50, \.p51, \.p52, \.p53, \.p54, \.p55, \.p56, \.p57, \.p58, \.p59,
    \.p60, \.p61, \.p62, \.p63, \.p64, \.p65, \.p66, \.p67, \.p68, \.p69,
    \.p70, \.p71, \.p72, \.p73, \.p74, \.p75, \.p76, \.p77, \.p78, \.p79,
    \.p80, \.p81, \.p82, \.p83, \.p84, \.p85, \.p86, \.p87, \.p88, \.p89,
    \.p90, \.p91, \.p92, \.p93, \.p94, \.p95, \.p96, \.p97, \.p98, \.p99,
  ]

  // Reads every property, so a tracking around it interns all 100 key paths;
  // at most 64 fit the observer mask, so the rest take the overflow path.
  func readAll() {
    for keyPath in Self.keyPaths {
      _blackHole(self[keyPath: keyPath])
    }
  }
}
