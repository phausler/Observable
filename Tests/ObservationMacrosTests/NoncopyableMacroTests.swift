import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

#if canImport(ObservationMacros)
import ObservationMacros

// `@Observable` on a noncopyable struct: no key path can name a property of
// a noncopyable type, so the accessors make only the property index-only calls, in
// every build.
struct NoncopyableMacroTests {
  let macros: [String: MacroSpec] = [
    "Observable": MacroSpec(type: ObservableMacro.self, conformances: ["Observable"]),
    "ObservationTracked": MacroSpec(type: ObservationTrackedMacro.self),
    "ObservationIgnored": MacroSpec(type: ObservationIgnoredMacro.self),
    "ObservationDerived": MacroSpec(type: ObservationDerivedMacro.self),
  ]

  func expectNoMacroFailure(_ spec: TestFailureSpec) {
    Issue.record(
      "\(spec.message)",
      sourceLocation: SourceLocation(
        fileID: spec.location.fileID,
        filePath: spec.location.filePath,
        line: spec.location.line,
        column: spec.location.column
      )
    )
  }

  @Test
  func observableOnNoncopyableStruct() {
    assertMacroExpansion(
      #"""
      @Observable
      struct Counter: ~Copyable {
        var count = 0
        @ObservationIgnored var scratch = 0
      }
      """#,
      expandedSource: #"""
        struct Counter: ~Copyable {
          var count {
              @storageRestrictions(initializes: _count)
              init(initialValue) {
                _count = initialValue
              }
              get {
                access(propertyIndex: 0)
                return _count
              }
              set {
                guard shouldNotifyObservers(_count, newValue) else {
                  _count = newValue
                  return
                }
                withMutation(propertyIndex: 0) {
                  $0._count = newValue
                }
              }
              _modify {
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                  _$observationRegistrar.didSet(propertyIndex: 0)
                }
                yield &_count
              }
          }
          private  var _count  = 0
          var scratch = 0

            private let _$observationRegistrar = Observation.ObservationRegistrar()

            internal nonisolated func access(propertyIndex: Int) {
              _$observationRegistrar.access(propertyIndex: property index)
            }

            internal nonisolated mutating func withMutation<__macro_local_14MutationResultfMu_, __macro_local_7FailurefMu_: Error>(
              propertyIndex: Int,
              _ mutation: (inout Counter) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu_
            ) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu_ {
              _$observationRegistrar.willSet(propertyIndex: property index)
              defer {
                _$observationRegistrar.didSet(propertyIndex: property index)
              }
              return try mutation(&self)
            }

            private nonisolated func shouldNotifyObservers<__macro_local_6MemberfMu_>(_ lhs: __macro_local_6MemberfMu_, _ rhs: __macro_local_6MemberfMu_) -> Bool {
                true
            }

            private nonisolated func shouldNotifyObservers<__macro_local_6MemberfMu0_: Equatable>(_ lhs: __macro_local_6MemberfMu0_, _ rhs: __macro_local_6MemberfMu0_) -> Bool {
                lhs != rhs
            }

            private nonisolated func shouldNotifyObservers<__macro_local_6MemberfMu1_: AnyObject>(_ lhs: __macro_local_6MemberfMu1_, _ rhs: __macro_local_6MemberfMu1_) -> Bool {
                lhs !== rhs
            }

            private nonisolated func shouldNotifyObservers<__macro_local_6MemberfMu2_: Equatable & AnyObject>(_ lhs: __macro_local_6MemberfMu2_, _ rhs: __macro_local_6MemberfMu2_) -> Bool {
                lhs != rhs
            }
        }

        extension Counter: nonisolated Observation.Observable {
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // `~Swift.Copyable` is recognized as well.
  @Test
  func observableOnQualifiedNoncopyableStruct() {
    assertMacroExpansion(
      #"""
      @Observable
      struct Empty: ~Swift.Copyable {
      }
      """#,
      expandedSource: #"""
        struct Empty: ~Swift.Copyable {

            private let _$observationRegistrar = Observation.ObservationRegistrar()

            internal nonisolated func access(propertyIndex: Int) {
              _$observationRegistrar.access(propertyIndex: property index)
            }

            internal nonisolated mutating func withMutation<__macro_local_14MutationResultfMu_, __macro_local_7FailurefMu_: Error>(
              propertyIndex: Int,
              _ mutation: (inout Empty) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu_
            ) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu_ {
              _$observationRegistrar.willSet(propertyIndex: property index)
              defer {
                _$observationRegistrar.didSet(propertyIndex: property index)
              }
              return try mutation(&self)
            }

            private nonisolated func shouldNotifyObservers<__macro_local_6MemberfMu_>(_ lhs: __macro_local_6MemberfMu_, _ rhs: __macro_local_6MemberfMu_) -> Bool {
                true
            }

            private nonisolated func shouldNotifyObservers<__macro_local_6MemberfMu0_: Equatable>(_ lhs: __macro_local_6MemberfMu0_, _ rhs: __macro_local_6MemberfMu0_) -> Bool {
                lhs != rhs
            }

            private nonisolated func shouldNotifyObservers<__macro_local_6MemberfMu1_: AnyObject>(_ lhs: __macro_local_6MemberfMu1_, _ rhs: __macro_local_6MemberfMu1_) -> Bool {
                lhs !== rhs
            }

            private nonisolated func shouldNotifyObservers<__macro_local_6MemberfMu2_: Equatable & AnyObject>(_ lhs: __macro_local_6MemberfMu2_, _ rhs: __macro_local_6MemberfMu2_) -> Bool {
                lhs != rhs
            }
        }

        extension Empty: nonisolated Observation.Observable {
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // A copyable struct is still diagnosed: a copy would share the original's
  // registrar, and notify its observers. Its properties get no accessors.
  @Test
  func observableOnCopyableStructWithPropertiesError() {
    assertMacroExpansion(
      #"""
      @Observable
      struct Point: Equatable {
        var x = 0
      }
      """#,
      expandedSource: #"""
        struct Point: Equatable {
          var x = 0
        }

        extension Point: nonisolated Observation.Observable {
        }
        """#,
      diagnostics: [
        DiagnosticSpec(message: "'@Observable' cannot be applied to struct type 'Point'", line: 1, column: 1)
      ],
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // A derived property's storage is noncopyable, so a noncopyable struct can
  // hold one.
  @Test
  func derivedInNoncopyableStruct() {
    assertMacroExpansion(
      #"""
      struct Doubler: ~Copyable {
        @ObservationDerived var twice: Int {
          input { a }
          update { $0 * 2 }
        }
      }
      """#,
      expandedSource: #"""
        struct Doubler: ~Copyable {
          var twice: Int {
              return _twice.compute(input: {
                      a
                  }, update: {
                      $0 * 2
                  })
          }

          private let _twice = Observation.ObservationDerivedValue<Int>()
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }
}
#endif
