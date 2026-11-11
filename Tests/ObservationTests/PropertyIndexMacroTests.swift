import Testing
import Observation

// MARK: - Fixture

// Its properties' macro-generated accessors call the property-index-tagged entry
// points; the hand-written methods call the key-path-only ones, as code
// written against the v1 macro would.
@Observable
final class PropertyIndexMacroModel: @unchecked Sendable {
  var first = 0
  var second = 0
  var third = 0

  func readSecondByKeyPath() -> Int {
    _$observationRegistrar.access(self, keyPath: \.second)
    return _second
  }

  func writeSecondByKeyPath(_ newValue: Int) {
    _$observationRegistrar.withMutation(of: self, keyPath: \.second) {
      _second = newValue
    }
  }
}

// `a` and `c` share `a`'s property index and key path; `b` has its own.
@Observable
final class GroupedPropertyIndexModel: @unchecked Sendable {
  @ObservationTracked(group: 1) var a = 0
  var b = 0
  @ObservationTracked(group: 1) var c = 0
}

// Every property shares property index 0 and `x`'s key path.
@Observable(resolution: .object)
final class ObjectResolutionModel: @unchecked Sendable {
  var x = 0
  var y = 0
}

// MARK: - Tests

// Tracking through a key-path-only call is notified by a property-index-tagged mutation
// of the same property, and the other way around.
@available(SwiftStdlib 6.4, *)
@Test func testPropertyIndexTaggedAndKeyPathOnlyCallSitesInteroperate() {
  let log = CapturedState(state: [String]())
  let model = PropertyIndexMacroModel()

  withObservationTracking {
    _blackHole(model.readSecondByKeyPath())
  } onChange: {
    log.state.append("key path tracked")
  }
  model.first = 1
  model.third = 1
  model.second = 1

  withObservationTracking {
    _blackHole(model.second)
  } onChange: {
    log.state.append("property index tracked")
  }
  model.first = 2
  model.writeSecondByKeyPath(2)

  withObservationTracking {
    _blackHole(model.first)
    _blackHole(model.third)
  } onChange: {
    log.state.append("first and third tracked")
  }
  model.writeSecondByKeyPath(3)
  model.second = 4
  model.third = 2

  #expect(log.state == ["key path tracked", "property index tracked", "first and third tracked"])
}

// `Entity.age`, `Person.firstName`, and `MiddleNamePerson.middleName` each
// have property index 0 in their own class's registrar; a mutation of one notifies only
// the observers of that one.
@available(SwiftStdlib 6.4, *)
@Test func testSubclassPropertyIndicesAreIndependentPerRegistrar() {
  let log = CapturedState(state: [String]())
  let person = MiddleNamePerson()

  withObservationTracking {
    _blackHole(person.age)
  } onChange: {
    log.state.append("age")
  }
  withObservationTracking {
    _blackHole(person.firstName)
  } onChange: {
    log.state.append("firstName")
  }
  withObservationTracking {
    _blackHole(person.middleName)
  } onChange: {
    log.state.append("middleName")
  }

  person.middleName = "M"
  person.age = 1
  person.firstName = "F"
  person.lastName = "L"

  #expect(log.state == ["middleName", "age", "firstName"])
}

// Properties sharing a property index notify each other's observers, by design; a
// property outside the group does not.
@available(SwiftStdlib 6.4, *)
@Test func testSharedPropertyIndicesNotifyTheWholeGroup() {
  let log = CapturedState(state: [String]())
  let grouped = GroupedPropertyIndexModel()
  let object = ObjectResolutionModel()

  withObservationTracking {
    _blackHole(grouped.a)
  } onChange: {
    log.state.append("a")
  }
  grouped.b = 1
  grouped.c = 1

  withObservationTracking {
    _blackHole(grouped.b)
  } onChange: {
    log.state.append("b")
  }
  grouped.a = 2
  grouped.c = 2
  grouped.b = 2

  withObservationTracking {
    _blackHole(object.x)
  } onChange: {
    log.state.append("x")
  }
  object.y = 1

  #expect(log.state == ["a", "b", "x"])
  #expect(grouped.a == 2 && grouped.b == 2 && grouped.c == 2 && object.y == 1)
}
