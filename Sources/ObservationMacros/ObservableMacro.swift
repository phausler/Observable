//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftSyntaxBuilder

public struct ObservableMacro {
  static let moduleName = "Observation"

  static let conformanceName = "Observable"
  static var qualifiedConformanceName: String {
    return "\(moduleName).\(conformanceName)"
  }

  static var observableConformanceType: TypeSyntax {
    "\(raw: qualifiedConformanceName)"
  }

  static let registrarTypeName = "ObservationRegistrar"
  static var qualifiedRegistrarTypeName: String {
    return "\(moduleName).\(registrarTypeName)"
  }
  
  static let trackedMacroName = "ObservationTracked"
  static let ignoredMacroName = "ObservationIgnored"

  static let registrarVariableName = "_$observationRegistrar"
  
  static func registrarVariable(_ observableType: TokenSyntax, context: some MacroExpansionContext) -> DeclSyntax {
    return
      """
      @\(raw: ignoredMacroName) private let \(raw: registrarVariableName) = \(raw: qualifiedRegistrarTypeName)()
      """
  }
  
  static func accessFunction(_ observableType: TokenSyntax, context: some MacroExpansionContext) -> DeclSyntax {
    let memberGeneric = context.makeUniqueName("Member")
    return
      """
      internal nonisolated func access<\(memberGeneric)>(
        keyPath: KeyPath<\(observableType), \(memberGeneric)>
      ) {
        \(raw: registrarVariableName).access(self, keyPath: keyPath)
      }
      """
  }
  
  static func withMutationFunction(_ observableType: TokenSyntax, context: some MacroExpansionContext) -> DeclSyntax {
    let memberGeneric = context.makeUniqueName("Member")
    let mutationGeneric = context.makeUniqueName("MutationResult")
    return
      """
      internal nonisolated func withMutation<\(memberGeneric), \(mutationGeneric)>(
        keyPath: KeyPath<\(observableType), \(memberGeneric)>,
        _ mutation: () throws -> \(mutationGeneric)
      ) rethrows -> \(mutationGeneric) {
        try \(raw: registrarVariableName).withMutation(of: self, keyPath: keyPath, mutation)
      }
      """
  }

  // The entry points of the property index-tagged accessors (`property index` is the property's
  // ordinal among its class's observed properties). When the class
  // implements its own `access(keyPath:)` or `withMutation(keyPath:_:)`,
  // these forward to it instead, so its customization still runs.
  static func accessPropertyIndexFunction(_ observableType: TokenSyntax, forwarding: Bool, context: some MacroExpansionContext) -> DeclSyntax {
    let memberGeneric = context.makeUniqueName("Member")
    let call = forwarding
      ? "access(keyPath: keyPath)"
      : "\(registrarVariableName).access(self, keyPath: keyPath, propertyIndex: propertyIndex)"
    return
      """
      internal nonisolated func access<\(memberGeneric)>(
        keyPath: KeyPath<\(observableType), \(memberGeneric)>,
        propertyIndex: Int
      ) {
        \(raw: call)
      }
      """
  }

  static func withMutationPropertyIndexFunction(_ observableType: TokenSyntax, forwarding: Bool, context: some MacroExpansionContext) -> DeclSyntax {
    let memberGeneric = context.makeUniqueName("Member")
    let mutationGeneric = context.makeUniqueName("MutationResult")
    let call = forwarding
      ? "try withMutation(keyPath: keyPath, mutation)"
      : "try \(registrarVariableName).withMutation(of: self, keyPath: keyPath, propertyIndex: propertyIndex, mutation)"
    return
      """
      internal nonisolated func withMutation<\(memberGeneric), \(mutationGeneric)>(
        keyPath: KeyPath<\(observableType), \(memberGeneric)>,
        propertyIndex: Int,
        _ mutation: () throws -> \(mutationGeneric)
      ) rethrows -> \(mutationGeneric) {
        \(raw: call)
      }
      """
  }

  // Embedded Swift cannot form key paths, and its registrar's entry points
  // take only the property index, so under Embedded these replace the members above.
  // A class's own `access(keyPath:)` or `withMutation(keyPath:_:)` cannot be
  // forwarded to there, so a class customizing one implements these too, or
  // its Embedded build fails (see `embeddedForwardingError`).
  static func embeddedAccessPropertyIndexFunction(_ observableType: TokenSyntax, context: some MacroExpansionContext) -> DeclSyntax {
    return
      """
      internal nonisolated func access(propertyIndex: Int) {
        \(raw: registrarVariableName).access(propertyIndex: propertyIndex)
      }
      """
  }

  static func embeddedWithMutationPropertyIndexFunction(_ observableType: TokenSyntax, isolated: Bool = false, context: some MacroExpansionContext) -> DeclSyntax {
    let mutationGeneric = context.makeUniqueName("MutationResult")
    let failureGeneric = context.makeUniqueName("Failure")
    return
      """
      internal \(raw: isolated ? "" : "nonisolated ")func withMutation<\(mutationGeneric), \(failureGeneric): Error>(
        propertyIndex: Int,
        _ mutation: () throws(\(failureGeneric)) -> \(mutationGeneric)
      ) throws(\(failureGeneric)) -> \(mutationGeneric) {
        try \(raw: registrarVariableName).withMutation(propertyIndex: propertyIndex, mutation)
      }
      """
  }

  // Under Embedded in place of a member above, when the class customizes
  // `customized` but not `replacement`: rather than bypass the customization,
  // the build fails.
  static func embeddedForwardingError(_ observableType: TokenSyntax, customized: String, replacement: String) -> DeclSyntax {
    return
      """
      #error("'@Observable' cannot forward to '\(raw: customized)' of '\(raw: observableType.text)' in Embedded Swift, which has no key paths; implement '\(raw: replacement)' too")
      """
  }

  // The members of a noncopyable struct, which has no key paths in any
  // build: its accessors make only the property index-only calls, the same under
  // Embedded as not. `withMutation(propertyIndex:_:)` is mutating and passes the
  // struct to `mutation` inout: a setter's closure could not otherwise
  // mutate the struct while a method borrows it.
  static func noncopyableAccessPropertyIndexFunction(_ observableType: TokenSyntax, isolated: Bool = false, context: some MacroExpansionContext) -> DeclSyntax {
    return
      """
      internal \(raw: isolated ? "" : "nonisolated ")func access(propertyIndex: Int) {
        \(raw: registrarVariableName).access(propertyIndex: propertyIndex)
      }
      """
  }

