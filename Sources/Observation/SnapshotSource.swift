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

#if !$Embedded

/// An actor that publishes its state as a `Snapshot`, a value that can be read
/// from outside the actor without awaiting it.
///
/// Declaring the conformance on an actor that is also `@Observable` is all
/// that is needed: the macro synthesizes a `Snapshot` structure mirroring the
/// actor's observed stored properties, and the members of the protocol.
///
///     @Observable
///     actor Counter: SnapshotSource {
///       var count = 0
///     }
///
/// The snapshot is eventually consistent with the actor. A write to one of
/// its observed properties invalidates the snapshot, and a refresh, scheduled
/// on the actor, publishes the new values; that is no earlier than the writing
/// job's next suspension point. Coalescing writes into one refresh, a reader
/// sees the previous snapshot or a newer one, never an older one, and all of
/// a snapshot's values come from a single job on the actor.
///
/// Reading a property of a snapshot under observation tracking, as a view's
/// body does, registers an access to it. The observer is notified once the
/// refresh has published the snapshot that has the new value, so reading the
/// snapshot when notified always gives it. These notifications are separate
/// from the actor's own, which are immediate and for observers on the actor.
/// Read `latestSnapshot` for the most recent published snapshot, without
/// awaiting it; all of its values come from one snapshot, so a view reads a
/// consistent set. Await `snapshot` for a value that is current as of the
/// access.
///
/// Mark a property `@ObservationIgnored` to leave it out of the snapshot, as
/// one whose type is not `Sendable` must be. It is then not observed either.
@available(SwiftStdlib 6.5, *)
public protocol SnapshotSource: Actor {
  associatedtype Snapshot: Sendable

  /// A snapshot of the actor's current state, which is also published as the
  /// latest snapshot.
  var snapshot: Snapshot { get async }

  /// The most recent snapshot the actor has published, readable without
  /// awaiting it.
  ///
  /// It lags a write until the refresh that write scheduled runs, which is no
  /// earlier than the writing job's next suspension point. Reading a property
  /// of it under observation tracking registers an access to that property.
  nonisolated var latestSnapshot: Snapshot { get }
}

/// The registrar of a `SnapshotSource` actor, which the `@Observable` macro
/// synthesizes. Its use outside of the framework isn't necessary.
///
/// It holds two sets of observers that are kept apart: the actor's own, which
/// the actor's property accessors notify at the write, and the snapshot's,
/// which are notified only when a refresh has published a snapshot, after it
/// has released its lock. It also holds the published snapshot.
@available(SwiftStdlib 6.5, *)
public final class ObservableSnapshotRegistrar<Snapshot: Sendable>: Sendable {
  /// The registrar that a snapshot's properties register their accesses with,
  /// and that notifies their observers.
  public let registrar: ObservationRegistrar

  private let actorRegistrar = ObservationRegistrar()
  private let propertyCount: Int
  private let published: Mutex<Snapshot>

  // The property indices written since the last refresh, a bit each. Those
  // from 63 up share the last, which stands for all of them. Only the actor
  // reads or writes it, so no ordering is needed.
  private let dirty = Atomic<UInt64>(0)

  /// - Parameters:
  ///   - propertyCount: The number of property indices a snapshot's
  ///     properties use: one more than the greatest.
  ///   - initial: Makes the initial snapshot, given the registrar its
  ///     properties register their accesses with.
  public init(propertyCount: Int, initial: (ObservationRegistrar) -> Snapshot) {
    let registrar = ObservationRegistrar()
    self.registrar = registrar
    self.propertyCount = propertyCount
    self.published = Mutex(initial(registrar))
  }

  // The actor's own observation, as `ObservationRegistrar`'s property index
  // entry points.

  /// Registers access to a property of the actor.
  public func access(propertyIndex: Int) {
    actorRegistrar.access(propertyIndex: propertyIndex)
  }

  /// A property observation called before setting a property of the actor.
  public func willSet(propertyIndex: Int) {
    actorRegistrar.willSet(propertyIndex: propertyIndex)
  }

  /// A property observation called after setting a property of the actor.
  public func didSet(propertyIndex: Int) {
    actorRegistrar.didSet(propertyIndex: propertyIndex)
  }

  /// Identifies a mutation of a property of the actor to its observers.
  public func withMutation<T, Failure: Error>(
    propertyIndex: Int,
    _ mutation: () throws(Failure) -> T
  ) throws(Failure) -> T {
    try actorRegistrar.withMutation(propertyIndex: propertyIndex, mutation)
  }

  /// A copy of the published snapshot.
  public var latest: Snapshot {
    published.withLock { $0 }
  }

  /// Marks a property out of date. The first write after a refresh schedules
  /// one on `source`, which can't start until the writing job reaches a
  /// suspension point; later writes find the snapshot already out of date and
  /// coalesce into it.
  ///
  /// `make` is called on `source` with the lock held; it must not read the
  /// registrar.
  public func invalidate<Source: Actor>(
    propertyIndex: Int,
    in source: Source,
    make: @escaping @Sendable (isolated Source) -> Snapshot
  ) {
    let bit: UInt64 = 1 << UInt64(min(max(propertyIndex, 0), 63))
    guard dirty.bitwiseOr(bit, ordering: .relaxed).oldValue == 0 else { return }
    Task { await refresh(on: source, make) }
  }

  private func refresh<Source: Actor>(
    on source: isolated Source,
    _ make: (isolated Source) -> Snapshot
  ) {
    refresh { make(source) }
  }

  /// Publishes the snapshot `make` returns, if a property is out of date,
  /// notifying the observers of those that are: before the lock is taken for
  /// `willSet`, and after it is released for `didSet`, so an observer reading
  /// the snapshot on `didSet` reads the new values.
  ///
  /// `make` is called with the lock held; it must not read the registrar.
  public func refresh(_ make: () -> Snapshot) {
    let changed = dirty.exchange(0, ordering: .relaxed)
    guard changed != 0 else { return }
    forEachPropertyIndex(in: changed) { registrar.willSet(propertyIndex: $0) }
    published.withLock { $0 = make() }
    forEachPropertyIndex(in: changed) { registrar.didSet(propertyIndex: $0) }
  }

  private func forEachPropertyIndex(in bits: UInt64, _ body: (Int) -> Void) {
    var remaining = bits
    while remaining != 0 {
      let bit = remaining.trailingZeroBitCount
      remaining &= remaining - 1
      if bit < 63 {
        body(bit)
      } else {
        for propertyIndex in 63..<max(propertyCount, 64) {
          body(propertyIndex)
        }
      }
    }
  }
}

#endif
