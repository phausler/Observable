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


/// A type that emits notifications to observers when underlying data changes.
///
/// Conforming to this protocol signals to other APIs that the type supports
/// observation. However, applying the `Observable` protocol by itself to a
/// type doesn't add observation functionality to the type. Instead, always use
/// the ``Observation/Observable()`` macro when adding observation
/// support to a type.
///
/// Noncopyable types can conform: the ``Observation/Observable()`` macro
/// applies to a `~Copyable` struct, whose properties are observed by property index
/// rather than by key path.
@available(SwiftStdlib 5.9, *)
public protocol Observable: ~Copyable { }

#if $Macros && hasAttribute(attached)

/// Defines and implements conformance of the Observable protocol.
///
/// This macro adds observation support to a custom type and conforms the type
/// to the ``Observation/Observable`` protocol. For example, the following code
/// applies the `Observable` macro to the type `Car` making it observable:
///
///     @Observable 
///     class Car {
///        var name: String = ""
///        var needsRepairs: Bool = false
///        
///        init(name: String, needsRepairs: Bool = false) {
///            self.name = name
///            self.needsRepairs = needsRepairs
///        }
///     }
///
/// The macro also applies to a noncopyable struct, which, unlike a copyable
/// one, has no copies to share its observers with:
///
///     @Observable
///     struct Gauge: ~Copyable {
///        var reading: Double = 0
///     }
///
/// No key path can name a property of a noncopyable type, so its properties
/// are observed by property index: tracking and notification work as for a class, but
/// an event's ``ObservationTracking/Event/matches(_:)`` is always false.
@available(SwiftStdlib 5.9, *)
@attached(member, names: named(_$observationRegistrar), named(access), named(withMutation), named(shouldNotifyObservers))
@attached(memberAttribute)
@attached(extension, conformances: Observable)
public macro Observable() =
  #externalMacro(module: "ObservationMacros", type: "ObservableMacro")

/// Defines and implements conformance of the Observable protocol, with the
/// given granularity of change events.
///
/// With `.object` resolution, every tracked property shares one event: an
/// observer that read any of them is notified when any of them changes.
///
///     @Observable(resolution: .object)
///     final class Color {
///        var red = 0.0
///        var green = 0.0
///        var blue = 0.0
///     }
///
/// A separate declaration from ``Observable()``, so that `@Observable` keeps
/// its original availability.
@available(SwiftStdlib 6.5, *)
@attached(member, names: named(_$observationRegistrar), named(access), named(withMutation), named(shouldNotifyObservers))
@attached(memberAttribute)
@attached(extension, conformances: Observable)
public macro Observable(resolution: ObservationResolution) =
  #externalMacro(module: "ObservationMacros", type: "ObservableMacro")

/// The granularity of the change events of an `@Observable` type's
/// properties.
@available(SwiftStdlib 6.5, *)
public enum ObservationResolution {
  /// Each tracked property is its own event source.
  case `default`
  /// All tracked properties share a single event source.
  case object
}

/// Synthesizes a property for accessors.
///
/// The ``Observation`` module uses this macro. Its use outside of the
/// framework isn't necessary. `@Observable` passes `propertyIndex`, the property's
/// ordinal among its type's observed properties, for the accessors to pass to
/// the registrar; without it they use the key-path-only entry points. When
/// properties share a property index (`group:`, or `@Observable(resolution: .object)`),
/// it also passes `representative`, the first of them, whose key path the
/// accessors pass instead of their own.
@available(SwiftStdlib 5.9, *)
@attached(accessor, names: named(init), named(get), named(set), named(_modify))
@attached(peer, names: prefixed(_))
public macro ObservationTracked(propertyIndex: Int = -1, group: Int? = nil, representative: String? = nil) =
  #externalMacro(module: "ObservationMacros", type: "ObservationTrackedMacro")

/// Disables observation tracking of a property.
///
/// By default, an object can observe any property of an observable type that
/// is accessible to the observing object. To prevent observation of an
/// accessible property, attach the `ObservationIgnored` macro to the property.
@available(SwiftStdlib 5.9, *)
@attached(accessor)
public macro ObservationIgnored() =
  #externalMacro(module: "ObservationMacros", type: "ObservationIgnoredMacro")

/// Derives a property from other observable state, storing the result and
/// recomputing it only when what it depends on has changed.
///
///     @Observable final class Signal {
///       var a: Float = 0
///       var b: Float = 0
///       @ObservationDerived var rms: Float {
///         input {
///           (a, b)
///         }
///         update {
///           (($0.0 * $0.0 + $0.1 * $0.1) / 2).squareRoot()
///         }
///       }
///     }
///
/// The body is exactly two blocks: `input` reads what the value depends on
/// and should be cheap; `update` computes the value from what `input`
/// returned and must be pure. Unlike a plain computed property, reading a
/// derived property whose inputs haven't changed runs neither block, and a
/// recomputed `Equatable` value equal to the previous one isn't a change to
/// derived properties that read it.
///
/// The macro stores the value in an ``ObservationDerivedValue`` named after
/// the property with a leading underscore, and replaces the body with a call
/// passing it the two blocks as closures; see ``ObservationDerivedValue`` for
/// when each runs.
///
/// `@Observable` supplies `propertyIndex`, the property's index among the type's
/// properties; code doesn't write it by hand.
@available(SwiftStdlib 6.5, *)
@attached(peer, names: prefixed(_))
@attached(body)
public macro ObservationDerived(propertyIndex: Int = -1) =
  #externalMacro(module: "ObservationMacros", type: "ObservationDerivedMacro")

#endif