  static func noncopyableWithMutationPropertyIndexFunction(_ observableType: TokenSyntax, context: some MacroExpansionContext) -> DeclSyntax {
    let mutationGeneric = context.makeUniqueName("MutationResult")
    let failureGeneric = context.makeUniqueName("Failure")
    return
      """
      internal nonisolated mutating func withMutation<\(mutationGeneric), \(failureGeneric): Error>(
        propertyIndex: Int,
        _ mutation: (inout \(observableType)) throws(\(failureGeneric)) -> \(mutationGeneric)
      ) throws(\(failureGeneric)) -> \(mutationGeneric) {
        \(raw: registrarVariableName).willSet(propertyIndex: propertyIndex)
        defer {
          \(raw: registrarVariableName).didSet(propertyIndex: propertyIndex)
        }
        return try mutation(&self)
      }
      """
  }

  // `embedded` under Embedded, `other` otherwise; nil when neither is needed.
  static func embeddedConditional(_ embedded: DeclSyntax?, else other: DeclSyntax?) -> DeclSyntax? {
    switch (embedded, other) {
    case (let embedded?, let other?):
      return
        """
        #if $Embedded
        \(embedded)
        #else
        \(other)
        #endif
        """
    case (let embedded?, nil):
      return
        """
        #if $Embedded
        \(embedded)
        #endif
        """
    case (nil, let other?):
      return
        """
        #if !$Embedded
        \(other)
        #endif
        """
    case (nil, nil):
      return nil
    }
  }
  
  static func shouldNotifyObserversNonEquatableFunction(_ observableType: TokenSyntax, final: Bool = true, context: some MacroExpansionContext) -> DeclSyntax {
    let memberGeneric = context.makeUniqueName("Member")
    return
      """
       private nonisolated \(raw: final ? "final " : "")func shouldNotifyObservers<\(memberGeneric)>(_ lhs: \(memberGeneric), _ rhs: \(memberGeneric)) -> Bool { true }
      """
  }
  
  static func shouldNotifyObserversEquatableFunction(_ observableType: TokenSyntax, final: Bool = true, context: some MacroExpansionContext) -> DeclSyntax {
    let memberGeneric = context.makeUniqueName("Member")
    return
      """
      private nonisolated \(raw: final ? "final " : "")func shouldNotifyObservers<\(memberGeneric): Equatable>(_ lhs: \(memberGeneric), _ rhs: \(memberGeneric)) -> Bool { lhs != rhs }
      """
  }
  
  static func shouldNotifyObserversNonEquatableObjectFunction(_ observableType: TokenSyntax, final: Bool = true, context: some MacroExpansionContext) -> DeclSyntax {
    let memberGeneric = context.makeUniqueName("Member")
    return
      """
       private nonisolated \(raw: final ? "final " : "")func shouldNotifyObservers<\(memberGeneric): AnyObject>(_ lhs: \(memberGeneric), _ rhs: \(memberGeneric)) -> Bool { lhs !== rhs }
      """
  }

  static func shouldNotifyObserversEquatableObjectFunction(_ observableType: TokenSyntax, final: Bool = true, context: some MacroExpansionContext) -> DeclSyntax {
    let memberGeneric = context.makeUniqueName("Member")
    return
      """
      private nonisolated \(raw: final ? "final " : "")func shouldNotifyObservers<\(memberGeneric): Equatable & AnyObject>(_ lhs: \(memberGeneric), _ rhs: \(memberGeneric)) -> Bool { lhs != rhs }
      """
  }

  static var ignoredAttribute: AttributeSyntax {
    AttributeSyntax(
      leadingTrivia: .space,
      atSign: .atSignToken(),
      attributeName: IdentifierTypeSyntax(name: .identifier(ignoredMacroName)),
      trailingTrivia: .space
    )
  }

  static var trackedAttribute: AttributeSyntax {
    AttributeSyntax(
      leadingTrivia: .space,
      atSign: .atSignToken(),
      attributeName: IdentifierTypeSyntax(name: .identifier(trackedMacroName)),
      trailingTrivia: .space
    )
  }

  // `@ObservationTracked(propertyIndex:)` for `property`, with `representative:` when
  // another property's key path stands for the property index (see `representative(ofPropertyIndex:for:isObjectResolution:)`).
  static func trackedAttribute(for property: VariableDeclSyntax, in declaration: some DeclGroupSyntax, isObjectResolution: Bool, group: Int?) throws -> AttributeSyntax? {
    guard let propertyIndex = declaration.observationPropertyIndex(of: property, isObjectResolution: isObjectResolution, group: group) else {
      return nil
    }
    if let representative = try declaration.representative(ofPropertyIndex: propertyIndex, for: property, isObjectResolution: isObjectResolution)?.identifier?.trimmed.text,
       representative != property.identifier?.trimmed.text {
      return "@\(raw: trackedMacroName)(propertyIndex: \(raw: propertyIndex), representative: \(literal: representative))"
    }
    return "@\(raw: trackedMacroName)(propertyIndex: \(raw: propertyIndex))"
  }
}

struct ObservationDiagnostic: DiagnosticMessage {
  enum ID: String {
    case invalidApplication = "invalid type"
    case missingInitializer = "missing initializer"
    case nonLiteralArgument = "non-literal argument"
    case isolationMismatch = "isolation mismatch"
  }
  
  var message: String
  var diagnosticID: MessageID
  var severity: DiagnosticSeverity
  
  init(message: String, diagnosticID: SwiftDiagnostics.MessageID, severity: SwiftDiagnostics.DiagnosticSeverity = .error) {
    self.message = message
    self.diagnosticID = diagnosticID
    self.severity = severity
  }
  
  init(message: String, domain: String, id: ID, severity: SwiftDiagnostics.DiagnosticSeverity = .error) {
    self.message = message
    self.diagnosticID = MessageID(domain: domain, id: id.rawValue)
    self.severity = severity
  }
}

extension DiagnosticsError {
  init<S: SyntaxProtocol>(syntax: S, message: String, domain: String = "Observation", id: ObservationDiagnostic.ID, severity: SwiftDiagnostics.DiagnosticSeverity = .error) {
    self.init(diagnostics: [
      Diagnostic(node: Syntax(syntax), message: ObservationDiagnostic(message: message, domain: domain, id: id, severity: severity))
    ])
  }
}


struct LocalMacroExpansionContext<Context: MacroExpansionContext> {
  var context: Context
}

