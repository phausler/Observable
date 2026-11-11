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

// `@ObservationDerived var rms: Float { input { ... } update { ... } }`: a
// derived value computed through a stored
// `_rms: ObservationDerivedValue<Float>` (ObservationDerived.swift). The peer
// role emits that storage; the body role replaces the getter with
// `_rms.compute(input: { ... }, update: { ... })`, splicing in the two
// closures unchanged. `input { ... }` and `update { ... }` are not real calls:
// they only parse as calls of bare identifiers with a trailing closure, and
// the original body is never type-checked.
//
// Inside an `@Observable` type the property index is supplied by `@Observable`,
// which attaches `@ObservationDerived(propertyIndex:)` (the lexical context
// shows no other members, so this macro can't count them); the body then also
// passes the type's registrar and that index. A bare `@ObservationDerived`
// there defers: both roles expand to nothing.
//
// The peer role validates the whole declaration and reports any problem; the
// body role expands to nothing for a body it cannot rewrite, so nothing is
// reported twice.
public struct ObservationDerivedMacro {
  static let macroName = "ObservationDerived"
  static let derivedValueTypeName = "ObservationDerivedValue"
  static var qualifiedDerivedValueTypeName: String {
    "\(ObservableMacro.moduleName).\(derivedValueTypeName)"
  }

  // The property's name and type, or a diagnostic.
  static func parse(_ declaration: some DeclSyntaxProtocol, node: AttributeSyntax, context: some MacroExpansionContext) throws -> (identifier: TokenSyntax, type: TypeSyntax) {
    guard let property = declaration.as(VariableDeclSyntax.self),
          property.bindings.count == 1,
          let binding = property.bindings.first,
          let identifier = property.identifier?.trimmed else {
      throw DiagnosticsError(syntax: node, message: "'@\(macroName)' can only be applied to a single 'var' property", id: .invalidApplication)
    }
    guard property.bindingSpecifier.tokenKind == .keyword(.var), property.isInstance else {
      throw DiagnosticsError(syntax: node, message: "'@\(macroName)' can only be applied to an instance 'var' property", id: .invalidApplication)
    }
    guard let type = binding.typeAnnotation?.type.trimmed else {
      throw DiagnosticsError(syntax: binding, message: "'@\(macroName)' property '\(identifier.text)' must declare its type", id: .invalidApplication)
    }
    guard case .getter(let statements) = binding.accessorBlock?.accessors,
          blocks(statements) != nil else {
      throw DiagnosticsError(syntax: binding, message: "'@\(macroName)' property '\(identifier.text)' must have a body of the form 'input { ... } update { ... }'", id: .invalidApplication)
    }
    guard let container = context.lexicalContext.first?.asProtocol(DeclGroupSyntax.self),
          isDerivedContainer(container) else {
      throw DiagnosticsError(syntax: node, message: "'@\(macroName)' can only be applied to a property of a class or noncopyable struct", id: .invalidApplication)
    }
    return (identifier, type)
  }

  // Whether `@Observable` will supply this attribute's property index: it has
  // none, and the container carries `@Observable`.
  static func defersToObservable(_ node: AttributeSyntax, in container: some DeclGroupSyntax) -> Bool {
    guard !node.hasObservationPropertyIndexArgument else { return false }
    return container.attributes.contains { attribute in
      guard case .attribute(let attr) = attribute else { return false }
      let name = attr.attributeName.trimmedDescription
      return name == ObservableMacro.conformanceName || name == ObservableMacro.qualifiedConformanceName
    }
  }

  // The attribute's `propertyIndex:` literal, if it has a non-negative one.
  static func propertyIndex(of node: AttributeSyntax) -> Int? {
    guard case .argumentList(let arguments) = node.arguments,
          let argument = arguments.first(where: { $0.label?.text == "propertyIndex" }),
          let literal = argument.expression.as(IntegerLiteralExprSyntax.self),
          let index = Int(literal.literal.text), index >= 0 else {
      return nil
    }
    return index
  }

  // A class, or a noncopyable struct: its `ObservationDerivedValue` storage
  // is noncopyable, so a copyable struct can't hold it.
  static func isDerivedContainer(_ declaration: some DeclGroupSyntax) -> Bool {
    declaration.isClass || declaration.isNoncopyableStruct
  }

  // The closures of `input { ... }` and `update { ... }`, when they are the
  // body's only statements, in that order.
  static func blocks(_ statements: CodeBlockItemListSyntax) -> (input: ClosureExprSyntax, update: ClosureExprSyntax)? {
    guard statements.count == 2 else { return nil }
    let closures = statements.compactMap { trailingClosure(of: $0.item) }
    guard closures.count == 2,
          closures[0].name == "input",
          closures[1].name == "update" else {
      return nil
    }
    return (closures[0].closure, closures[1].closure)
  }

  // `name { ... }`: a bare identifier called with only a trailing closure.
  static func trailingClosure(of item: CodeBlockItemSyntax.Item) -> (name: String, closure: ClosureExprSyntax)? {
    guard let call = item.as(FunctionCallExprSyntax.self),
          let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
          call.leftParen == nil,
          call.arguments.isEmpty,
          call.additionalTrailingClosures.isEmpty,
          let closure = call.trailingClosure else {
      return nil
    }
    return (callee.baseName.text, closure)
  }
}

extension ObservationDerivedMacro: PeerMacro {
  public static func expansion<
    Context: MacroExpansionContext,
    Declaration: DeclSyntaxProtocol
  >(
    of node: AttributeSyntax,
    providingPeersOf declaration: Declaration,
    in context: Context
  ) throws -> [DeclSyntax] {
    if let container = context.lexicalContext.first?.asProtocol(DeclGroupSyntax.self),
       defersToObservable(node, in: container) {
      return []
    }
    let (identifier, type) = try parse(declaration, node: node, context: context)
    return [
      "private let _\(identifier) = \(raw: qualifiedDerivedValueTypeName)<\(type)>()"
    ]
  }
}

extension ObservationDerivedMacro: BodyMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
    in context: some MacroExpansionContext
  ) throws -> [CodeBlockItemSyntax] {
    // The getter arrives on its own; the property it belongs to is the
    // innermost lexical context, and the type the peer role requires is the
    // next.
    guard let statements = declaration.body?.statements,
          let property = context.lexicalContext.first?.as(VariableDeclSyntax.self),
          let container = context.lexicalContext.dropFirst().first?.asProtocol(DeclGroupSyntax.self),
          isDerivedContainer(container),
          let identifier = property.identifier?.trimmed,
          let (input, update) = blocks(statements),
          !defersToObservable(node, in: container) else {
      return []
    }
    if let index = propertyIndex(of: node) {
      return [
        "return _\(identifier).compute(registrar: \(raw: ObservableMacro.registrarVariableName), propertyIndex: \(raw: index), input: \(input.trimmed), update: \(update.trimmed))"
      ]
    }
    return [
      "return _\(identifier).compute(input: \(input.trimmed), update: \(update.trimmed))"
    ]
  }
}
