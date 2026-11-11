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

// There is one process-global epoch. Each registrar (so each observable
// object) has two stamps: the epoch it was last visited in by a cache's
// `input`, and the epoch of its last write that anything could have seen. A
// cache records the epoch it last computed in; it is clean while that is
// still the epoch, and otherwise recomputes only if a stamp it reads is
// newer.
//
// A write advances the epoch only if its object was visited in the current
// epoch, so a burst of writes nothing reads between advances it once, and a
// write to an object no cache has read since its last write touches nothing.
// The visited stamp is an epoch per object rather than a single visited bit,
// so it can never be lost to a concurrent write clearing the bit; it costs
// four bytes, which fit in the extent header's padding.
//
// Epochs are 30-bit and wrap, so two stamps are compared by how far each is
// behind an epoch freshly loaded from the global one, which no stamp is
// past, rather than by their distance from each other: that distance takes
// one 2^29 or more behind the other for newer, so a stamp that lagged that
// far would never be moved forward, and could leave a cache stale for good.
// Measured this way, only a stamp a whole wraparound (2^30 epochs) behind,
// less `skew`, is misjudged.

// Views a word the registrar keeps in an extent's header (an epoch stamp,
// its `observedMask`, or its `hasContext` flag) as the atomic it is only
// ever accessed as. `Atomic<Value>` has the layout of `Value`, and the header
// does not move for the extent's lifetime.
func _atomic<Value: AtomicRepresentable>(
  _ word: UnsafeMutablePointer<Value>
) -> UnsafeMutablePointer<Atomic<Value>> {
  UnsafeMutableRawPointer(word).assumingMemoryBound(to: Atomic<Value>.self)
}

// All accesses to the epoch and the stamps are relaxed: a cache's
// correctness only matters for reads ordered with the writes they depend on,
// which the program must order anyway.
enum _Epoch {
  static var mask: UInt32 { (1 << 30) - 1 }

  // Whether `a` is a later epoch than `b`, across wraparound, by their
  // distance alone. Only for tests; the stamps compare by `age(of:at:)`.
  static func isNewer(_ a: UInt32, than b: UInt32) -> Bool {
    let distance = (a &- b) & mask
    return distance != 0 && distance < (1 << 29)
  }

  // How far ahead of a thread's load of the epoch a stamp can be: stored by
  // another thread from a later epoch than that load saw, so by the few
  // epochs relaxed loads of different words can disagree by.
  static var skew: UInt32 { 1 << 20 }

  // How many epochs `stamp` is behind `current`, an epoch freshly loaded;
  // negative for one up to `skew` ahead of it, not almost a whole
  // wraparound behind. A later stamp has a lower age.
  static func age(of stamp: UInt32, at current: UInt32) -> Int32 {
    let distance = (current &- stamp) & mask
    if distance > mask - skew {
      return Int32(distance) - Int32(mask) - 1
    }
    return Int32(distance)
  }

  // The process-global epoch. It starts at 1, so that a stamp that has never
  // been visited (0) is older than a new object's mutation stamp (1).
  static let global = Atomic<UInt32>(1)

  static var current: UInt32 {
    global.load(ordering: .relaxed)
  }

  // Advances the epoch past `epoch`, unless another write already has, and
  // returns the epoch after.
  static func advance(from epoch: UInt32) -> UInt32 {
    let next = (epoch &+ 1) & mask
    let (exchanged, original) = global.compareExchange(
      expected: epoch, desired: next, ordering: .relaxed)
    return exchanged ? next : original
  }

  // Raises `word` to `epoch` if that is newer, atomically, so a concurrent
  // raise to an older epoch never lowers it. `current` is an epoch loaded
  // since `epoch` was, to measure both by.
  static func raise(_ word: UnsafeMutablePointer<UInt32>, to epoch: UInt32, at current: UInt32) {
    let target = age(of: epoch, at: current)
    let atomic = _atomic(word)
    var expected = atomic.pointee.load(ordering: .relaxed)
    while target < age(of: expected, at: current) {
      let (exchanged, original) = atomic.pointee.compareExchange(
        expected: expected, desired: epoch, ordering: .relaxed)
      if exchanged {
        return
      }
      expected = original
    }
  }