extension DeclModifierListSyntax {
  func privatePrefixed(_ prefix: String, in context: LocalMacroExpansionContext<some MacroExpansionContext>) -> DeclModifierListSyntax {
    let modifier: DeclModifierSyntax = DeclModifierSyntax(name: "private", trailingTrivia: .space)
    return [modifier] + filter {
      switch $0.name.tokenKind {
      case .keyword(let keyword):
        switch keyword {
        case .fileprivate: fallthrough
        case .private: fallthrough
        case .internal: fallthrough
        case .package: fallthrough
        case .public:
          return false
        default:
          return true
        }
      default:
        return true
      }
    }
  }
  
  init(keyword: Keyword) {
    self.init([DeclModifierSyntax(name: .keyword(keyword))])
  }
}

extension TokenSyntax {
  func privatePrefixed(_ prefix: String, in context: LocalMacroExpansionContext<some MacroExpansionContext>) -> TokenSyntax {
    switch tokenKind {
    case .identifier(let identifier):
      return TokenSyntax(.identifier(prefix + identifier), leadingTrivia: leadingTrivia, trailingTrivia: trailingTrivia, presence: presence)
    default:
      return self
    }
  }
}

extension CodeBlockSyntax {
  func locationAnnotated(in context: LocalMacroExpansionContext<some MacroExpansionContext>) -> CodeBlockSyntax {
    guard let firstStatement = statements.first, let loc = context.context.location(of: firstStatement) else {
      return self
    }
    
    return CodeBlockSyntax(
      leadingTrivia: leadingTrivia,
      leftBrace: leftBrace,
      statements: CodeBlockItemListSyntax {
        "#sourceLocation(file: \(loc.file), line: \(loc.line))"
        statements
        "#sourceLocation()"
      },
      rightBrace: rightBrace,
      trailingTrivia: trailingTrivia
    )
  }
}


extension AccessorDeclSyntax {
  func locationAnnotated(in context: LocalMacroExpansionContext<some MacroExpansionContext>) -> AccessorDeclSyntax {
    return AccessorDeclSyntax(
      leadingTrivia: leadingTrivia,
      attributes: attributes,
      modifiers: modifiers,
      accessorSpecifier: accessorSpecifier,
      parameters: parameters,
      effectSpecifiers: effectSpecifiers,
      body: body?.locationAnnotated(in: context),
      trailingTrivia: trailingTrivia
    )
  }
}

extension AccessorBlockSyntax {
  func locationAnnotated(in context: LocalMacroExpansionContext<some MacroExpansionContext>) -> AccessorBlockSyntax {
    switch accessors {
    case .accessors(let accessorList):
      let remapped = AccessorDeclListSyntax {
        accessorList.map { $0.locationAnnotated(in: context) }
      }
      return AccessorBlockSyntax(accessors: .accessors(remapped))
    case .getter(let codeBlockList):
      return AccessorBlockSyntax(accessors: .getter(codeBlockList))
    }
  }
}

extension PatternBindingListSyntax {
  func privatePrefixed(_ prefix: String, in context: LocalMacroExpansionContext<some MacroExpansionContext>) -> PatternBindingListSyntax {
    var bindings = self.map { $0 }
    for index in 0..<bindings.count {
      let binding = bindings[index]
      if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
        bindings[index] = PatternBindingSyntax(
          leadingTrivia: binding.leadingTrivia,
          pattern: IdentifierPatternSyntax(
            leadingTrivia: identifier.leadingTrivia,
            identifier: identifier.identifier.privatePrefixed(prefix, in: context),
            trailingTrivia: identifier.trailingTrivia
          ),
          typeAnnotation: binding.typeAnnotation,
          initializer: binding.initializer,
          accessorBlock: binding.accessorBlock?.locationAnnotated(in: context),
          trailingComma: binding.trailingComma,
          trailingTrivia: binding.trailingTrivia)
        
      }
    }
    
    return PatternBindingListSyntax(bindings)
  }
}

extension VariableDeclSyntax {
  func privatePrefixed(_ prefix: String, addingAttribute attribute: AttributeSyntax, removingAttribute toRemove: AttributeSyntax, in context: LocalMacroExpansionContext<some MacroExpansionContext>) -> VariableDeclSyntax {
    var newAttribute = attribute
    newAttribute.leadingTrivia = .newline

    let newAttributes = attributes.filter { attribute in
      switch attribute {
      case .attribute(let attr):
        attr.attributeName.identifier != toRemove.attributeName.identifier
      default: true
      }
    } + [.attribute(newAttribute)]

    var newModifiers = modifiers.privatePrefixed(prefix, in: context)
    let hasModifiers = !newModifiers.isEmpty
    if hasModifiers {
      newModifiers.leadingTrivia += .newline
    }

    return VariableDeclSyntax(
      leadingTrivia: leadingTrivia,
      attributes: newAttributes,
      modifiers: newModifiers,
      bindingSpecifier: TokenSyntax(
        bindingSpecifier.tokenKind,
        leadingTrivia: hasModifiers ? .space : .newline,
        trailingTrivia: .space,
        presence: .present
      ),
      bindings: bindings.privatePrefixed(prefix, in: context),
      trailingTrivia: trailingTrivia
    )
  }
  
  var isValidForObservation: Bool {
    !isComputed && isInstance && !isImmutable && identifier != nil
  }
}

