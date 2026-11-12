import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

#if canImport(ObservationMacros)
import ObservationMacros

struct ObservationMacrosTests {
  let macros: [String: MacroSpec] = [
    "Observable": MacroSpec(type: ObservableMacro.self),
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

  // MARK: - @Observable macro expansion tests

  @Test
  func observableOnSimpleClass() {
    assertMacroExpansion(
      #"""
      @Observable
      final class SimpleClass {
        var value = 0
      }
      """#,
      expandedSource: #"""
        final class SimpleClass {
          var value {
              @storageRestrictions(initializes: _value)
              init(initialValue) {
                _value = initialValue
              }
              get {
                #if $Embedded
                access(propertyIndex: 0)
                #else
                access(keyPath: \.value, propertyIndex: 0)
                #endif
                return _value
              }
              set {
                guard shouldNotifyObservers(_value, newValue) else {
                  _value = newValue
                  return
                }
                #if $Embedded
                withMutation(propertyIndex: 0) {
                  _value = newValue
                }
                #else
                withMutation(keyPath: \.value, propertyIndex: 0) {
                  _value = newValue
                }
                #endif
              }
              _modify {
                #if $Embedded
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(propertyIndex: 0)
                }
                #else
                access(keyPath: \.value, propertyIndex: 0)
                _$observationRegistrar.willSet(self, keyPath: \.value, propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(self, keyPath: \.value, propertyIndex: 0)
                }
                #endif
                yield &_value
              }
          }
          private  var _value  = 0

            private let _$observationRegistrar = Observation.ObservationRegistrar()

            #if !$Embedded
            internal nonisolated func access<__macro_local_6MemberfMu_>(
              keyPath: KeyPath<SimpleClass, __macro_local_6MemberfMu_>
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath)
            }
            #endif

            #if !$Embedded
            internal nonisolated func withMutation<__macro_local_6MemberfMu0_, __macro_local_14MutationResultfMu_>(
              keyPath: KeyPath<SimpleClass, __macro_local_6MemberfMu0_>,
              _ mutation: () throws -> __macro_local_14MutationResultfMu_
            ) rethrows -> __macro_local_14MutationResultfMu_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
            }
            #endif

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu1_>(_ lhs: __macro_local_6MemberfMu1_, _ rhs: __macro_local_6MemberfMu1_) -> Bool {
                true
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu2_: Equatable>(_ lhs: __macro_local_6MemberfMu2_, _ rhs: __macro_local_6MemberfMu2_) -> Bool {
                lhs != rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu3_: AnyObject>(_ lhs: __macro_local_6MemberfMu3_, _ rhs: __macro_local_6MemberfMu3_) -> Bool {
                lhs !== rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu4_: Equatable & AnyObject>(_ lhs: __macro_local_6MemberfMu4_, _ rhs: __macro_local_6MemberfMu4_) -> Bool {
                lhs != rhs
            }

            #if $Embedded
            internal nonisolated func access(propertyIndex: Int) {
              _$observationRegistrar.access(propertyIndex: property index)
            }
            #else
            internal nonisolated func access<__macro_local_6MemberfMu5_>(
              keyPath: KeyPath<SimpleClass, __macro_local_6MemberfMu5_>,
              propertyIndex: Int
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath, propertyIndex: property index)
            }
            #endif

            #if $Embedded
            internal nonisolated func withMutation<__macro_local_14MutationResultfMu1_, __macro_local_7FailurefMu_: Error>(
              propertyIndex: Int,
              _ mutation: () throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_
            ) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_ {
              try _$observationRegistrar.withMutation(propertyIndex: property index, mutation)
            }
            #else
            internal nonisolated func withMutation<__macro_local_6MemberfMu6_, __macro_local_14MutationResultfMu0_>(
              keyPath: KeyPath<SimpleClass, __macro_local_6MemberfMu6_>,
              propertyIndex: Int,
              _ mutation: () throws -> __macro_local_14MutationResultfMu0_
            ) rethrows -> __macro_local_14MutationResultfMu0_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, propertyIndex: property index, mutation)
            }
            #endif
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // Property indices count only observed properties (not ignored, computed, immutable,
  // or static ones), in declaration order.
  @Test
  func observablePropertyIndexsFollowDeclarationOrder() {
    assertMacroExpansion(
      #"""
      @Observable
      final class MultiClass {
        var first = 0
        @ObservationIgnored var ignored = 1
        var computed: Int { first }
        let constant = 2
        static var shared = 3
        var second = 4
        var third = 5
      }
      """#,
      expandedSource: #"""
        final class MultiClass {
          var first {
              @storageRestrictions(initializes: _first)
              init(initialValue) {
                _first = initialValue
              }
              get {
                #if $Embedded
                access(propertyIndex: 0)
                #else
                access(keyPath: \.first, propertyIndex: 0)
                #endif
                return _first
              }
              set {
                guard shouldNotifyObservers(_first, newValue) else {
                  _first = newValue
                  return
                }
                #if $Embedded
                withMutation(propertyIndex: 0) {
                  _first = newValue
                }
                #else
                withMutation(keyPath: \.first, propertyIndex: 0) {
                  _first = newValue
                }
                #endif
              }
              _modify {
                #if $Embedded
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(propertyIndex: 0)
                }
                #else
                access(keyPath: \.first, propertyIndex: 0)
                _$observationRegistrar.willSet(self, keyPath: \.first, propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(self, keyPath: \.first, propertyIndex: 0)
                }
                #endif
                yield &_first
              }
          }
          private  var _first  = 0
          var ignored = 1
          var computed: Int { first }
          let constant = 2
          static var shared = 3
          var second {
              @storageRestrictions(initializes: _second)
              init(initialValue) {
                _second = initialValue
              }
              get {
                #if $Embedded
                access(propertyIndex: 1)
                #else
                access(keyPath: \.second, propertyIndex: 1)
                #endif
                return _second
              }
              set {
                guard shouldNotifyObservers(_second, newValue) else {
                  _second = newValue
                  return
                }
                #if $Embedded
                withMutation(propertyIndex: 1) {
                  _second = newValue
                }
                #else
                withMutation(keyPath: \.second, propertyIndex: 1) {
                  _second = newValue
                }
                #endif
              }
              _modify {
                #if $Embedded
                access(propertyIndex: 1)
                _$observationRegistrar.willSet(propertyIndex: 1)
                defer {
                    _$observationRegistrar.didSet(propertyIndex: 1)
                }
                #else
                access(keyPath: \.second, propertyIndex: 1)
                _$observationRegistrar.willSet(self, keyPath: \.second, propertyIndex: 1)
                defer {
                    _$observationRegistrar.didSet(self, keyPath: \.second, propertyIndex: 1)
                }
                #endif
                yield &_second
              }
          }
          private  var _second  = 4
          var third {
              @storageRestrictions(initializes: _third)
              init(initialValue) {
                _third = initialValue
              }
              get {
                #if $Embedded
                access(propertyIndex: 2)
                #else
                access(keyPath: \.third, propertyIndex: 2)
                #endif
                return _third
              }
              set {
                guard shouldNotifyObservers(_third, newValue) else {
                  _third = newValue
                  return
                }
                #if $Embedded
                withMutation(propertyIndex: 2) {
                  _third = newValue
                }
                #else
                withMutation(keyPath: \.third, propertyIndex: 2) {
                  _third = newValue
                }
                #endif
              }
              _modify {
                #if $Embedded
                access(propertyIndex: 2)
                _$observationRegistrar.willSet(propertyIndex: 2)
                defer {
                    _$observationRegistrar.didSet(propertyIndex: 2)
                }
                #else
                access(keyPath: \.third, propertyIndex: 2)
                _$observationRegistrar.willSet(self, keyPath: \.third, propertyIndex: 2)
                defer {
                    _$observationRegistrar.didSet(self, keyPath: \.third, propertyIndex: 2)
                }
                #endif
                yield &_third
              }
          }
          private  var _third  = 5

            private let _$observationRegistrar = Observation.ObservationRegistrar()

            #if !$Embedded
            internal nonisolated func access<__macro_local_6MemberfMu_>(
              keyPath: KeyPath<MultiClass, __macro_local_6MemberfMu_>
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath)
            }
            #endif

            #if !$Embedded
            internal nonisolated func withMutation<__macro_local_6MemberfMu0_, __macro_local_14MutationResultfMu_>(
              keyPath: KeyPath<MultiClass, __macro_local_6MemberfMu0_>,
              _ mutation: () throws -> __macro_local_14MutationResultfMu_
            ) rethrows -> __macro_local_14MutationResultfMu_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
            }
            #endif

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu1_>(_ lhs: __macro_local_6MemberfMu1_, _ rhs: __macro_local_6MemberfMu1_) -> Bool {
                true
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu2_: Equatable>(_ lhs: __macro_local_6MemberfMu2_, _ rhs: __macro_local_6MemberfMu2_) -> Bool {
                lhs != rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu3_: AnyObject>(_ lhs: __macro_local_6MemberfMu3_, _ rhs: __macro_local_6MemberfMu3_) -> Bool {
                lhs !== rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu4_: Equatable & AnyObject>(_ lhs: __macro_local_6MemberfMu4_, _ rhs: __macro_local_6MemberfMu4_) -> Bool {
                lhs != rhs
            }

            #if $Embedded
            internal nonisolated func access(propertyIndex: Int) {
              _$observationRegistrar.access(propertyIndex: property index)
            }
            #else
            internal nonisolated func access<__macro_local_6MemberfMu5_>(
              keyPath: KeyPath<MultiClass, __macro_local_6MemberfMu5_>,
              propertyIndex: Int
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath, propertyIndex: property index)
            }
            #endif

            #if $Embedded
            internal nonisolated func withMutation<__macro_local_14MutationResultfMu1_, __macro_local_7FailurefMu_: Error>(
              propertyIndex: Int,
              _ mutation: () throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_
            ) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_ {
              try _$observationRegistrar.withMutation(propertyIndex: property index, mutation)
            }
            #else
            internal nonisolated func withMutation<__macro_local_6MemberfMu6_, __macro_local_14MutationResultfMu0_>(
              keyPath: KeyPath<MultiClass, __macro_local_6MemberfMu6_>,
              propertyIndex: Int,
              _ mutation: () throws -> __macro_local_14MutationResultfMu0_
            ) rethrows -> __macro_local_14MutationResultfMu0_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, propertyIndex: property index, mutation)
            }
            #endif
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // A class with its own `access(keyPath:)` gets a property index-taking `access` that
  // forwards to it, so the customization still runs; `withMutation`, not
  // customized, calls the registrar's property index-tagged entry point. Under
  // Embedded, which cannot forward by key path, the customization without an
  // `access(propertyIndex:)` of its own is an error rather than bypassed.
  @Test
  func observablePropertyIndexAccessForwardsToCustomAccess() {
    assertMacroExpansion(
      #"""
      @Observable
      final class CustomAccess {
        var value = 0

        func access<Member>(keyPath: KeyPath<CustomAccess, Member>) {
        }
      }
      """#,
      expandedSource: #"""
        final class CustomAccess {
          var value {
              @storageRestrictions(initializes: _value)
              init(initialValue) {
                _value = initialValue
              }
              get {
                #if $Embedded
                access(propertyIndex: 0)
                #else
                access(keyPath: \.value, propertyIndex: 0)
                #endif
                return _value
              }
              set {
                guard shouldNotifyObservers(_value, newValue) else {
                  _value = newValue
                  return
                }
                #if $Embedded
                withMutation(propertyIndex: 0) {
                  _value = newValue
                }
                #else
                withMutation(keyPath: \.value, propertyIndex: 0) {
                  _value = newValue
                }
                #endif
              }
              _modify {
                #if $Embedded
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(propertyIndex: 0)
                }
                #else
                access(keyPath: \.value, propertyIndex: 0)
                _$observationRegistrar.willSet(self, keyPath: \.value, propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(self, keyPath: \.value, propertyIndex: 0)
                }
                #endif
                yield &_value
              }
          }
          private  var _value  = 0

          func access<Member>(keyPath: KeyPath<CustomAccess, Member>) {
          }

            private let _$observationRegistrar = Observation.ObservationRegistrar()

            #if !$Embedded
            internal nonisolated func withMutation<__macro_local_6MemberfMu0_, __macro_local_14MutationResultfMu_>(
              keyPath: KeyPath<CustomAccess, __macro_local_6MemberfMu0_>,
              _ mutation: () throws -> __macro_local_14MutationResultfMu_
            ) rethrows -> __macro_local_14MutationResultfMu_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
            }
            #endif

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu1_>(_ lhs: __macro_local_6MemberfMu1_, _ rhs: __macro_local_6MemberfMu1_) -> Bool {
                true
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu2_: Equatable>(_ lhs: __macro_local_6MemberfMu2_, _ rhs: __macro_local_6MemberfMu2_) -> Bool {
                lhs != rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu3_: AnyObject>(_ lhs: __macro_local_6MemberfMu3_, _ rhs: __macro_local_6MemberfMu3_) -> Bool {
                lhs !== rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu4_: Equatable & AnyObject>(_ lhs: __macro_local_6MemberfMu4_, _ rhs: __macro_local_6MemberfMu4_) -> Bool {
                lhs != rhs
            }

            #if $Embedded
            #error("'@Observable' cannot forward to 'access(keyPath:)' of 'CustomAccess' in Embedded Swift, which has no key paths; implement 'access(propertyIndex:)' too")
            #else
            internal nonisolated func access<__macro_local_6MemberfMu5_>(
              keyPath: KeyPath<CustomAccess, __macro_local_6MemberfMu5_>,
              propertyIndex: Int
            ) {
              access(keyPath: keyPath)
            }
            #endif

            #if $Embedded
            internal nonisolated func withMutation<__macro_local_14MutationResultfMu1_, __macro_local_7FailurefMu_: Error>(
              propertyIndex: Int,
              _ mutation: () throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_
            ) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_ {
              try _$observationRegistrar.withMutation(propertyIndex: property index, mutation)
            }
            #else
            internal nonisolated func withMutation<__macro_local_6MemberfMu6_, __macro_local_14MutationResultfMu0_>(
              keyPath: KeyPath<CustomAccess, __macro_local_6MemberfMu6_>,
              propertyIndex: Int,
              _ mutation: () throws -> __macro_local_14MutationResultfMu0_
            ) rethrows -> __macro_local_14MutationResultfMu0_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, propertyIndex: property index, mutation)
            }
            #endif
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // A class customizing both by key path and by property index gets no Embedded
  // members: its accessors call its own `access(propertyIndex:)` and
  // `withMutation(propertyIndex:_:)` there, and forward by key path otherwise.
  @Test
  func observableEmbeddedUsesCustomPropertyIndexAccessAndMutation() {
    assertMacroExpansion(
      #"""
      @Observable
      final class CustomPropertyIndexAccess {
        var value = 0

        func access<Member>(keyPath: KeyPath<CustomPropertyIndexAccess, Member>) {
        }

        func withMutation<Member, T>(keyPath: KeyPath<CustomPropertyIndexAccess, Member>, _ mutation: () throws -> T) rethrows -> T {
          try mutation()
        }

        func access(propertyIndex: Int) {
        }

        func withMutation<T, Failure: Error>(propertyIndex: Int, _ mutation: () throws(Failure) -> T) throws(Failure) -> T {
          try mutation()
        }
      }
      """#,
      expandedSource: #"""
        final class CustomPropertyIndexAccess {
          var value {
              @storageRestrictions(initializes: _value)
              init(initialValue) {
                _value = initialValue
              }
              get {
                #if $Embedded
                access(propertyIndex: 0)
                #else
                access(keyPath: \.value, propertyIndex: 0)
                #endif
                return _value
              }
              set {
                guard shouldNotifyObservers(_value, newValue) else {
                  _value = newValue
                  return
                }
                #if $Embedded
                withMutation(propertyIndex: 0) {
                  _value = newValue
                }
                #else
                withMutation(keyPath: \.value, propertyIndex: 0) {
                  _value = newValue
                }
                #endif
              }
              _modify {
                #if $Embedded
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(propertyIndex: 0)
                }
                #else
                access(keyPath: \.value, propertyIndex: 0)
                _$observationRegistrar.willSet(self, keyPath: \.value, propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(self, keyPath: \.value, propertyIndex: 0)
                }
                #endif
                yield &_value
              }
          }
          private  var _value  = 0

          func access<Member>(keyPath: KeyPath<CustomPropertyIndexAccess, Member>) {
          }

          func withMutation<Member, T>(keyPath: KeyPath<CustomPropertyIndexAccess, Member>, _ mutation: () throws -> T) rethrows -> T {
            try mutation()
          }

          func access(propertyIndex: Int) {
          }

          func withMutation<T, Failure: Error>(propertyIndex: Int, _ mutation: () throws(Failure) -> T) throws(Failure) -> T {
            try mutation()
          }

            private let _$observationRegistrar = Observation.ObservationRegistrar()

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu1_>(_ lhs: __macro_local_6MemberfMu1_, _ rhs: __macro_local_6MemberfMu1_) -> Bool {
                true
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu2_: Equatable>(_ lhs: __macro_local_6MemberfMu2_, _ rhs: __macro_local_6MemberfMu2_) -> Bool {
                lhs != rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu3_: AnyObject>(_ lhs: __macro_local_6MemberfMu3_, _ rhs: __macro_local_6MemberfMu3_) -> Bool {
                lhs !== rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu4_: Equatable & AnyObject>(_ lhs: __macro_local_6MemberfMu4_, _ rhs: __macro_local_6MemberfMu4_) -> Bool {
                lhs != rhs
            }

            #if !$Embedded
            internal nonisolated func access<__macro_local_6MemberfMu5_>(
              keyPath: KeyPath<CustomPropertyIndexAccess, __macro_local_6MemberfMu5_>,
              propertyIndex: Int
            ) {
              access(keyPath: keyPath)
            }
            #endif

            #if !$Embedded
            internal nonisolated func withMutation<__macro_local_6MemberfMu6_, __macro_local_14MutationResultfMu0_>(
              keyPath: KeyPath<CustomPropertyIndexAccess, __macro_local_6MemberfMu6_>,
              propertyIndex: Int,
              _ mutation: () throws -> __macro_local_14MutationResultfMu0_
            ) rethrows -> __macro_local_14MutationResultfMu0_ {
              try withMutation(keyPath: keyPath, mutation)
            }
            #endif
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // A property explicitly marked `@ObservationTracked`, with no property index, keeps
  // the key-path-only calls; under Embedded, which has no key paths, it is
  // an error rather than silently untracked.
  @Test
  func observationTrackedWithoutPropertyIndexUsesKeyPathOnlyCalls() {
    assertMacroExpansion(
      #"""
      final class TrackedClass {
        @ObservationTracked var value = 0
      }
      """#,
      expandedSource: #"""
        final class TrackedClass {
          var value {
              @storageRestrictions(initializes: _value)
              init(initialValue) {
                _value = initialValue
              }
              get {
                #if $Embedded
                #error("'@Observable' cannot track 'value' in Embedded Swift because it is not a direct member of its class")
                #else
                access(keyPath: \.value)
                #endif
                return _value
              }
              set {
                guard shouldNotifyObservers(_value, newValue) else {
                  _value = newValue
                  return
                }
                #if $Embedded
                #error("'@Observable' cannot track 'value' in Embedded Swift because it is not a direct member of its class")
                #else
                withMutation(keyPath: \.value) {
                  _value = newValue
                }
                #endif
              }
              _modify {
                #if $Embedded
                #error("'@Observable' cannot track 'value' in Embedded Swift because it is not a direct member of its class")
                #else
                access(keyPath: \.value)
                _$observationRegistrar.willSet(self, keyPath: \.value)
                defer {
                    _$observationRegistrar.didSet(self, keyPath: \.value)
                }
                #endif
                yield &_value
              }
          }
          private  var _value  = 0
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // MARK: - @Observable diagnostic tests

  @Test
  func observableOnEnumError() {
    assertMacroExpansion(
      #"""
      @Observable
      enum MyEnum {
        case myCase
      }
      """#,
      expandedSource: #"""
        enum MyEnum {
          case myCase
        }
        """#,
      diagnostics: [
        DiagnosticSpec(message: "'@Observable' cannot be applied to enumeration type 'MyEnum'", line: 1, column: 1)
      ],
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  @Test
  func observableOnStructError() {
    assertMacroExpansion(
      #"""
      @Observable
      struct MyStruct {
      }
      """#,
      expandedSource: #"""
        struct MyStruct {
        }
        """#,
      diagnostics: [
        DiagnosticSpec(message: "'@Observable' cannot be applied to struct type 'MyStruct'", line: 1, column: 1)
      ],
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  @Test
  func observableOnActor() {
    assertMacroExpansion(
      #"""
      @Observable
      actor MyActor {
        var count = 0
      }
      """#,
      expandedSource: #"""
        actor MyActor {
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
                  _count = newValue
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

            private let _$observationRegistrar = Observation.ObservationRegistrar()

            internal func access(propertyIndex: Int) {
              _$observationRegistrar.access(propertyIndex: propertyIndex)
            }

            internal func withMutation<__macro_local_14MutationResultfMu_, __macro_local_7FailurefMu_: Error>(
              propertyIndex: Int,
              _ mutation: () throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu_
            ) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu_ {
              try _$observationRegistrar.withMutation(propertyIndex: propertyIndex, mutation)
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
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  @Test
  func observableOnDistributedActor() {
    assertMacroExpansion(
      #"""
      @Observable
      distributed actor MyActor {
        var count = 0
      }
      """#,
      expandedSource: #"""
        distributed actor MyActor {
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
                  _count = newValue
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

            private let _$observationRegistrar = Observation.ObservationRegistrar()

            internal func access(propertyIndex: Int) {
              _$observationRegistrar.access(propertyIndex: propertyIndex)
            }

            internal func withMutation<__macro_local_14MutationResultfMu_, __macro_local_7FailurefMu_: Error>(
              propertyIndex: Int,
              _ mutation: () throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu_
            ) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu_ {
              try _$observationRegistrar.withMutation(propertyIndex: propertyIndex, mutation)
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
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // A `#if`-nested member is not covered here: this harness's
  // `MacroApplication` never applies a member attribute macro to members
  // inside an `IfConfigDeclSyntax`, so it cannot show the bare
  // `@ObservationTracked` such a member gets. The compiler does, and
  // `parityConditionallyCompiledMemberIsTracked` in
  // Tests/ObservationTests/BaselineParityTests.swift checks it.

  // The member attribute expansion runs once per member, so a non-literal
  // `resolution:` must be diagnosed once for the type, not once per member.
  @Test
  func observableWithNonLiteralResolutionError() {
    assertMacroExpansion(
      #"""
      @Observable(resolution: someResolution)
      final class Model {
        var a = 0
        var b = 0
      }
      """#,
      expandedSource: #"""
        final class Model {
          @ObservationTracked(propertyIndex: 0)
          var a = 0
          @ObservationTracked(propertyIndex: 1)
          var b = 0
        }
        """#,
      diagnostics: [
        DiagnosticSpec(message: "the 'resolution:' argument must be a literal member access (such as '.default' or '.object')", line: 1, column: 25)
      ],
      macroSpecs: ["Observable": MacroSpec(type: ObservableMacro.self)],
      failureHandler: expectNoMacroFailure
    )
  }

  @Test
  func observationTrackedWithNonLiteralPropertyIndexError() {
    assertMacroExpansion(
      #"""
      final class TrackedClass {
        @ObservationTracked(propertyIndex: somePropertyIndex) var value = 0
      }
      """#,
      expandedSource: #"""
        final class TrackedClass {
          var value = 0
          private  var _value  = 0
        }
        """#,
      diagnostics: [
        DiagnosticSpec(message: "the 'propertyIndex:' argument must be a non-negative integer literal", line: 2, column: 29)
      ],
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  @Test
  func observationTrackedWithNonLiteralGroupError() {
    assertMacroExpansion(
      #"""
      final class TrackedClass {
        @ObservationTracked(group: someGroup) var value = 0
      }
      """#,
      expandedSource: #"""
        final class TrackedClass {
          var value = 0
          private  var _value  = 0
        }
        """#,
      diagnostics: [
        DiagnosticSpec(message: "the 'group:' argument must be a non-negative integer literal", line: 2, column: 30)
      ],
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // A non-literal `propertyIndex:` beside a `group:`, in an `@Observable` class, is
  // diagnosed rather than taken for no property index and deferred to `@Observable`.
  // (`@Observable` is left unexpanded, so only the hand-written attribute's
  // own expansion is seen.)
  @Test
  func observationTrackedWithNonLiteralPropertyIndexAndGroupError() {
    assertMacroExpansion(
      #"""
      @Observable
      final class TrackedClass {
        @ObservationTracked(propertyIndex: somePropertyIndex, group: 0) var value = 0
      }
      """#,
      expandedSource: #"""
        @Observable
        final class TrackedClass {
          var value = 0
          private  var _value  = 0
        }
        """#,
      diagnostics: [
        DiagnosticSpec(message: "the 'propertyIndex:' argument must be a non-negative integer literal", line: 3, column: 29)
      ],
      macroSpecs: [
        "ObservationTracked": MacroSpec(type: ObservationTrackedMacro.self),
        "ObservationIgnored": MacroSpec(type: ObservationIgnoredMacro.self),
      ],
      failureHandler: expectNoMacroFailure
    )
  }

  // When both @Observable and a hand-written @ObservationTracked with a
  // non-literal propertyIndex: and valid group: are applied, the diagnostic from the
  // hand-written attribute should fire once, and @Observable should NOT
  // attach an additional attribute (it defers via hasObservationPropertyIndexArgument).
  // This test uses the FULL macros dict to verify no duplicate diagnostic
  // when both macros run together (cf. observationTrackedWithNonLiteralPropertyIndexAndGroupError
  // which uses a partial dict to keep @Observable unexpanded).
  @Test
  func observableWithHandWrittenObservationTrackedNonLiteralPropertyIndex() {
    assertMacroExpansion(
      #"""
      @Observable
      final class C {
        @ObservationTracked(propertyIndex: somePropertyIndex, group: 0) var v = 0
      }
      """#,
      expandedSource: #"""
        final class C {
          var v = 0
          private  var _v  = 0

            private let _$observationRegistrar = Observation.ObservationRegistrar()

            #if !$Embedded
            internal nonisolated func access<__macro_local_6MemberfMu_>(
              keyPath: KeyPath<C, __macro_local_6MemberfMu_>
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath)
            }
            #endif

            #if !$Embedded
            internal nonisolated func withMutation<__macro_local_6MemberfMu0_, __macro_local_14MutationResultfMu_>(
              keyPath: KeyPath<C, __macro_local_6MemberfMu0_>,
              _ mutation: () throws -> __macro_local_14MutationResultfMu_
            ) rethrows -> __macro_local_14MutationResultfMu_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
            }
            #endif

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu1_>(_ lhs: __macro_local_6MemberfMu1_, _ rhs: __macro_local_6MemberfMu1_) -> Bool {
                true
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu2_: Equatable>(_ lhs: __macro_local_6MemberfMu2_, _ rhs: __macro_local_6MemberfMu2_) -> Bool {
                lhs != rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu3_: AnyObject>(_ lhs: __macro_local_6MemberfMu3_, _ rhs: __macro_local_6MemberfMu3_) -> Bool {
                lhs !== rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu4_: Equatable & AnyObject>(_ lhs: __macro_local_6MemberfMu4_, _ rhs: __macro_local_6MemberfMu4_) -> Bool {
                lhs != rhs
            }

            #if $Embedded
            internal nonisolated func access(propertyIndex: Int) {
              _$observationRegistrar.access(propertyIndex: property index)
            }
            #else
            internal nonisolated func access<__macro_local_6MemberfMu5_>(
              keyPath: KeyPath<C, __macro_local_6MemberfMu5_>,
              propertyIndex: Int
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath, propertyIndex: property index)
            }
            #endif

            #if $Embedded
            internal nonisolated func withMutation<__macro_local_14MutationResultfMu1_, __macro_local_7FailurefMu_: Error>(
              propertyIndex: Int,
              _ mutation: () throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_
            ) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_ {
              try _$observationRegistrar.withMutation(propertyIndex: property index, mutation)
            }
            #else
            internal nonisolated func withMutation<__macro_local_6MemberfMu6_, __macro_local_14MutationResultfMu0_>(
              keyPath: KeyPath<C, __macro_local_6MemberfMu6_>,
              propertyIndex: Int,
              _ mutation: () throws -> __macro_local_14MutationResultfMu0_
            ) rethrows -> __macro_local_14MutationResultfMu0_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, propertyIndex: property index, mutation)
            }
            #endif
        }
        """#,
      diagnostics: [
        DiagnosticSpec(message: "the 'propertyIndex:' argument must be a non-negative integer literal", line: 3, column: 29)
      ],
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // Properties sharing a property index all form the representative's key path in
  // their own accessors, in their own isolation, so with mixed isolation the
  // nonisolated property, not the first declared, stands for the property index.
  @Test
  func observableSharedPropertyIndexPrefersNonisolatedRepresentative() {
    assertMacroExpansion(
      #"""
      @Observable(resolution: .object)
      final class C {
        @MainActor var isolated = ""
        var plain = 0
      }
      """#,
      expandedSource: #"""
        final class C {
          @MainActor
          @ObservationTracked(propertyIndex: 0, representative: "plain") var isolated = ""
          @ObservationTracked(propertyIndex: 0)
          var plain = 0

            @ObservationIgnored private let _$observationRegistrar = Observation.ObservationRegistrar()

            #if !$Embedded
            internal nonisolated func access<__macro_local_6MemberfMu_>(
              keyPath: KeyPath<C, __macro_local_6MemberfMu_>
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath)
            }
            #endif

            #if !$Embedded
            internal nonisolated func withMutation<__macro_local_6MemberfMu0_, __macro_local_14MutationResultfMu_>(
              keyPath: KeyPath<C, __macro_local_6MemberfMu0_>,
              _ mutation: () throws -> __macro_local_14MutationResultfMu_
            ) rethrows -> __macro_local_14MutationResultfMu_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
            }
            #endif

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu1_>(_ lhs: __macro_local_6MemberfMu1_, _ rhs: __macro_local_6MemberfMu1_) -> Bool {
                true
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu2_: Equatable>(_ lhs: __macro_local_6MemberfMu2_, _ rhs: __macro_local_6MemberfMu2_) -> Bool {
                lhs != rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu3_: AnyObject>(_ lhs: __macro_local_6MemberfMu3_, _ rhs: __macro_local_6MemberfMu3_) -> Bool {
                lhs !== rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu4_: Equatable & AnyObject>(_ lhs: __macro_local_6MemberfMu4_, _ rhs: __macro_local_6MemberfMu4_) -> Bool {
                lhs != rhs
            }

            #if $Embedded
            internal nonisolated func access(propertyIndex: Int) {
              _$observationRegistrar.access(propertyIndex: property index)
            }
            #else
            internal nonisolated func access<__macro_local_6MemberfMu5_>(
              keyPath: KeyPath<C, __macro_local_6MemberfMu5_>,
              propertyIndex: Int
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath, propertyIndex: property index)
            }
            #endif

            #if $Embedded
            internal nonisolated func withMutation<__macro_local_14MutationResultfMu1_, __macro_local_7FailurefMu_: Error>(
              propertyIndex: Int,
              _ mutation: () throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_
            ) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_ {
              try _$observationRegistrar.withMutation(propertyIndex: property index, mutation)
            }
            #else
            internal nonisolated func withMutation<__macro_local_6MemberfMu6_, __macro_local_14MutationResultfMu0_>(
              keyPath: KeyPath<C, __macro_local_6MemberfMu6_>,
              propertyIndex: Int,
              _ mutation: () throws -> __macro_local_14MutationResultfMu0_
            ) rethrows -> __macro_local_14MutationResultfMu0_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, propertyIndex: property index, mutation)
            }
            #endif
        }
        """#,
      macroSpecs: ["Observable": MacroSpec(type: ObservableMacro.self)],
      failureHandler: expectNoMacroFailure
    )
  }

  // With no nonisolated property among them, properties sharing a property index but
  // isolated to different actors are diagnosed, rather than expanded into
  // key paths their accessors cannot form.
  @Test
  func observableSharedPropertyIndexWithDifferentActorsError() {
    assertMacroExpansion(
      #"""
      @Observable(resolution: .object)
      final class C {
        @MainActor var a = 0
        @OtherActor var b = 0
      }
      """#,
      expandedSource: #"""
        final class C {
          @MainActor
          @ObservationTracked(propertyIndex: 0) var a = 0
          @OtherActor var b = 0

            @ObservationIgnored private let _$observationRegistrar = Observation.ObservationRegistrar()

            #if !$Embedded
            internal nonisolated func access<__macro_local_6MemberfMu_>(
              keyPath: KeyPath<C, __macro_local_6MemberfMu_>
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath)
            }
            #endif

            #if !$Embedded
            internal nonisolated func withMutation<__macro_local_6MemberfMu0_, __macro_local_14MutationResultfMu_>(
              keyPath: KeyPath<C, __macro_local_6MemberfMu0_>,
              _ mutation: () throws -> __macro_local_14MutationResultfMu_
            ) rethrows -> __macro_local_14MutationResultfMu_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
            }
            #endif

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu1_>(_ lhs: __macro_local_6MemberfMu1_, _ rhs: __macro_local_6MemberfMu1_) -> Bool {
                true
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu2_: Equatable>(_ lhs: __macro_local_6MemberfMu2_, _ rhs: __macro_local_6MemberfMu2_) -> Bool {
                lhs != rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu3_: AnyObject>(_ lhs: __macro_local_6MemberfMu3_, _ rhs: __macro_local_6MemberfMu3_) -> Bool {
                lhs !== rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu4_: Equatable & AnyObject>(_ lhs: __macro_local_6MemberfMu4_, _ rhs: __macro_local_6MemberfMu4_) -> Bool {
                lhs != rhs
            }

            #if $Embedded
            internal nonisolated func access(propertyIndex: Int) {
              _$observationRegistrar.access(propertyIndex: property index)
            }
            #else
            internal nonisolated func access<__macro_local_6MemberfMu5_>(
              keyPath: KeyPath<C, __macro_local_6MemberfMu5_>,
              propertyIndex: Int
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath, propertyIndex: property index)
            }
            #endif

            #if $Embedded
            internal nonisolated func withMutation<__macro_local_14MutationResultfMu1_, __macro_local_7FailurefMu_: Error>(
              propertyIndex: Int,
              _ mutation: () throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_
            ) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_ {
              try _$observationRegistrar.withMutation(propertyIndex: property index, mutation)
            }
            #else
            internal nonisolated func withMutation<__macro_local_6MemberfMu6_, __macro_local_14MutationResultfMu0_>(
              keyPath: KeyPath<C, __macro_local_6MemberfMu6_>,
              propertyIndex: Int,
              _ mutation: () throws -> __macro_local_14MutationResultfMu0_
            ) rethrows -> __macro_local_14MutationResultfMu0_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, propertyIndex: property index, mutation)
            }
            #endif
        }
        """#,
      diagnostics: [
        DiagnosticSpec(message: "'@Observable' cannot share a property index between 'b', isolated to 'OtherActor', and 'a', isolated to 'MainActor'; mark a property sharing it 'nonisolated', or give them different groups", line: 4, column: 3)
      ],
      macroSpecs: ["Observable": MacroSpec(type: ObservableMacro.self)],
      failureHandler: expectNoMacroFailure
    )
  }


  // MARK: - @ObservationIgnored macro tests

  @Test
  func observationIgnoredOnIgnoredProperty() {
    assertMacroExpansion(
      #"""
      final class TestClass {
        @ObservationIgnored var ignored = 0
      }
      """#,
      expandedSource: #"""
        final class TestClass {
          var ignored = 0
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  @Test
  func observationIgnoredDoesNotModifyProperty() {
    // When @ObservationIgnored is used, it should not add accessors
    assertMacroExpansion(
      #"""
      final class TestClass {
        @ObservationIgnored var field = 3
      }
      """#,
      expandedSource: #"""
        final class TestClass {
          var field = 3
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // MARK: - @ObservationDerived macro tests

  @Test
  func derivedOnStructPropertyError() {
    assertMacroExpansion(
      #"""
      struct DerivedInStruct {
        @ObservationDerived var value: Int {
          input { 1 }
          update { $0 }
        }
      }
      """#,
      expandedSource: #"""
        struct DerivedInStruct {
          var value: Int {
            input { 1 }
            update { $0 }
          }
        }
        """#,
      diagnostics: [
        DiagnosticSpec(message: "'@ObservationDerived' can only be applied to a property of a class or noncopyable struct", line: 2, column: 3)
      ],
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }


  @Test
  func observableWithGroupSamePropertyIndex() {
    // Properties with the same `@ObservationTracked(group:)` share the property index of
    // the group's first property, and pass its key path. The hand-written
    // attribute expands to nothing; `@Observable` attaches the one with the
    // property index, so each property gets one set of accessors and one storage.
    assertMacroExpansion(
      #"""
      @Observable
      final class GroupModel {
        @ObservationTracked(group: 1) var a = 0
        @ObservationTracked(group: 1) var b = 1
      }
      """#,
      expandedSource: #"""
        final class GroupModel {
          var a {
              @storageRestrictions(initializes: _a)
              init(initialValue) {
                _a = initialValue
              }
              get {
                #if $Embedded
                access(propertyIndex: 0)
                #else
                access(keyPath: \.a, propertyIndex: 0)
                #endif
                return _a
              }
              set {
                guard shouldNotifyObservers(_a, newValue) else {
                  _a = newValue
                  return
                }
                #if $Embedded
                withMutation(propertyIndex: 0) {
                  _a = newValue
                }
                #else
                withMutation(keyPath: \.a, propertyIndex: 0) {
                  _a = newValue
                }
                #endif
              }
              _modify {
                #if $Embedded
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(propertyIndex: 0)
                }
                #else
                access(keyPath: \.a, propertyIndex: 0)
                _$observationRegistrar.willSet(self, keyPath: \.a, propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(self, keyPath: \.a, propertyIndex: 0)
                }
                #endif
                yield &_a
              }
          }
          private  var _a  = 0
          var b {
              @storageRestrictions(initializes: _b)
              init(initialValue) {
                _b = initialValue
              }
              get {
                #if $Embedded
                access(propertyIndex: 0)
                #else
                access(keyPath: \.a, propertyIndex: 0)
                #endif
                return _b
              }
              set {
                guard shouldNotifyObservers(_b, newValue) else {
                  _b = newValue
                  return
                }
                #if $Embedded
                withMutation(propertyIndex: 0) {
                  _b = newValue
                }
                #else
                withMutation(keyPath: \.a, propertyIndex: 0) {
                  _b = newValue
                }
                #endif
              }
              _modify {
                #if $Embedded
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(propertyIndex: 0)
                }
                #else
                access(keyPath: \.a, propertyIndex: 0)
                _$observationRegistrar.willSet(self, keyPath: \.a, propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(self, keyPath: \.a, propertyIndex: 0)
                }
                #endif
                yield &_b
              }
          }
          private  var _b  = 1

            private let _$observationRegistrar = Observation.ObservationRegistrar()

            #if !$Embedded
            internal nonisolated func access<__macro_local_6MemberfMu_>(
              keyPath: KeyPath<GroupModel, __macro_local_6MemberfMu_>
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath)
            }
            #endif

            #if !$Embedded
            internal nonisolated func withMutation<__macro_local_6MemberfMu0_, __macro_local_14MutationResultfMu_>(
              keyPath: KeyPath<GroupModel, __macro_local_6MemberfMu0_>,
              _ mutation: () throws -> __macro_local_14MutationResultfMu_
            ) rethrows -> __macro_local_14MutationResultfMu_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
            }
            #endif

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu1_>(_ lhs: __macro_local_6MemberfMu1_, _ rhs: __macro_local_6MemberfMu1_) -> Bool {
                true
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu2_: Equatable>(_ lhs: __macro_local_6MemberfMu2_, _ rhs: __macro_local_6MemberfMu2_) -> Bool {
                lhs != rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu3_: AnyObject>(_ lhs: __macro_local_6MemberfMu3_, _ rhs: __macro_local_6MemberfMu3_) -> Bool {
                lhs !== rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu4_: Equatable & AnyObject>(_ lhs: __macro_local_6MemberfMu4_, _ rhs: __macro_local_6MemberfMu4_) -> Bool {
                lhs != rhs
            }

            #if $Embedded
            internal nonisolated func access(propertyIndex: Int) {
              _$observationRegistrar.access(propertyIndex: property index)
            }
            #else
            internal nonisolated func access<__macro_local_6MemberfMu5_>(
              keyPath: KeyPath<GroupModel, __macro_local_6MemberfMu5_>,
              propertyIndex: Int
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath, propertyIndex: property index)
            }
            #endif

            #if $Embedded
            internal nonisolated func withMutation<__macro_local_14MutationResultfMu1_, __macro_local_7FailurefMu_: Error>(
              propertyIndex: Int,
              _ mutation: () throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_
            ) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_ {
              try _$observationRegistrar.withMutation(propertyIndex: property index, mutation)
            }
            #else
            internal nonisolated func withMutation<__macro_local_6MemberfMu6_, __macro_local_14MutationResultfMu0_>(
              keyPath: KeyPath<GroupModel, __macro_local_6MemberfMu6_>,
              propertyIndex: Int,
              _ mutation: () throws -> __macro_local_14MutationResultfMu0_
            ) rethrows -> __macro_local_14MutationResultfMu0_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, propertyIndex: property index, mutation)
            }
            #endif
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // Under `@Observable(resolution: .object)` every observed property gets
  // property index 0 and passes the first property's key path.
  @Test
  func observableWithObjectResolutionSharesPropertyIndexZero() {
    assertMacroExpansion(
      #"""
      @Observable(resolution: .object)
      final class ObjectModel {
        var a = 0
        var b = 1
        var c = 2
      }
      """#,
      expandedSource: #"""
        final class ObjectModel {
          var a {
              @storageRestrictions(initializes: _a)
              init(initialValue) {
                _a = initialValue
              }
              get {
                #if $Embedded
                access(propertyIndex: 0)
                #else
                access(keyPath: \.a, propertyIndex: 0)
                #endif
                return _a
              }
              set {
                guard shouldNotifyObservers(_a, newValue) else {
                  _a = newValue
                  return
                }
                #if $Embedded
                withMutation(propertyIndex: 0) {
                  _a = newValue
                }
                #else
                withMutation(keyPath: \.a, propertyIndex: 0) {
                  _a = newValue
                }
                #endif
              }
              _modify {
                #if $Embedded
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(propertyIndex: 0)
                }
                #else
                access(keyPath: \.a, propertyIndex: 0)
                _$observationRegistrar.willSet(self, keyPath: \.a, propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(self, keyPath: \.a, propertyIndex: 0)
                }
                #endif
                yield &_a
              }
          }
          private  var _a  = 0
          var b {
              @storageRestrictions(initializes: _b)
              init(initialValue) {
                _b = initialValue
              }
              get {
                #if $Embedded
                access(propertyIndex: 0)
                #else
                access(keyPath: \.a, propertyIndex: 0)
                #endif
                return _b
              }
              set {
                guard shouldNotifyObservers(_b, newValue) else {
                  _b = newValue
                  return
                }
                #if $Embedded
                withMutation(propertyIndex: 0) {
                  _b = newValue
                }
                #else
                withMutation(keyPath: \.a, propertyIndex: 0) {
                  _b = newValue
                }
                #endif
              }
              _modify {
                #if $Embedded
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(propertyIndex: 0)
                }
                #else
                access(keyPath: \.a, propertyIndex: 0)
                _$observationRegistrar.willSet(self, keyPath: \.a, propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(self, keyPath: \.a, propertyIndex: 0)
                }
                #endif
                yield &_b
              }
          }
          private  var _b  = 1
          var c {
              @storageRestrictions(initializes: _c)
              init(initialValue) {
                _c = initialValue
              }
              get {
                #if $Embedded
                access(propertyIndex: 0)
                #else
                access(keyPath: \.a, propertyIndex: 0)
                #endif
                return _c
              }
              set {
                guard shouldNotifyObservers(_c, newValue) else {
                  _c = newValue
                  return
                }
                #if $Embedded
                withMutation(propertyIndex: 0) {
                  _c = newValue
                }
                #else
                withMutation(keyPath: \.a, propertyIndex: 0) {
                  _c = newValue
                }
                #endif
              }
              _modify {
                #if $Embedded
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(propertyIndex: 0)
                }
                #else
                access(keyPath: \.a, propertyIndex: 0)
                _$observationRegistrar.willSet(self, keyPath: \.a, propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(self, keyPath: \.a, propertyIndex: 0)
                }
                #endif
                yield &_c
              }
          }
          private  var _c  = 2

            private let _$observationRegistrar = Observation.ObservationRegistrar()

            #if !$Embedded
            internal nonisolated func access<__macro_local_6MemberfMu_>(
              keyPath: KeyPath<ObjectModel, __macro_local_6MemberfMu_>
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath)
            }
            #endif

            #if !$Embedded
            internal nonisolated func withMutation<__macro_local_6MemberfMu0_, __macro_local_14MutationResultfMu_>(
              keyPath: KeyPath<ObjectModel, __macro_local_6MemberfMu0_>,
              _ mutation: () throws -> __macro_local_14MutationResultfMu_
            ) rethrows -> __macro_local_14MutationResultfMu_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
            }
            #endif

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu1_>(_ lhs: __macro_local_6MemberfMu1_, _ rhs: __macro_local_6MemberfMu1_) -> Bool {
                true
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu2_: Equatable>(_ lhs: __macro_local_6MemberfMu2_, _ rhs: __macro_local_6MemberfMu2_) -> Bool {
                lhs != rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu3_: AnyObject>(_ lhs: __macro_local_6MemberfMu3_, _ rhs: __macro_local_6MemberfMu3_) -> Bool {
                lhs !== rhs
            }

            private nonisolated final func shouldNotifyObservers<__macro_local_6MemberfMu4_: Equatable & AnyObject>(_ lhs: __macro_local_6MemberfMu4_, _ rhs: __macro_local_6MemberfMu4_) -> Bool {
                lhs != rhs
            }

            #if $Embedded
            internal nonisolated func access(propertyIndex: Int) {
              _$observationRegistrar.access(propertyIndex: property index)
            }
            #else
            internal nonisolated func access<__macro_local_6MemberfMu5_>(
              keyPath: KeyPath<ObjectModel, __macro_local_6MemberfMu5_>,
              propertyIndex: Int
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath, propertyIndex: property index)
            }
            #endif

            #if $Embedded
            internal nonisolated func withMutation<__macro_local_14MutationResultfMu1_, __macro_local_7FailurefMu_: Error>(
              propertyIndex: Int,
              _ mutation: () throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_
            ) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_ {
              try _$observationRegistrar.withMutation(propertyIndex: property index, mutation)
            }
            #else
            internal nonisolated func withMutation<__macro_local_6MemberfMu6_, __macro_local_14MutationResultfMu0_>(
              keyPath: KeyPath<ObjectModel, __macro_local_6MemberfMu6_>,
              propertyIndex: Int,
              _ mutation: () throws -> __macro_local_14MutationResultfMu0_
            ) rethrows -> __macro_local_14MutationResultfMu0_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, propertyIndex: property index, mutation)
            }
            #endif
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }
}
#endif
