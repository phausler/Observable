//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftSyntaxBuilder

// The synthesis `@Observable` adds to an actor that conforms to
// `SnapshotSource`: a `Snapshot` structure mirroring the actor's observed
// stored properties, whose own properties register their accesses with a
// registrar of the snapshot's, and the two members `SnapshotSource` requires
// of it (see `ObservableSnapshotRegistrar`). The rest, scheduling and
// publishing the refresh, `SnapshotSource` implements. The properties' storage
// is `@Observable`'s own `_name` backing, which `_$makeSnapshot()` reads; their
// accessors invalidate the snapshot on write (see `ObservationTrackedMacro`).

extension ObservableMacro {
  static let snapshotInvalidateFunctionName = "invalidateSnapshot"
  static let snapshotRegistrarParameterName = "_$registrar"

  static var qualifiedSnapshotRegistrarTypeName: String {
    "\(moduleName).ObservableSnapshotRegistrar"
  }

  // One line of generated code for a snapshotted property (or `#if`
  // directive), rendered both as the `Snapshot` member and as the assignment
  // `_$makeSnapshot()` makes.
  struct SnapshotLine {
    var declaration: String
    var assignment: String
  }

  // Whether writes to `property` reach the snapshot: it is one `@Observable`
  // tracks, so not `@ObservationIgnored`, which leaves a property out of the
  // snapshot of a `SnapshotSource` as well.
  static func isSnapshotted(_ property: VariableDeclSyntax) -> Bool {
    property.isValidForObservation
      && !property.hasMacroApplication(ignoredMacroName)
  }

  // The access level of a snapshot's property: the one its actor's property is
  // declared with, so a snapshot exposes no more than the actor does. The
  // snapshot structure has the actor's own access level, which caps it, as it
  // does a member declared with a greater one. A setter's level is left out,
  // since a snapshot has no setter, and `private` becomes `fileprivate`: the
  // snapshot is a nested type, so a `private` property would be out of sight
  // of the code of the actor's file that sees the actor's own.
  static func snapshotAccess(of property: VariableDeclSyntax) -> String {
    for modifier in property.modifiers where modifier.detail == nil {
      switch modifier.name.tokenKind {
      case .keyword(.public): return "public "
      case .keyword(.package): return "package "
      case .keyword(.internal): return "internal "
      case .keyword(.fileprivate), .keyword(.private): return "fileprivate "
      default: break
      }
    }
    return ""
  }

  // The snapshot's property declarations, preserving `#if` structure, and
  // the property indices they use. Nil after diagnosing if a property can't be
  // snapshotted.
  static func snapshotLines(
    of members: MemberBlockItemListSyntax,
    in declaration: some DeclGroupSyntax,
    isObjectResolution: Bool,
    propertyIndices: inout [Int],
    context: some MacroExpansionContext
  ) -> [SnapshotLine]? {
    var lines = [SnapshotLine]()
    var succeeded = true
    for member in members {
      if let ifConfig = member.decl.as(IfConfigDeclSyntax.self) {
        for clause in ifConfig.clauses {
          var header = clause.poundKeyword.text
          if let condition = clause.condition { header += " " + condition.trimmedDescription }
          lines.append(SnapshotLine(declaration: header, assignment: header))
          if case .decls(let nested)? = clause.elements {
            if let nestedLines = snapshotLines(of: nested, in: declaration, isObjectResolution: isObjectResolution, propertyIndices: &propertyIndices, context: context) {
              lines += nestedLines
            } else {
              succeeded = false
            }
          }
        }
        lines.append(SnapshotLine(declaration: "#endif", assignment: "#endif"))
      } else if let property = member.decl.as(VariableDeclSyntax.self), isSnapshotted(property) {
        guard property.bindings.count == 1, let binding = property.bindings.first,
              let name = property.identifier?.trimmed.text else {
          context.diagnose(Diagnostic(node: property, message: ObservationDiagnostic(
            message: "'@Observable' requires each property of a 'SnapshotSource' to be declared separately with a simple name; split the declaration or mark it '@\(ignoredMacroName)'",
            domain: "Observation", id: .invalidApplication)))
          succeeded = false
          continue
        }
        let type = binding.typeAnnotation?.type
        let isOptional = type.map {
          $0.is(OptionalTypeSyntax.self)
            || $0.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
            || $0.as(IdentifierTypeSyntax.self)?.name.text == "Optional"
        } ?? false
        // The snapshot starts out holding the initial values, so each
        // property needs one, or to be optional.
        if binding.initializer == nil && !isOptional {
          context.diagnose(Diagnostic(node: property, message: ObservationDiagnostic(
            message: "'@Observable' requires each property of a 'SnapshotSource' to have a default value (or be optional) so an initial snapshot can be created; add one or mark it '@\(ignoredMacroName)'",
            domain: "Observation", id: .missingInitializer)))
          succeeded = false
          continue
        }
        // The same property index the actor's accessor uses. Without one (a
        // property inside `#if`) the actor's own accessors fail the build.
        let group = property.macroApplication(trackedMacroName)?.observationGroup
        let propertyIndex = declaration.observationPropertyIndex(of: property, isObjectResolution: isObjectResolution, group: group)
        if let propertyIndex { propertyIndices.append(propertyIndex) }
        let attribute = propertyIndex.map { "@\(trackedMacroName)(propertyIndex: \($0)) " } ?? "@\(trackedMacroName) "
        // The declaration repeats the property's own type annotation and
        // initializer, so one with only an initializer (`var name = "test"`)
        // gets the same inferred type.
        var line = "\(attribute)\(snapshotAccess(of: property))var \(name)"
        if let type { line += ": \(type.trimmedDescription)" }
        if let initializer = binding.initializer { line += " \(initializer.trimmedDescription)" }
        lines.append(SnapshotLine(declaration: line, assignment: "snapshot._\(name) = _\(name)"))
      }
    }
    return succeeded ? lines : nil
  }