extension DeclGroupSyntax {
  // The property index of `property`: its ordinal among this type's observed
  // properties (valid for observation and not ignored), in declaration
  // order. Nil when it is not a direct member, such as one inside `#if`;
  // its accessors then make the key-path-only calls.
  // When resolution is `.object` (isObjectResolution=true), all properties get property index 0.
  // When a group is specified, properties in the same group get the same property index.
  // Otherwise (default), each property gets a unique property index by ordinal.
  func observationPropertyIndex(of property: VariableDeclSyntax, isObjectResolution: Bool = false, group: Int? = nil) -> Int? {
    guard let identifier = property.identifier?.text else { return nil }
    
    // If object resolution, all properties use property index 0
    if isObjectResolution {
      // Just verify this property is valid for observation
      for member in memberBlock.members {
        guard let variable = member.decl.as(VariableDeclSyntax.self),
              variable.isValidForObservation,
              !variable.hasMacroApplication(ObservableMacro.ignoredMacroName) else {
          continue
        }
        if variable.identifier?.text == identifier {
          return 0
        }
      }
      return nil
    }
    
    // If a group is specified, find the first property in that group and use that property index
    if let group = group {
      var targetPropertyIndex: Int? = nil
      var propertyIndexForGroup: Int? = nil
      var currentPropertyIndex = 0
      
      for member in memberBlock.members {
        guard let variable = member.decl.as(VariableDeclSyntax.self),
              variable.isValidForObservation,
              !variable.hasMacroApplication(ObservableMacro.ignoredMacroName) else {
          continue
        }
        
        // Check if this variable is in the same group
        let varGroup = variable.macroApplication(ObservableMacro.trackedMacroName)?.observationGroup
        if varGroup == group {
          if propertyIndexForGroup == nil {
            propertyIndexForGroup = currentPropertyIndex
          }
          if variable.identifier?.text == identifier {
            targetPropertyIndex = propertyIndexForGroup
          }
        }
        
        currentPropertyIndex += 1
      }
      
      return targetPropertyIndex
    }
    
    // Default case: each property gets a unique ordinal property index
    var propertyIndex = 0
    for member in memberBlock.members {
      guard let variable = member.decl.as(VariableDeclSyntax.self),
            variable.isValidForObservation,
            !variable.hasMacroApplication(ObservableMacro.ignoredMacroName) else {
        continue
      }
      if variable.identifier?.text == identifier {
        return propertyIndex
      }
      propertyIndex += 1
    }
    return nil
  }
  
  // The property index of the derived property `property`: the number of
  // observed stored properties plus its position among the derived ones.
  // Derived indices follow the stored ones, so none equals a stored index
  // under any resolution or grouping. Nil when it is not a direct member.
  func observationDerivedPropertyIndex(of property: VariableDeclSyntax) -> Int? {
    guard let identifier = property.identifier?.text else { return nil }
    var stored = 0
    var derivedPosition: Int? = nil
    var derived = 0
    for member in memberBlock.members {
      guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
      if variable.hasMacroApplication(ObservationDerivedMacro.macroName) {
        if derivedPosition == nil && variable.identifier?.text == identifier {
          derivedPosition = derived
        }
        derived += 1
      } else if variable.isValidForObservation,
                !variable.hasMacroApplication(ObservableMacro.ignoredMacroName) {
        stored += 1
      }
    }
    return derivedPosition.map { stored + $0 }
  }

  // The property whose key path every property sharing `propertyIndex` passes, so
  // the registrar sees one key path per property index: the first declared, unless
  // they are isolated differently, when the first nonisolated one, since
  // each property's accessors form the key path in its own isolation, and
  // any of them can form one to a nonisolated property. Throws, at
  // `property`, when none is nonisolated and `property` is isolated
  // otherwise than the first, rather than leave the compiler to reject the
  // key path in its accessors.
  func representative(ofPropertyIndex propertyIndex: Int, for property: VariableDeclSyntax, isObjectResolution: Bool) throws -> VariableDeclSyntax? {
    var sharers = [VariableDeclSyntax]()
    for member in memberBlock.members {
      guard let variable = member.decl.as(VariableDeclSyntax.self),
            variable.isValidForObservation,
            !variable.hasMacroApplication(ObservableMacro.ignoredMacroName) else {
        continue
      }
      let group = variable.macroApplication(ObservableMacro.trackedMacroName)?.observationGroup
      if observationPropertyIndex(of: variable, isObjectResolution: isObjectResolution, group: group) == propertyIndex {
        sharers.append(variable)
      }
    }
    guard let first = sharers.first else { return nil }
    let isolations = sharers.map { $0.observationIsolation(in: self) }
    if isolations.allSatisfy({ $0 == isolations[0] }) {
      return first
    }
    if let nonisolated = isolations.firstIndex(where: { $0 == nil }) {
      return sharers[nonisolated]
    }
    let isolation = property.observationIsolation(in: self)
    if isolation != isolations[0],
       let name = property.identifier?.trimmed.text,
       let firstName = first.identifier?.trimmed.text {
      throw DiagnosticsError(syntax: property, message: "'@Observable' cannot share a property index between '\(name)', isolated to '\(isolation ?? "")', and '\(firstName)', isolated to '\(isolations[0] ?? "")'; mark a property sharing it 'nonisolated', or give them different groups", id: .isolationMismatch)
    }
    return first
  }
}

extension VariableDeclSyntax {
  // The global actor this property is isolated to, or nil when it is
  // nonisolated, as far as its syntax shows: its own global actor attribute
  // or `nonisolated`, else those of `declaration`, its type. Isolation only
  // the type checker infers (from a superclass, a protocol conformance, or
  // the module's default isolation) is not seen; a property with it is
  // taken for nonisolated, or isolated as its type's attributes say.
  func observationIsolation(in declaration: some DeclGroupSyntax) -> String? {
    if modifiers.containsNonisolated { return nil }
    if let actor = attributes.globalActorName { return actor }
    if declaration.modifiers.containsNonisolated { return nil }
    return declaration.attributes.globalActorName
  }
}

extension DeclModifierListSyntax {
  // Whether this has `nonisolated` (or `nonisolated(unsafe)`).
  var containsNonisolated: Bool {
    contains { $0.name.text == "nonisolated" }
  }
}

extension AttributeListSyntax {
  // The unqualified name of the first attribute shaped like a global actor:
  // `@MainActor`, or any other whose name ends in `Actor`. Whether an
  // attribute is a global actor is only known to the type checker.
  var globalActorName: String? {
    for element in self {
      guard case .attribute(let attribute) = element,
            let name = attribute.attributeName.trimmedDescription.split(separator: ".").last,
            name.hasSuffix("Actor") else {
        continue
      }
      return String(name)
    }
    return nil
  }
}

extension AttributeSyntax {

  // Whether `@ObservationTracked` has a `propertyIndex:` argument at all, literal or
  // not: one that is not a literal is diagnosed, not taken for no property index.
  var hasObservationPropertyIndexArgument: Bool {
    guard case .argumentList(let arguments) = self.arguments else { return false }
    return arguments.contains { $0.label?.text == "propertyIndex" }
  }
  
  // The `group:` literal of `@ObservationTracked(group:)`, if it has one.
  var observationGroup: Int? {
    guard case .argumentList(let arguments) = self.arguments,
          let argument = arguments.first(where: { $0.label?.text == "group" }),
          let literal = argument.expression.as(IntegerLiteralExprSyntax.self),
          let group = Int(literal.literal.text), group >= 0 else {
      return nil
    }
    return group
  }
  
