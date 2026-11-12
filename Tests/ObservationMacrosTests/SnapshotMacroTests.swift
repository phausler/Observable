import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

#if canImport(ObservationMacros)
import ObservationMacros

// `@Observable` on an actor that conforms to `SnapshotSource` adds the
// synthesis of its snapshot to its observation; on any other type the
// conformance changes nothing.
struct SnapshotMacroTests {
  let macros: [String: MacroSpec] = [
    "Observable": MacroSpec(type: ObservableMacro.self, conformances: ["Observable"]),
    "ObservationTracked": MacroSpec(type: ObservationTrackedMacro.self),
    "ObservationIgnored": MacroSpec(type: ObservationIgnoredMacro.self),
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
  func observableOnSnapshotSourceActor() {
    assertMacroExpansion(
      #"""
      @Observable
      actor MyActor: SnapshotSource {
        var name = "test"
        var index: Int = 0
        @ObservationIgnored var scratch = 0
      }
      """#,
      expandedSource: #"""
        actor MyActor: SnapshotSource {
          var name {
              @storageRestrictions(initializes: _name)
              init(initialValue) {
                _name = initialValue
              }
              get {
                access(propertyIndex: 0)
                return _name
              }
              set {
                guard shouldNotifyObservers(_name, newValue) else {
                  _name = newValue
                  return
                }
                invalidateSnapshot(propertyIndex: 0)
                withMutation(propertyIndex: 0) {
                    _name = newValue
                  }
              }
              _modify {
                invalidateSnapshot(propertyIndex: 0)
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                  _$observationRegistrar.didSet(propertyIndex: 0)
                }
                yield &_name
              }
          }
          private  var _name  = "test"
          var index: Int {
              @storageRestrictions(initializes: _index)
              init(initialValue) {
                _index = initialValue
              }
              get {
                access(propertyIndex: 1)
                return _index
              }
              set {
                guard shouldNotifyObservers(_index, newValue) else {
                  _index = newValue
                  return
                }
                invalidateSnapshot(propertyIndex: 1)
                withMutation(propertyIndex: 1) {
                    _index = newValue
                  }
              }
              _modify {
                invalidateSnapshot(propertyIndex: 1)
                access(propertyIndex: 1)
                _$observationRegistrar.willSet(propertyIndex: 1)
                defer {
                  _$observationRegistrar.didSet(propertyIndex: 1)
                }
                yield &_index
              }
          }
          private  var _index: Int = 0
          var scratch = 0

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

            struct Snapshot: Sendable {
              var _$registrar: Observation.ObservationRegistrar
              var name {
                  @storageRestrictions(initializes: _name)
                  init(initialValue) {
                    _name = initialValue
                  }
                  get {
                    _$registrar.access(propertyIndex: 0)
                    return _name
                  }
              }

              fileprivate var _name = "test"
              var index: Int {
                  @storageRestrictions(initializes: _index)
                  init(initialValue) {
                    _index = initialValue
                  }
                  get {
                    _$registrar.access(propertyIndex: 1)
                    return _index
                  }
              }

              fileprivate var _index: Int = 0
            }

            private nonisolated let _$observationRegistrar: Observation.ObservableSnapshotRegistrar<Snapshot> = .init(propertyCount: 2) {
              Snapshot(_$registrar: $0)
            }

            private func __macro_local_12makeSnapshotfMu_() -> Snapshot {
              var snapshot = Snapshot(_$registrar: _$observationRegistrar.registrar)
              snapshot._name = _name
              snapshot._index = _index
              return snapshot
            }

            internal func invalidateSnapshot(propertyIndex: Int) {
              _$observationRegistrar.invalidate(propertyIndex: propertyIndex, in: self) {
                  $0.__macro_local_12makeSnapshotfMu_()
              }
            }

            var snapshot: Snapshot {
              get async {
                _$observationRegistrar.refresh {
                    __macro_local_12makeSnapshotfMu_()
                }
                return __macro_local_12makeSnapshotfMu_()
              }
            }

            nonisolated var latestSnapshot: Snapshot {
              _$observationRegistrar.latest
            }
        }

        extension MyActor: nonisolated Observation.Observable {
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // The snapshot has the access level of its actor, and each of its properties
  // that of the actor's property: a setter's level is left out, and `private`
  // becomes `fileprivate`.
  @Test
  func observableOnSnapshotSourceActorFollowsAccessLevels() {
    assertMacroExpansion(
      #"""
      @Observable
      public actor Shelf: SnapshotSource {
        public var name = "a"
        public private(set) var count = 0
        private var secret = 1
      }
      """#,
      expandedSource: #"""
        public actor Shelf: SnapshotSource {
          public var name {
              @storageRestrictions(initializes: _name)
              init(initialValue) {
                _name = initialValue
              }
              get {
                access(propertyIndex: 0)
                return _name
              }
              set {
                guard shouldNotifyObservers(_name, newValue) else {
                  _name = newValue
                  return
                }
                invalidateSnapshot(propertyIndex: 0)
                withMutation(propertyIndex: 0) {
                    _name = newValue
                  }
              }
              _modify {
                invalidateSnapshot(propertyIndex: 0)
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                  _$observationRegistrar.didSet(propertyIndex: 0)
                }
                yield &_name
              }
          }
          private  var _name  = "a"
          public private(set) var count {
              @storageRestrictions(initializes: _count)
              init(initialValue) {
                _count = initialValue
              }
              get {
                access(propertyIndex: 1)
                return _count
              }
              set {
                guard shouldNotifyObservers(_count, newValue) else {
                  _count = newValue
                  return
                }
                invalidateSnapshot(propertyIndex: 1)
                withMutation(propertyIndex: 1) {
                    _count = newValue
                  }
              }
              _modify {
                invalidateSnapshot(propertyIndex: 1)
                access(propertyIndex: 1)
                _$observationRegistrar.willSet(propertyIndex: 1)
                defer {
                  _$observationRegistrar.didSet(propertyIndex: 1)
                }
                yield &_count
              }
          }
          private  var _count  = 0
          private var secret {
              @storageRestrictions(initializes: _secret)
              init(initialValue) {
                _secret = initialValue
              }
              get {
                access(propertyIndex: 2)
                return _secret
              }
              set {
                guard shouldNotifyObservers(_secret, newValue) else {
                  _secret = newValue
                  return
                }
                invalidateSnapshot(propertyIndex: 2)
                withMutation(propertyIndex: 2) {
                    _secret = newValue
                  }
              }
              _modify {
                invalidateSnapshot(propertyIndex: 2)
                access(propertyIndex: 2)
                _$observationRegistrar.willSet(propertyIndex: 2)
                defer {
                  _$observationRegistrar.didSet(propertyIndex: 2)
                }
                yield &_secret
              }
          }
          private  var _secret  = 1

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

            public struct Snapshot: Sendable {
              var _$registrar: Observation.ObservationRegistrar
              public var name {
                  @storageRestrictions(initializes: _name)
                  init(initialValue) {
                    _name = initialValue
                  }
                  get {
                    _$registrar.access(propertyIndex: 0)
                    return _name
                  }
              }

              fileprivate var _name = "a"
              public var count {
                  @storageRestrictions(initializes: _count)
                  init(initialValue) {
                    _count = initialValue
                  }
                  get {
                    _$registrar.access(propertyIndex: 1)
                    return _count
                  }
              }

              fileprivate var _count = 0
              fileprivate var secret {
                  @storageRestrictions(initializes: _secret)
                  init(initialValue) {
                    _secret = initialValue
                  }
                  get {
                    _$registrar.access(propertyIndex: 2)
                    return _secret
                  }
              }

              fileprivate var _secret = 1
            }

            private nonisolated let _$observationRegistrar: Observation.ObservableSnapshotRegistrar<Snapshot> = .init(propertyCount: 3) {
              Snapshot(_$registrar: $0)
            }

            private func __macro_local_12makeSnapshotfMu_() -> Snapshot {
              var snapshot = Snapshot(_$registrar: _$observationRegistrar.registrar)
              snapshot._name = _name
              snapshot._count = _count
              snapshot._secret = _secret
              return snapshot
            }

            internal func invalidateSnapshot(propertyIndex: Int) {
              _$observationRegistrar.invalidate(propertyIndex: propertyIndex, in: self) {
                  $0.__macro_local_12makeSnapshotfMu_()
              }
            }

            public var snapshot: Snapshot {
              get async {
                _$observationRegistrar.refresh {
                    __macro_local_12makeSnapshotfMu_()
                }
                return __macro_local_12makeSnapshotfMu_()
              }
            }

            public nonisolated var latestSnapshot: Snapshot {
              _$observationRegistrar.latest
            }
        }

        extension Shelf: nonisolated Observation.Observable {
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // A property with neither a default value nor an optional type can't be in
  // the initial snapshot.
  @Test
  func observableOnSnapshotSourceActorWithoutDefaultError() {
    assertMacroExpansion(
      #"""
      @Observable
      actor MyActor: SnapshotSource {
        var index: Int
      }
      """#,
      expandedSource: #"""
        actor MyActor: SnapshotSource {
          var index: Int {
              @storageRestrictions(initializes: _index)
              init(initialValue) {
                _index = initialValue
              }
              get {
                access(propertyIndex: 0)
                return _index
              }
              set {
                guard shouldNotifyObservers(_index, newValue) else {
                  _index = newValue
                  return
                }
                invalidateSnapshot(propertyIndex: 0)
                withMutation(propertyIndex: 0) {
                    _index = newValue
                  }
              }
              _modify {
                invalidateSnapshot(propertyIndex: 0)
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                  _$observationRegistrar.didSet(propertyIndex: 0)
                }
                yield &_index
              }
          }
          private  var _index: Int

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

        extension MyActor: nonisolated Observation.Observable {
        }
        """#,
      diagnostics: [
        DiagnosticSpec(message: "'@Observable' requires each property of a 'SnapshotSource' to have a default value (or be optional) so an initial snapshot can be created; add one or mark it '@ObservationIgnored'", line: 3, column: 3)
      ],
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  @Test
  func observableOnSnapshotSourceDistributedActorError() {
    assertMacroExpansion(
      #"""
      @Observable
      distributed actor MyActor: SnapshotSource {
        var index = 0
      }
      """#,
      expandedSource: #"""
        distributed actor MyActor: SnapshotSource {
          var index {
              @storageRestrictions(initializes: _index)
              init(initialValue) {
                _index = initialValue
              }
              get {
                access(propertyIndex: 0)
                return _index
              }
              set {
                guard shouldNotifyObservers(_index, newValue) else {
                  _index = newValue
                  return
                }
                invalidateSnapshot(propertyIndex: 0)
                withMutation(propertyIndex: 0) {
                    _index = newValue
                  }
              }
              _modify {
                invalidateSnapshot(propertyIndex: 0)
                access(propertyIndex: 0)
                _$observationRegistrar.willSet(propertyIndex: 0)
                defer {
                  _$observationRegistrar.didSet(propertyIndex: 0)
                }
                yield &_index
              }
          }
          private  var _index  = 0

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

        extension MyActor: nonisolated Observation.Observable {
        }
        """#,
      diagnostics: [
        DiagnosticSpec(message: "'@Observable' cannot synthesize 'SnapshotSource' for distributed actor type 'MyActor'", line: 1, column: 1)
      ],
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // Only an actor can conform to `SnapshotSource`, so the name on another
  // kind of type is not acted on.
  @Test
  func observableOnClassNamingSnapshotSourceIsUnchanged() {
    assertMacroExpansion(
      #"""
      @Observable
      class MyClass: SnapshotSource {
        var index = 0
      }
      """#,
      expandedSource: #"""
        class MyClass: SnapshotSource {
          var index {
              @storageRestrictions(initializes: _index)
              init(initialValue) {
                _index = initialValue
              }
              get {
                #if $Embedded
                access(propertyIndex: 0)
                #else
                access(keyPath: \.index, propertyIndex: 0)
                #endif
                return _index
              }
              set {
                guard shouldNotifyObservers(_index, newValue) else {
                  _index = newValue
                  return
                }
                #if $Embedded
                withMutation(propertyIndex: 0) {
                  _index = newValue
                }
                #else
                withMutation(keyPath: \.index, propertyIndex: 0) {
                  _index = newValue
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
                access(keyPath: \.index, propertyIndex: 0)
                _$observationRegistrar.willSet(self, keyPath: \.index, propertyIndex: 0)
                defer {
                    _$observationRegistrar.didSet(self, keyPath: \.index, propertyIndex: 0)
                }
                #endif
                yield &_index
              }
          }
          private  var _index  = 0

            private let _$observationRegistrar = Observation.ObservationRegistrar()

            #if !$Embedded
            internal nonisolated func access<__macro_local_6MemberfMu_>(
              keyPath: KeyPath<MyClass, __macro_local_6MemberfMu_>
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath)
            }
            #endif

            #if !$Embedded
            internal nonisolated func withMutation<__macro_local_6MemberfMu0_, __macro_local_14MutationResultfMu_>(
              keyPath: KeyPath<MyClass, __macro_local_6MemberfMu0_>,
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
              _$observationRegistrar.access(propertyIndex: propertyIndex)
            }
            #else
            internal nonisolated func access<__macro_local_6MemberfMu5_>(
              keyPath: KeyPath<MyClass, __macro_local_6MemberfMu5_>,
              propertyIndex: Int
            ) {
              _$observationRegistrar.access(self, keyPath: keyPath, propertyIndex: propertyIndex)
            }
            #endif

            #if $Embedded
            internal nonisolated func withMutation<__macro_local_14MutationResultfMu1_, __macro_local_7FailurefMu_: Error>(
              propertyIndex: Int,
              _ mutation: () throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_
            ) throws(__macro_local_7FailurefMu_) -> __macro_local_14MutationResultfMu1_ {
              try _$observationRegistrar.withMutation(propertyIndex: propertyIndex, mutation)
            }
            #else
            internal nonisolated func withMutation<__macro_local_6MemberfMu6_, __macro_local_14MutationResultfMu0_>(
              keyPath: KeyPath<MyClass, __macro_local_6MemberfMu6_>,
              propertyIndex: Int,
              _ mutation: () throws -> __macro_local_14MutationResultfMu0_
            ) rethrows -> __macro_local_14MutationResultfMu0_ {
              try _$observationRegistrar.withMutation(of: self, keyPath: keyPath, propertyIndex: propertyIndex, mutation)
            }
            #endif
        }

        extension MyClass: nonisolated Observation.Observable {
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }
}
#endif