  // The members of a `SnapshotSource` actor beyond `@Observable`'s own. Nil
  // after diagnosing if a property can't be snapshotted.
  static func snapshotMembers(of declaration: some DeclGroupSyntax, node: AttributeSyntax, in context: some MacroExpansionContext) -> [DeclSyntax]? {
    let access = declaration.modifiers.lazy.compactMap { modifier -> String? in
      switch modifier.name.tokenKind {
      case .keyword(.public): "public "
      case .keyword(.package): "package "
      default: nil
      }
    }.first ?? ""

    var propertyIndices = [Int]()
    guard let lines = snapshotLines(
      of: declaration.memberBlock.members,
      in: declaration,
      isObjectResolution: node.observationResolution == true,
      propertyIndices: &propertyIndices,
      context: context
    ) else {
      return nil
    }
    let declarations = lines.map(\.declaration).joined(separator: "\n")
    let assignments = lines.map(\.assignment).joined(separator: "\n")
    let propertyCount = (propertyIndices.max() ?? -1) + 1
    // Only these members refer to the maker, so it needs no name the
    // accessors, which another expansion makes, could use.
    let registrar = registrarVariableName
    let makeSnapshot = context.makeUniqueName("makeSnapshot")

    return [
      """
      \(raw: access)struct Snapshot: Sendable {
        var \(raw: snapshotRegistrarParameterName): \(raw: qualifiedRegistrarTypeName)
        \(raw: declarations)
      }
      """,
      // The actor's registrar as well as the snapshot's, which it forwards the
      // actor's own observation to. Annotated: the conformance is declared on
      // the actor itself, so inferring this type from its initializer would
      // recurse into the inference of `Snapshot`.
      """
      @\(raw: ignoredMacroName) private nonisolated let \(raw: registrar): \(raw: qualifiedSnapshotRegistrarTypeName)<Snapshot> = .init(propertyCount: \(raw: propertyCount)) {
        Snapshot(\(raw: snapshotRegistrarParameterName): $0)
      }
      """,
      """
      private func \(makeSnapshot)() -> Snapshot {
        var snapshot = Snapshot(\(raw: snapshotRegistrarParameterName): \(raw: registrar).registrar)
        \(raw: assignments)
        return snapshot
      }
      """,
      // Only the clean -> dirty transition schedules a refresh on this actor.
      """
      internal func \(raw: snapshotInvalidateFunctionName)(propertyIndex: Int) {
        \(raw: registrar).invalidate(propertyIndex: propertyIndex, in: self) { $0.\(makeSnapshot)() }
      }
      """,
      """
      \(raw: access)var snapshot: Snapshot {
        get async {
          \(raw: registrar).refresh { \(makeSnapshot)() }
          return \(makeSnapshot)()
        }
      }
      """,
      """
      \(raw: access)nonisolated var latestSnapshot: Snapshot {
        \(raw: registrar).latest
      }
      """,
    ]
  }
}

// A property of a `SnapshotSource`'s `Snapshot` is tracked by the same
// `@ObservationTracked` as the actor's own, which tells them apart by the type
// it is a member of: the `Snapshot` structure of an actor that conforms to
// `SnapshotSource`. Such a property reads the value stored in `_name`, after
// registering an access to it with the snapshot's registrar. The snapshot is
// only ever read, so there is no setter.
extension ObservationTrackedMacro {
  static func isSnapshotProperty(in context: some MacroExpansionContext) -> Bool {
    // The innermost lexical context is all that is known of code a macro
    // generated: the actor that declares the structure is not in the chain.
    guard let snapshot = context.lexicalContext.first?.as(StructDeclSyntax.self),
          snapshot.name.text == "Snapshot",
          !snapshot.isNoncopyable,
          snapshot.inheritanceClause?.inheritedTypes.contains(where: { $0.type.trimmedDescription == "Sendable" }) == true else {
      return false
    }
    return true
  }

  static func snapshotAccessors(identifier: TokenSyntax, propertyIndex: Int?) -> [AccessorDeclSyntax] {
    let access = propertyIndex.map { "\(ObservableMacro.snapshotRegistrarParameterName).access(propertyIndex: \($0))\n" } ?? ""
    return [
      """
      @storageRestrictions(initializes: _\(identifier))
      init(initialValue) {
        _\(identifier) = initialValue
      }
      """,
      """
      get {
        \(raw: access)return _\(identifier)
      }
      """,
    ]
  }

  // `fileprivate`, not `private`, for the actor's `_$makeSnapshot()` to
  // assign it.
  static func snapshotPeers(of property: VariableDeclSyntax) -> [DeclSyntax] {
    guard property.bindings.count == 1,
          let binding = property.bindings.first,
          let identifier = property.identifier?.trimmed else {
      return []
    }
    let backing = binding
      .with(\.pattern, PatternSyntax(IdentifierPatternSyntax(identifier: .identifier("_" + identifier.text))))
      .trimmed
    return ["fileprivate var \(backing)"]
  }
}