  // The `representative:` literal of `@ObservationTracked(representative:)`:
  // the property whose key path stands for the property index, if it has one.
  var observationRepresentative: String? {
    guard case .argumentList(let arguments) = self.arguments,
          let argument = arguments.first(where: { $0.label?.text == "representative" }),
          let literal = argument.expression.as(StringLiteralExprSyntax.self) else {
      return nil
    }
    return literal.representedLiteralValue
  }

  // Whether this is a hand-written `@ObservationTracked(group:)` without a
  // property index on a member of an `@Observable` class. The group's property index depends on
  // the other members, which a macro's lexical context does not show
  // (`asMacroLexicalContext()` clears the member list), so `@Observable`
  // attaches an `@ObservationTracked(propertyIndex:)` next to this one, and this one
  // expands to nothing.
  func defersToObservable(in classDecl: some DeclGroupSyntax) -> Bool {
    guard !hasObservationPropertyIndexArgument, observationGroup != nil else { return false }
    return classDecl.attributes.contains { attribute in
      guard case .attribute(let attr) = attribute else { return false }
      let name = attr.attributeName.trimmedDescription
      return name == ObservableMacro.conformanceName || name == ObservableMacro.qualifiedConformanceName
    }
  }

  // The `resolution:` argument of `@Observable(resolution: .object)`, if it has one.
  // Returns true if resolution is `.object`, false if it's `.default` or unspecified.
  var observationResolution: Bool? {
    guard case .argumentList(let arguments) = self.arguments,
          let argument = arguments.first(where: { $0.label?.text == "resolution" }) else {
      return nil
    }
    // Check if it's `.object`
    if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
       memberAccess.declName.baseName.text == "object" {
      return true
    }
    // Check if it's `.default`
    if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
       memberAccess.declName.baseName.text == "default" {
      return false
    }
    return nil
  }
  
  // Validates and extracts the `resolution:` argument, throwing a diagnostic for non-literal values.
  func validatedObservationResolution() throws -> Bool? {
    guard case .argumentList(let arguments) = self.arguments,
          let argument = arguments.first(where: { $0.label?.text == "resolution" }) else {
      return nil
    }
    // Check if it's `.object`
    if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
       memberAccess.declName.baseName.text == "object" {
      return true
    }
    // Check if it's `.default`
    if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
       memberAccess.declName.baseName.text == "default" {
      return false
    }
    // If the argument exists but is not a recognized literal, emit a diagnostic
    throw DiagnosticsError(syntax: argument.expression, message: "the 'resolution:' argument must be a literal member access (such as '.default' or '.object')", id: .nonLiteralArgument)
  }
  
  // Validates and extracts the `propertyIndex:` argument, throwing a diagnostic for non-literal values.
  func validatedObservationPropertyIndex() throws -> Int? {
    guard case .argumentList(let arguments) = self.arguments,
          let argument = arguments.first(where: { $0.label?.text == "propertyIndex" }) else {
      return nil
    }
    guard let literal = argument.expression.as(IntegerLiteralExprSyntax.self),
          let propertyIndex = Int(literal.literal.text), propertyIndex >= 0 else {
      throw DiagnosticsError(syntax: argument.expression, message: "the 'propertyIndex:' argument must be a non-negative integer literal", id: .nonLiteralArgument)
    }
    return propertyIndex
  }
  
  // Validates and extracts the `group:` argument, throwing a diagnostic for non-literal values.
  func validatedObservationGroup() throws -> Int? {
    guard case .argumentList(let arguments) = self.arguments,
          let argument = arguments.first(where: { $0.label?.text == "group" }) else {
      return nil
    }
    guard let literal = argument.expression.as(IntegerLiteralExprSyntax.self),
          let group = Int(literal.literal.text), group >= 0 else {
      throw DiagnosticsError(syntax: argument.expression, message: "the 'group:' argument must be a non-negative integer literal", id: .nonLiteralArgument)
    }
    return group
  }
}

