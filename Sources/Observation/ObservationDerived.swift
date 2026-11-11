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

import Synchronization

struct CacheValueId {
  static let generation = Atomic(0)
}

// The `ObservationDerivedValue` traversals under way. Each thread's innermost
// is in a thread-local (`_ThreadLocal.traversal`), linked to the ones it is
// nested in; see `_TraversalFrame`.
struct _Traversals {
  // How many traversals are under way, on all threads. Every access checks
  // for a traversal on its thread, and a C11 thread-local costs a call into
  // the runtime to reach on Darwin (about 2 ns, a third of a plain read), so
  // the check reads this first and reaches the thread-local only while it is
  // not zero. Relaxed suffices: a thread always sees its own increments, so
  // it never misses its own traversal, and a stale nonzero elsewhere only
  // costs the thread-local read, which finds nothing.
  private static let active = Atomic<UInt32>(0)

  // The innermost traversal on this thread, if any.
  static var current: UnsafeMutableRawPointer? {
    guard active.load(ordering: .relaxed) != 0 else { return nil }
    return _ThreadLocal.traversal
  }

  // Makes `frame` the innermost traversal on this thread.
  static func push(_ frame: UnsafeMutableRawPointer) {
    active.add(1, ordering: .relaxed)
    _ThreadLocal.traversal = frame
  }

  // Ends the innermost traversal, making `previous`, the one it was pushed
  // over, the innermost again.
  static func pop(_ previous: UnsafeMutableRawPointer?) {
    _ThreadLocal.traversal = previous
    active.subtract(1, ordering: .relaxed)
  }
}

// The derived visit of a read under tracking: the collection, this value's
// identity, and whether the collection already holds it. Declared outside
// `ObservationDerivedValue` so its metadata is static, not instantiated at
// run time for each `Value` on every read.
@available(SwiftStdlib 6.5, *)
internal struct _DerivedVisit {
  let collecting: ObservationTracking.Collecting
  let context: ObservationRegistrar.Context
  let index: Int
  let visited: Bool
}

/// The storage of a derived property of an observable type.
///
/// Most code doesn't use this type directly: the ``ObservationDerived(propertyIndex:)``
/// macro declares one for each derived property and computes the property
/// through it.
///
///     @Observable final class Signal {
///       var a: Float = 0
///       var b: Float = 0
///       @ObservationDerived
///       var rms: Float {
///         input {
///           (a, b)
///         }
///         update {
///           (($0.0 * $0.0 + $0.1 * $0.1) / 2).squareRoot()
///         }
///       }
///     }
///
/// Declaring one by hand and calling ``compute(input:update:)`` from a
/// getter is equivalent, and is for types the macro can't be applied to.
///
/// `input` reads the observable properties (and other derived values) the
/// value depends on, and should be cheap; `update` computes the value from
/// what `input` returned, and must be pure. A read runs neither if nothing
/// has been written since the value was last computed; otherwise it runs
/// `input`, and runs `update` only if something `input` read has changed
/// since. If `Value` is `Equatable`, a recomputed value equal to the stored
/// one does not count as a change to derived values that read this one.
///
/// A read inside `withObservationTracking` (or another tracking) runs `input`,
/// so that the tracking observes what the value depends on. Through the
/// ``compute(registrar:propertyIndex:input:update:)`` overloads, which the
/// macro uses, that happens once per tracking: a later read in the same
/// tracking, while the value is still valid, returns it directly.
@available(SwiftStdlib 6.5, *)
public struct ObservationDerivedValue<Value: Sendable>: Sendable, ~Copyable {
  internal struct Record {
    var value: Value?
    // The epoch `value` was last validated in, and the epoch it last
    // changed in; both meaningful only once `value` is set.
    var visited: UInt32 = 0
    var mutated: UInt32 = 0
  }
  internal struct Computation {
    var value: Value
    var mutation: UInt32
  }
  internal let id: Int

  private let state = Mutex(Record())

  public init() {
    id = CacheValueId.generation.add(1, ordering: .relaxed).oldValue
  }

  /// Returns the stored value, first recomputing it if what it depends on
  /// has changed; a recomputed value equal to the stored one does not count
  /// as a change.
  public func compute<Input>(
    input: () -> Input,
    update: (Input) -> Value
  ) -> Value where Value: Equatable {
    compute(input: input, update: update, isEqual: ==)
  }

  /// Returns the stored value, first recomputing it if what it depends on
  /// has changed.
  public func compute<Input>(
    input: () -> Input,
    update: (Input) -> Value
  ) -> Value {
    compute(input: input, update: update, isEqual: { _, _ in false })
  }