  // A read of the object with stamps `visited` and `mutated`, from inside
  // the cache's traversal `traversal`, the innermost on this thread: stamps
  // it visited in the traversal's epoch, and folds its mutation stamp into
  // the traversal.
  static func read(
    in traversal: UnsafeMutableRawPointer,
    visited: UnsafeMutablePointer<UInt32>,
    mutated: UnsafeMutablePointer<UInt32>
  ) {
    let frame = traversal.assumingMemoryBound(to: _TraversalFrame.self)
    // Not the traversal's epoch, which may be long past.
    let current = _Epoch.current
    raise(visited, to: frame.pointee.pinned, at: current)
    frame.pointee.include(_atomic(mutated).pointee.load(ordering: .relaxed), at: current)
  }

  // A write to the object with stamps `visited` and `mutated`, after its
  // value is stored: stamps it if a cache has read the object since its last
  // stamped write. Almost every write stops at the check, which finds its
  // mutation stamp newer than its visited stamp (otherwise any cache that
  // read it did so before that write, whose stamp is already newer than the
  // cache). Both are measured from an epoch loaded after them, rather than
  // by their distance from each other, which takes a stamp 2^29 or more
  // behind the other for newer and so could skip every write to an object
  // for good.
  static func write(
    visited: UnsafeMutablePointer<UInt32>,
    mutated: UnsafeMutablePointer<UInt32>
  ) {
    let lastVisited = _atomic(visited).pointee.load(ordering: .relaxed)
    let lastMutated = _atomic(mutated).pointee.load(ordering: .relaxed)
    let current = _Epoch.current
    if age(of: lastMutated, at: current) < age(of: lastVisited, at: current) {
      return
    }
    stampWrite(visited: visited, mutated: mutated)
  }

  // The rest of `write`, for the rare write that needs stamping; out of line.
  @inline(never)
  private static func stampWrite(
    visited: UnsafeMutablePointer<UInt32>,
    mutated: UnsafeMutablePointer<UInt32>
  ) {
    let lastVisited = _atomic(visited).pointee.load(ordering: .relaxed)
    var epoch = current
    // Visited in the current epoch (or, by `skew`, a later one): a cache
    // may be clean in it, having read the old value, so the epoch must move
    // on.
    if age(of: lastVisited, at: epoch) <= 0 {
      epoch = advance(from: epoch)
    }
    raise(mutated, to: epoch, at: epoch)
  }
}

// A cache's traversal under way on this thread, on that thread's stack:
// `_ThreadLocal.traversal` points at the innermost, and each at the one it
// is nested in (a cache's `input` may read other caches). Installed and
// removed with `_Traversals.push` and `pop`.
struct _TraversalFrame: @unchecked Sendable {
  // The cache computing, to trap a cycle rather than deadlock on its lock.
  let cache: Int
  // The epoch the outermost traversal started in; nested ones keep it.
  let pinned: UInt32
  let previous: UnsafeMutableRawPointer?
  // The newest mutation stamp read, if any was.
  var newest: UInt32 = 0
  var hasRead = false

  init(cache: Int, pinned: UInt32, previous: UnsafeMutableRawPointer?) {
    self.cache = cache
    self.pinned = pinned
    self.previous = previous
  }

  // Folds in `stamp`, measuring it and `newest` by `current`, an epoch
  // loaded since `stamp` was.
  mutating func include(_ stamp: UInt32, at current: UInt32) {
    if !hasRead || _Epoch.age(of: stamp, at: current) < _Epoch.age(of: newest, at: current) {
      newest = stamp
      hasRead = true
    }
  }
}

/// Whether epoch `a` is later than epoch `b`, comparing the low 30 bits
/// across wraparound. For tests.
@available(SwiftStdlib 6.5, *)
@_spi(Prototype)
public func _observationEpoch(_ a: UInt32, isNewerThan b: UInt32) -> Bool {
  _Epoch.isNewer(a, than: b)
}

/// Moves the global epoch forward by `distance`, modulo 2^30, as if that
/// many writes had advanced it. For tests of wraparound.
@available(SwiftStdlib 6.5, *)
@_spi(Prototype)
public func _observationEpochJump(by distance: UInt32) {
  let current = _Epoch.current
  _Epoch.global.store((current &+ distance) & _Epoch.mask, ordering: .relaxed)
}