extension ObservableMacro: MemberMacro {
  public static func expansion<
    Declaration: DeclGroupSyntax,
    Context: MacroExpansionContext
  >(
    of node: AttributeSyntax,
    providingMembersOf declaration: Declaration,
    conformingTo protocols: [TypeSyntax],
    in context: Context
  ) throws -> [DeclSyntax] {
    guard let identified = declaration.asProtocol(NamedDeclSyntax.self) else {
      return []
    }
    
    let observableType = identified.name.trimmed
    
    if declaration.isEnum {
      // enumerations cannot store properties
      throw DiagnosticsError(syntax: node, message: "'@Observable' cannot be applied to enumeration type '\(observableType.text)'", id: .invalidApplication)
    }
    if declaration.isStruct && !declaration.isNoncopyable {
      // A copy would share its registrar with the original, so mutating the
      // copy would notify the original's observers. A noncopyable struct has
      // no copies.
      throw DiagnosticsError(syntax: node, message: "'@Observable' cannot be applied to struct type '\(observableType.text)'", id: .invalidApplication)
    }

    // Validated here, once per type, rather than in the member attribute
    // expansion, which runs once per member and would repeat the diagnostic.
    _ = try node.validatedObservationResolution()

    var declarations = [DeclSyntax]()

    if declaration.isNoncopyableStruct {
      declaration.addIfNeeded(ObservableMacro.registrarVariable(observableType, context: context), to: &declarations)
      declaration.addIfNeeded(ObservableMacro.noncopyableAccessPropertyIndexFunction(observableType, context: context), to: &declarations)
      declaration.addIfNeeded(ObservableMacro.noncopyableWithMutationPropertyIndexFunction(observableType, context: context), to: &declarations)
      declaration.addIfNeeded(ObservableMacro.shouldNotifyObserversNonEquatableFunction(observableType, final: false, context: context), to: &declarations)
      declaration.addIfNeeded(ObservableMacro.shouldNotifyObserversEquatableFunction(observableType, final: false, context: context), to: &declarations)
      declaration.addIfNeeded(ObservableMacro.shouldNotifyObserversNonEquatableObjectFunction(observableType, final: false, context: context), to: &declarations)
      declaration.addIfNeeded(ObservableMacro.shouldNotifyObserversEquatableObjectFunction(observableType, final: false, context: context), to: &declarations)
      return declarations
    }
    if declaration.isActor {
      // An actor's properties are isolated, so no key path can name them
      // either. Its members are isolated too, since a distributed actor
      // cannot have a `nonisolated` registrar, and its `withMutation` is not
      // mutating: the closure runs on the actor, in the setter's own
      // isolation, and mutates it directly.
      // An actor that conforms to `SnapshotSource` also gets its snapshot, and
      // a registrar that is the snapshot's as well as its own, in place of the
      // plain one.
      var snapshotMembers: [DeclSyntax]?
      if declaration.isSnapshotSource {
        if declaration.modifiers.contains(where: { $0.name.tokenKind == .keyword(.distributed) }) {
          // `latestSnapshot` is `nonisolated`, and a distributed actor
          // can't have nonisolated stored state for it to read.
          context.diagnose(Diagnostic(node: node, message: ObservationDiagnostic(
            message: "'@Observable' cannot synthesize 'SnapshotSource' for distributed actor type '\(observableType.text)'",
            domain: "Observation", id: .invalidApplication)))
        } else {
          snapshotMembers = ObservableMacro.snapshotMembers(of: declaration, node: node, in: context)
        }
      }
      if snapshotMembers == nil {
        declaration.addIfNeeded(ObservableMacro.registrarVariable(observableType, context: context), to: &declarations)
      }
      declaration.addIfNeeded(ObservableMacro.noncopyableAccessPropertyIndexFunction(observableType, isolated: true, context: context), to: &declarations)
      declaration.addIfNeeded(ObservableMacro.embeddedWithMutationPropertyIndexFunction(observableType, isolated: true, context: context), to: &declarations)
      declaration.addIfNeeded(ObservableMacro.shouldNotifyObserversNonEquatableFunction(observableType, final: false, context: context), to: &declarations)
      declaration.addIfNeeded(ObservableMacro.shouldNotifyObserversEquatableFunction(observableType, final: false, context: context), to: &declarations)
      declaration.addIfNeeded(ObservableMacro.shouldNotifyObserversNonEquatableObjectFunction(observableType, final: false, context: context), to: &declarations)
      declaration.addIfNeeded(ObservableMacro.shouldNotifyObserversEquatableObjectFunction(observableType, final: false, context: context), to: &declarations)
      for member in snapshotMembers ?? [] {
        // `addIfNeeded` only knows functions and properties; the `Snapshot`
        // structure is added unless the actor declares its own.
        if let snapshot = member.as(StructDeclSyntax.self) {
          let declared = declaration.memberBlock.members.contains {
            $0.decl.as(StructDeclSyntax.self)?.name.text == snapshot.name.text
          }
          if !declared { declarations.append(member) }
        } else {
          declaration.addIfNeeded(member, to: &declarations)
        }
      }
      return declarations
    }
    // Each member that takes a key path is left out under Embedded, where
    // the property index-only ones stand in for the property index-tagged ones.
    func neededFunction(_ decl: DeclSyntax) -> DeclSyntax? {
      var needed = [DeclSyntax]()
      declaration.addIfNeeded(decl, to: &needed)
      return needed.first
    }
    func addConditional(_ embedded: DeclSyntax?, else other: DeclSyntax?) {
      if let decl = ObservableMacro.embeddedConditional(embedded, else: other.flatMap(neededFunction)) {
        declarations.append(decl)
      }
    }
    // A customization made by key path cannot be forwarded to under Embedded.
    func embeddedMember(_ decl: DeclSyntax, forwarding: Bool, customized: String, replacement: String) -> DeclSyntax? {
      guard let decl = neededFunction(decl) else { return nil }
      guard forwarding else { return decl }
      return ObservableMacro.embeddedForwardingError(observableType, customized: customized, replacement: replacement)
    }

    declaration.addIfNeeded(ObservableMacro.registrarVariable(observableType, context: context), to: &declarations)
    let accessFunction = ObservableMacro.accessFunction(observableType, context: context)
    addConditional(nil, else: accessFunction)
    let withMutationFunction = ObservableMacro.withMutationFunction(observableType, context: context)
    addConditional(nil, else: withMutationFunction)
    declaration.addIfNeeded(ObservableMacro.shouldNotifyObserversNonEquatableFunction(observableType, context: context), to: &declarations)
    declaration.addIfNeeded(ObservableMacro.shouldNotifyObserversEquatableFunction(observableType, context: context), to: &declarations)
    declaration.addIfNeeded(ObservableMacro.shouldNotifyObserversNonEquatableObjectFunction(observableType, context: context), to: &declarations)
    declaration.addIfNeeded(ObservableMacro.shouldNotifyObserversEquatableObjectFunction(observableType, context: context), to: &declarations)
    let customAccess = accessFunction.as(FunctionDeclSyntax.self).map(declaration.hasMemberFunction(equvalentTo:)) ?? false
    let accessPropertyIndexFunction = ObservableMacro.accessPropertyIndexFunction(observableType, forwarding: customAccess, context: context)
    let customWithMutation = withMutationFunction.as(FunctionDeclSyntax.self).map(declaration.hasMemberFunction(equvalentTo:)) ?? false
    let withMutationPropertyIndexFunction = ObservableMacro.withMutationPropertyIndexFunction(observableType, forwarding: customWithMutation, context: context)
    // Made after the others, so their unique names are as they were.
    let embeddedAccessPropertyIndexFunction = ObservableMacro.embeddedAccessPropertyIndexFunction(observableType, context: context)
    let embeddedWithMutationPropertyIndexFunction = ObservableMacro.embeddedWithMutationPropertyIndexFunction(observableType, context: context)
    addConditional(embeddedMember(embeddedAccessPropertyIndexFunction, forwarding: customAccess, customized: "access(keyPath:)", replacement: "access(propertyIndex:)"), else: accessPropertyIndexFunction)
    addConditional(embeddedMember(embeddedWithMutationPropertyIndexFunction, forwarding: customWithMutation, customized: "withMutation(keyPath:_:)", replacement: "withMutation(propertyIndex:_:)"), else: withMutationPropertyIndexFunction)

    return declarations
  }
}