  /// Returns the stored value, first recomputing it if what it depends on
  /// has changed; a recomputed value equal to the stored one does not count
  /// as a change.
  ///
  /// - Parameters:
  ///   - registrar: The registrar of the object that owns this value.
  ///   - propertyIndex: The derived property's index, which
  ///     ``ObservationDerived(propertyIndex:)`` numbers after the type's stored properties.
  ///
  /// A read under tracking runs `input` once per tracking, not on every read.
  public func compute<Input>(
    registrar: borrowing ObservationRegistrar,
    propertyIndex: Int,
    input: () -> Input,
    update: (Input) -> Value
  ) -> Value where Value: Equatable {
    compute(input: input, update: update, isEqual: ==,
            visit: visit(registrar: registrar, propertyIndex: propertyIndex))
  }

  /// Returns the stored value, first recomputing it if what it depends on
  /// has changed.
  ///
  /// - Parameters:
  ///   - registrar: The registrar of the object that owns this value.
  ///   - propertyIndex: The derived property's index, which
  ///     ``ObservationDerived(propertyIndex:)`` numbers after the type's stored properties.
  ///
  /// A read under tracking runs `input` once per tracking, not on every read.
  public func compute<Input>(
    registrar: borrowing ObservationRegistrar,
    propertyIndex: Int,
    input: () -> Input,
    update: (Input) -> Value
  ) -> Value {
    compute(input: input, update: update, isEqual: { _, _ in false },
            visit: visit(registrar: registrar, propertyIndex: propertyIndex))
  }

  private func visit(registrar: borrowing ObservationRegistrar, propertyIndex: Int) -> _DerivedVisit? {
    guard let collecting = ObservationTracking.Collecting(_ThreadLocal.value) else { return nil }
    let context = registrar.context
    return _DerivedVisit(
      collecting: collecting, context: context, index: propertyIndex,
      visited: collecting.containsDerivedVisit(context: context, index: propertyIndex))
  }

  private func compute<Input>(
    input: () -> Input,
    update: (Input) -> Value,
    isEqual: (Value, Value) -> Bool,
    visit: _DerivedVisit? = nil
  ) -> Value {
    let previous = _Traversals.current
    var next = previous
    while let pointer = next {
      let frame = pointer.assumingMemoryBound(to: _TraversalFrame.self)
      if frame.pointee.cache == id {
        fatalError("A derived value depends on itself")
      }
      next = frame.pointee.previous
    }
    let parent = previous?.assumingMemoryBound(to: _TraversalFrame.self)
    let pinned = parent?.pointee.pinned ?? _Epoch.current
    let tracked = _ThreadLocal.value != nil

    let computation: Computation = state.withLock { record in
      // Clean: validated in the traversal's epoch (or a later one). Both
      // are measured back from the current epoch, which neither is past, so
      // a `visited` 2^29 or more behind still reads as behind; comparing
      // the two by distance (`isNewer`) would take it for newer and return
      // a stale value. Loaded under the lock, so it is no older than a
      // `visited` another thread stored.
      let current = _Epoch.current
      let clean = record.value != nil &&
        (current &- record.visited) & _Epoch.mask <= (current &- pinned) & _Epoch.mask
      if clean && (!tracked || visit?.visited == true) {
        return Computation(value: record.value!, mutation: record.mutated)
      }
      var frame = _TraversalFrame(cache: id, pinned: pinned, previous: previous)
      return withUnsafeMutablePointer(to: &frame) { frame in
        _Traversals.push(UnsafeMutableRawPointer(frame))
        defer { _Traversals.pop(previous) }
        // Run even when clean, so an enclosing tracking records the reads.
        let arguments = input()
        if tracked, let visit {
          visit.collecting.addDerivedVisit(context: visit.context, index: visit.index)
        }
        guard !clean else {
          return Computation(value: record.value!, mutation: record.mutated)
        }
        // Changed: a stamp read is newer than `visited`, both measured from
        // an epoch loaded after `input` read them, as `clean` is.
        let now = _Epoch.current
        let changed = record.value == nil ||
          (frame.pointee.hasRead &&
            _Epoch.age(of: frame.pointee.newest, at: now) < _Epoch.age(of: record.visited, at: now))
        if changed {
          let newValue = update(arguments)
          if record.value == nil || !isEqual(record.value!, newValue) {
            record.value = newValue
            record.mutated = pinned
          }
        }
        // Not clean, so `pinned` is newer than `visited` (or this is the
        // first computation).
        record.visited = pinned
        return Computation(value: record.value!, mutation: record.mutated)
      }
    }
    // A cache read from another's `input` counts as a read of a source
    // whose last change is this value's.
    parent?.pointee.include(computation.mutation, at: _Epoch.current)
    return computation.value
  }
}
