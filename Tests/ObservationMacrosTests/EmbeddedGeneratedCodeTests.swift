// No `import Foundation`: with `Testing` it pulls in the `_Testing_Foundation`
// overlay, which imports the SDK's Observation and finds this package's
// module of the same name instead.
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

#if canImport(ObservationMacros)
import ObservationMacros

struct EmbeddedGeneratedCodeTests {
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

  // Helper to check that unsafe Embedded tokens don't appear outside guards.
  // Returns nil if clean, or a message describing the problem if found.
  func checkEmbeddedSafety(_ expandedSource: String) -> String? {
    // Tokens that are unsafe under Embedded when they appear outside #if !$Embedded
    let unsafeTokens = ["AnyKeyPath", "PartialKeyPath", "Codable", "Decoder", "Encoder"]
    
    // Patterns: "KeyPath<" is unsafe (bare key path), but "propertyIndex:" is the safe Embedded form
    let unsafeKeyPathPattern = "KeyPath<"
    
    let lines = expandedSource.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var inEmbeddedGuard = false
    var guardDepth = 0
    
    for (lineNum, line) in lines.enumerated() {
      let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
      
      // Track #if directives to know if we're inside a non-Embedded guard
      if trimmed.hasPrefix("#if $Embedded") {
        guardDepth += 1
      } else if trimmed.hasPrefix("#if !$Embedded") {
        inEmbeddedGuard = true
        guardDepth += 1
      } else if trimmed.hasPrefix("#else") && guardDepth > 0 {
        // #else toggles between Embedded and non-Embedded branch
        inEmbeddedGuard = !inEmbeddedGuard
      } else if trimmed.hasPrefix("#endif") && guardDepth > 0 {
        guardDepth -= 1
        if guardDepth == 0 {
          inEmbeddedGuard = false
        }
      }
      
      // Check for unsafe tokens outside a non-Embedded guard
      // (i.e., in Embedded-visible code)
      if !inEmbeddedGuard {
        for token in unsafeTokens {
          if line.contains(token) {
            return "Found '\(token)' on line \(lineNum + 1) outside #if !$Embedded guard: \(line)"
          }
        }
        
        // Check for bare KeyPath< (unsafe) but not preceded by propertyIndex:
        // This is a heuristic: we look for "KeyPath<" but not in contexts like "propertyIndex: Int"
        if line.contains(unsafeKeyPathPattern) && !line.contains("propertyIndex:") {
          return "Found bare 'KeyPath<' on line \(lineNum + 1) outside #if !$Embedded guard: \(line)"
        }
      }
    }
    
    return nil
  }

  // MARK: - Embedded Safety Tests

  @Test
  func simplePropertyNoUnsafeTokensOutsideEmbeddedGuard() {
    let sourceCode = #"""
      @Observable
      final class SimpleClass {
        var value = 0
      }
      """#
    
    let expectedExpansion = #"""
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
      """#
    
    // First verify the exact expansion (R2: byte-identical non-Embedded output)
    assertMacroExpansion(
      sourceCode,
      expandedSource: expectedExpansion,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
    
    // Also verify the safety of the expansion (no unsafe tokens outside guards)
    // This is a separate check from exact expansion because it applies to any
    // valid @Observable macro output, not just our expected template.
    if let problem = checkEmbeddedSafety(expectedExpansion) {
      #expect(Bool(false), "Embedded safety check failed: \(problem)")
    }
  }

  @Test
  func derivedPropertyNoUnsafeTokensOutsideEmbeddedGuard() {
    let expectedExpansion = #"""
      final class Doubler {
        var a = 0
        var twice: Int {
            return _twice.compute(input: {
                    a
                }, update: {
                    $0 * 2
                })
        }

        private let _twice = Observation.ObservationDerivedValue<Int>()
      }
      """#
    assertMacroExpansion(
      #"""
      final class Doubler {
        var a = 0
        @ObservationDerived var twice: Int {
          input { a }
          update { $0 * 2 }
        }
      }
      """#,
      expandedSource: expectedExpansion,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
    if let problem = checkEmbeddedSafety(expectedExpansion) {
      #expect(Bool(false), "Embedded safety check failed: \(problem)")
    }
  }

  // Multi-statement blocks are spliced in unchanged.
  @Test
  func derivedPropertyBodyKeepsBlocks() {
    assertMacroExpansion(
      #"""
      final class Signal {
        var a: Float = 0
        var b: Float = 0
        @ObservationDerived
        var rms: Float {
          input {
            (a, b)
          }
          update {
            let sum = $0.0 * $0.0 + $0.1 * $0.1
            return (sum / 2).squareRoot()
          }
        }
      }
      """#,
      expandedSource: #"""
        final class Signal {
          var a: Float = 0
          var b: Float = 0
          var rms: Float {
              return _rms.compute(input: {
                    (a, b)
                  }, update: {
                    let sum = $0.0 * $0.0 + $0.1 * $0.1
                    return (sum / 2).squareRoot()
                  })
          }

          private let _rms = Observation.ObservationDerivedValue<Float>()
        }
        """#,
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // A body other than `input { ... } update { ... }` is rejected rather than
  // cached some other way.
  @Test(arguments: [
    "_twice.compute { a } update: { $0 * 2 }",
    "input { a }",
    "update { $0 * 2 }\n    input { a }",
    "input { a }\n    update { $0 * 2 }\n    input { a }",
    "input(read)\n    update { $0 * 2 }",
    "input { a } other: { a }\n    update { $0 * 2 }",
    "self.input { a }\n    update { $0 * 2 }",
  ])
  func derivedPropertyWithOtherBodyIsDiagnosed(body: String) {
    assertMacroExpansion(
      """
      final class Doubler {
        @ObservationDerived var twice: Int {
          \(body)
        }
      }
      """,
      expandedSource: """
        final class Doubler {
          var twice: Int {
            \(body)
          }
        }
        """,
      diagnostics: [
        DiagnosticSpec(message: "'@ObservationDerived' property 'twice' must have a body of the form 'input { ... } update { ... }'", line: 2, column: 27)
      ],
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }

  // So is a getter written out with `get`.
  @Test
  func derivedPropertyWithExplicitGetterIsDiagnosed() {
    assertMacroExpansion(
      #"""
      final class Doubler {
        @ObservationDerived var twice: Int {
          get {
            input { 1 }
            update { $0 * 2 }
          }
        }
      }
      """#,
      expandedSource: #"""
        final class Doubler {
          var twice: Int {
            get {
              input { 1 }
              update { $0 * 2 }
            }
          }
        }
        """#,
      diagnostics: [
        DiagnosticSpec(message: "'@ObservationDerived' property 'twice' must have a body of the form 'input { ... } update { ... }'", line: 2, column: 27)
      ],
      macroSpecs: macros,
      failureHandler: expectNoMacroFailure
    )
  }
}

#endif