extension ObservableMacro: MemberAttributeMacro {
  public static func expansion<
    Declaration: DeclGroupSyntax,
    MemberDeclaration: DeclSyntaxProtocol,
    Context: MacroExpansionContext
  >(
    of node: AttributeSyntax,
    attachedTo declaration: Declaration,
    providingAttributesFor member: MemberDeclaration,
    in context: Context
  ) throws -> [AttributeSyntax] {
    // A derived property gets its property index here, where the whole type is
    // visible, as `@ObservationDerived(propertyIndex:)`.
    if let derived = member.as(VariableDeclSyntax.self),
       let attribute = derived.macroApplication(ObservationDerivedMacro.macroName) {
      guard !attribute.hasObservationPropertyIndexArgument else { return [] }
      // Not a direct member (inside `#if`): `-1` keeps the attribute from
      // deferring, so the property expands without a registrar or index.
      let propertyIndex = declaration.observationDerivedPropertyIndex(of: derived) ?? -1
      return ["@\(raw: ObservationDerivedMacro.macroName)(propertyIndex: \(raw: propertyIndex))"]
    }

    guard let property = member.as(VariableDeclSyntax.self), property.isValidForObservation,
          property.identifier != nil else {
      return []
    }

    // dont apply to ignored properties
    if property.hasMacroApplication(ObservableMacro.ignoredMacroName) {
      return []
    }
    
    // The accessors can't see the other members (a macro's lexical context
    // has its member list cleared), so the property index, and the representative key
    // path of a shared one, are worked out here, where the whole type is, and
    // handed to them as arguments.
    // A `resolution:` that is not a literal is diagnosed once, by the
    // `MemberMacro` expansion; here it falls back to `.default`.
    let isObjectResolution = node.observationResolution == true
    var group: Int? = nil
    if let tracked = property.macroApplication(ObservableMacro.trackedMacroName) {
      // A property already flagged as tracked keeps its attribute, except
      // that one with a group but no property index gets its property index from the attribute
      // attached here, and its own expands to nothing (see
      // `defersToObservable(in:)`).
      // Note: we use the non-throwing versions here because any validation of
      // hand-written @ObservationTracked attributes is the job of
      // ObservationTrackedMacro, not MemberAttributeMacro.
      guard !tracked.hasObservationPropertyIndexArgument, let trackedGroup = tracked.observationGroup else {
        return []
      }
      group = trackedGroup
    }

    guard let attribute = try ObservableMacro.trackedAttribute(for: property, in: declaration, isObjectResolution: isObjectResolution, group: group) else {
      // A property inside `#if` with no direct property index still gets the bare
      // @ObservationTracked attribute, for key-path-only tracking.
      return [ObservableMacro.trackedAttribute]
    }
    return [attribute]
  }
}


extension ObservableMacro: ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    // This method can be called twice - first with an empty `protocols` when
    // no conformance is needed, and second with a `MissingTypeSyntax` instance.
    if protocols.isEmpty {
      return []
    }

    let decl: DeclSyntax = """
        extension \(raw: type.trimmedDescription): nonisolated \(raw: qualifiedConformanceName) {}
        """
    let ext = decl.cast(ExtensionDeclSyntax.self)

    if let availability = declaration.attributes.availability {
      return [ext.with(\.attributes, availability)]
    } else {
      return [ext]
    }
  }
}

public struct ObservationTrackedMacro: AccessorMacro {
  public static func expansion<
    Context: MacroExpansionContext,
    Declaration: DeclSyntaxProtocol
  >(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: Declaration,
    in context: Context
  ) throws -> [AccessorDeclSyntax] {
    guard let property = declaration.as(VariableDeclSyntax.self),
          property.isValidForObservation,
          let identifier = property.identifier?.trimmed else {
      return []
    }

    // A property of a `SnapshotSource`'s `Snapshot` (see `SnapshotSynthesis.swift`).
    if ObservationTrackedMacro.isSnapshotProperty(in: context) {
      return snapshotAccessors(identifier: identifier, propertyIndex: try node.validatedObservationPropertyIndex())
    }

    guard let typeDecl = ObservationTrackedMacro.observableTypeDecl(in: context) else {
      return []
    }

    if property.hasMacroApplication(ObservableMacro.ignoredMacroName) {
      return []
    }

    if node.defersToObservable(in: typeDecl) {
      return []
    }

    // `, propertyIndex: n` when `@Observable` passed one; otherwise nothing, so the
    // calls are the key-path-only ones.
    let propertyIndex = try node.validatedObservationPropertyIndex()
    _ = try node.validatedObservationGroup()

    if typeDecl.observesByPropertyIndexOnly {
      // A `SnapshotSource`'s writes also invalidate its snapshot. A property
      // `@ObservationIgnored` has returned above, so it is not one.
      return noncopyableAccessors(identifier: identifier, propertyIndex: propertyIndex, isActor: typeDecl.isActor, invalidatesSnapshot: typeDecl.isSnapshotSource)
    }

    let propertyIndexArgument = propertyIndex.map { ", propertyIndex: \($0)" } ?? ""

    // Properties sharing a property index all pass the key path of the first of them
    // (`representative:`, from `@Observable`), so the registrar sees one key
    // path per property index.
    let keyPathIdentifier = node.observationRepresentative.map { TokenSyntax.identifier($0) } ?? identifier

    // Embedded Swift has no key paths, so there the calls pass only the
    // property index. Without one there is nothing to track the property by, so each
    // accessor fails the build under Embedded rather than drop its tracking.
    let noPropertyIndexError = #"#error("'@Observable' cannot track '\#(identifier.text)' in Embedded Swift because it is not a direct member of its class")"#
    let embeddedGet = propertyIndex.map { "access(propertyIndex: \($0))" } ?? noPropertyIndexError
    // Continuation lines carry the accessor body's indentation themselves.
    let embeddedSet = propertyIndex.map {
      "withMutation(propertyIndex: \($0)) {\n    _\(identifier.text) = newValue\n  }"
    } ?? noPropertyIndexError
    let embeddedModify = propertyIndex.map {
      "access(propertyIndex: \($0))\n" +
      "  \(ObservableMacro.registrarVariableName).willSet(propertyIndex: \($0))\n" +
      "  defer { \(ObservableMacro.registrarVariableName).didSet(propertyIndex: \($0)) }"
    } ?? noPropertyIndexError
    let embeddedSetClause = "#if $Embedded\n  \(embeddedSet)\n  #else"
    let embeddedModifyClause = "#if $Embedded\n  \(embeddedModify)\n  #else"

    let initAccessor: AccessorDeclSyntax =
      """
      @storageRestrictions(initializes: _\(identifier))
      init(initialValue) {
        _\(identifier) = initialValue
      }
      """
    let getAccessor: AccessorDeclSyntax =
      """
      get {
        #if $Embedded
        \(raw: embeddedGet)
        #else
        access(keyPath: \\.\(keyPathIdentifier)\(raw: propertyIndexArgument))
        #endif
        return _\(identifier)
      }
      """

    // the guard else case must include the assignment else
    // cases that would notify then drop the side effects of `didSet` etc
    let setAccessor: AccessorDeclSyntax =
      """
      set {
        guard shouldNotifyObservers(_\(identifier), newValue) else {
          _\(identifier) = newValue
          return
        }
        \(raw: embeddedSetClause)
        withMutation(keyPath: \\.\(keyPathIdentifier)\(raw: propertyIndexArgument)) {
          _\(identifier) = newValue
        }
        #endif
      }
      """
      
    // Note: this accessor cannot test the equality since it would incur
    // additional CoW's on structural types. Most mutations in-place do
    // not leave the value equal so this is "fine"-ish.
    // Warning to future maintence: adding equality checks here can make
    // container mutation O(N) instead of O(1).
    // e.g. observable.array.append(element) should just emit a change
    // to the new array, and NOT cause a copy of each element of the
    // array to an entirely new array.
    let modifyAccessor: AccessorDeclSyntax =
      """
      _modify {
        \(raw: embeddedModifyClause)
        access(keyPath: \\.\(keyPathIdentifier)\(raw: propertyIndexArgument))
        \(raw: ObservableMacro.registrarVariableName).willSet(self, keyPath: \\.\(keyPathIdentifier)\(raw: propertyIndexArgument))
        defer { \(raw: ObservableMacro.registrarVariableName).didSet(self, keyPath: \\.\(keyPathIdentifier)\(raw: propertyIndexArgument)) }
        #endif
        yield &_\(identifier)
      }
      """

    return [initAccessor, getAccessor, setAccessor, modifyAccessor]
  }

  // The type a tracked property is a member of, when it is one `@Observable`
  // applies to: a class, an actor (distributed or not), or a noncopyable struct.
  static func observableTypeDecl(in context: some MacroExpansionContext) -> (any DeclGroupSyntax)? {
    guard let lexical = context.lexicalContext.first else { return nil }
    if let classDecl = lexical.as(ClassDeclSyntax.self) {
      return classDecl
    }
    if let actorDecl = lexical.as(ActorDeclSyntax.self) {
      return actorDecl
    }
    if let structDecl = lexical.as(StructDeclSyntax.self), structDecl.isNoncopyable {
      return structDecl
    }
    return nil
  }

  // The accessors of a property of a noncopyable struct: property index-only calls in
  // every build, since no key path can name the property. The setter
  // mutates through `withMutation(propertyIndex:_:)`, which passes the struct inout;
  // an actor's takes no argument, and its closure mutates the actor directly.
  static func noncopyableAccessors(identifier: TokenSyntax, propertyIndex: Int?, isActor: Bool = false, invalidatesSnapshot: Bool = false) -> [AccessorDeclSyntax] {
    let initAccessor: AccessorDeclSyntax =
      """
      @storageRestrictions(initializes: _\(identifier))
      init(initialValue) {
        _\(identifier) = initialValue
      }
      """
    // Without a property index (a property inside `#if`) there is nothing to track the
    // property by, so each accessor fails the build rather than drop it.
    guard let propertyIndex else {
      let noPropertyIndexError: AccessorDeclSyntax =
        """
        get {
          #error("'@Observable' cannot track '\(raw: identifier.text)' of a noncopyable type because it is not a direct member of its type")
          return _\(identifier)
        }
        """
      return [initAccessor, noPropertyIndexError]
    }
    let getAccessor: AccessorDeclSyntax =
      """
      get {
        access(propertyIndex: \(raw: propertyIndex))
        return _\(identifier)
      }
      """
    let mutated = isActor ? "_\(identifier.text)" : "$0._\(identifier.text)"
    // Only schedules the snapshot's refresh, which can't run until this job
    // suspends, so where in the accessor it is called doesn't matter. In
    // `set` it follows the equality guard: a write that observers aren't
    // notified of doesn't change the snapshot either.
    let invalidate = invalidatesSnapshot ? "\(ObservableMacro.snapshotInvalidateFunctionName)(propertyIndex: \(propertyIndex))\n" : ""
    let setAccessor: AccessorDeclSyntax =
      """
      set {
        guard shouldNotifyObservers(_\(identifier), newValue) else {
          _\(identifier) = newValue
          return
        }
        \(raw: invalidate)withMutation(propertyIndex: \(raw: propertyIndex)) {
          \(raw: mutated) = newValue
        }
      }
      """
    // As for a class, `_modify` always notifies (see above).
    let modifyAccessor: AccessorDeclSyntax =
      """
      _modify {
        \(raw: invalidate)access(propertyIndex: \(raw: propertyIndex))
        \(raw: ObservableMacro.registrarVariableName).willSet(propertyIndex: \(raw: propertyIndex))
        defer {
          \(raw: ObservableMacro.registrarVariableName).didSet(propertyIndex: \(raw: propertyIndex))
        }
        yield &_\(identifier)
      }
      """
    return [initAccessor, getAccessor, setAccessor, modifyAccessor]
  }
}

extension ObservationTrackedMacro: PeerMacro {
  public static func expansion<
    Context: MacroExpansionContext,
    Declaration: DeclSyntaxProtocol
  >(
    of node: SwiftSyntax.AttributeSyntax,
    providingPeersOf declaration: Declaration,
    in context: Context
  ) throws -> [DeclSyntax] {
    guard let property = declaration.as(VariableDeclSyntax.self),
          property.isValidForObservation,
          property.identifier?.trimmed != nil else {
      return []
    }

    if ObservationTrackedMacro.isSnapshotProperty(in: context) {
      return snapshotPeers(of: property)
    }

    guard let typeDecl = ObservationTrackedMacro.observableTypeDecl(in: context) else {
      return []
    }

    if property.hasMacroApplication(ObservableMacro.ignoredMacroName) {
      return []
    }

    if node.defersToObservable(in: typeDecl) {
      return []
    }
    
    let localContext = LocalMacroExpansionContext(context: context)
    let storage = DeclSyntax(property.privatePrefixed("_", addingAttribute: ObservableMacro.ignoredAttribute, removingAttribute: ObservableMacro.trackedAttribute, in: localContext))
    return [storage]
  }
}

public struct ObservationIgnoredMacro: AccessorMacro {
  public static func expansion<
    Context: MacroExpansionContext,
    Declaration: DeclSyntaxProtocol
  >(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: Declaration,
    in context: Context
  ) throws -> [AccessorDeclSyntax] {
    return []
  }
}
