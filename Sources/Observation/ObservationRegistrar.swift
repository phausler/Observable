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

#if !$Embedded
// The identity of a property known only by its property index. Noncopyable types have
// no key paths, so their properties are observed through the property index-only entry
// points, and the registrar, whose tables are keyed by key path, records each
// such property index as a key path into this type instead: one per property index, distinct from
// every key path a program can form to a property of its own. They name no
// property, so `ObservationTracking.changed` is nil for a change made through
// them, and `Event.matches(_:)` is false.
//
// A property index-only property and a key-path property never share an identity, so
// a property observed through one form is not notified of mutations made
// through the other; a type uses one form for each property.
@available(SwiftStdlib 6.5, *)
internal struct _PropertyIndexIdentity {
  subscript(propertyIndex: Int) -> Int { propertyIndex }

  // Formed once, so that the identity comparisons the registrar makes before
  // hashing (`===`) hit; a key path with a subscript argument is otherwise a
  // new object every time it is formed. Property indices of 64 and above are formed
  // each time, and compare equal by hashing. Key paths are immutable, so
  // sharing them across threads is safe though `AnyKeyPath` isn't Sendable.
  private nonisolated(unsafe) static let common: ContiguousArray<AnyKeyPath> =
    ContiguousArray((0..<64).map { \_PropertyIndexIdentity.[$0] })

  static func keyPath(_ propertyIndex: Int) -> AnyKeyPath {
    propertyIndex >= 0 && propertyIndex < 64 ? common[propertyIndex] : \_PropertyIndexIdentity.[propertyIndex]
  }
}

// Names derived values in access lists, distinct from every stored property's
// key path.
@available(SwiftStdlib 5.9, *)
internal struct _DerivedIdentity {
  subscript(derived: Int) -> Int { derived }

  private nonisolated(unsafe) static let common: ContiguousArray<AnyKeyPath> =
    ContiguousArray((0..<64).map { \_DerivedIdentity.[$0] })

  static func keyPath(_ propertyIndex: Int) -> AnyKeyPath {
    propertyIndex >= 0 && propertyIndex < 64 ? common[propertyIndex] : \_DerivedIdentity.[propertyIndex]
  }
}
#else
// Stored-property indices are never negative, so a negative key can't collide
// with one.
internal enum _DerivedKey {
  static func key(_ propertyIndex: Int) -> Int { -1 - propertyIndex }
}
#endif

/// Provides storage for tracking and access to data changes.
///
/// You don't need to create an instance of `ObservationRegistrar` when using
/// the ``Observation/Observable()`` macro to indicate observability of a type.
@available(SwiftStdlib 5.9, *)
public struct ObservationRegistrar: Sendable {
  private struct State: @unchecked Sendable {
    // The kinds of change an observer record listens for; one record per
    // tracking per object carries all of them.
    struct Kinds: OptionSet {
      var rawValue: UInt8
      static var willSet: Kinds { Kinds(rawValue: 1 << 0) }
      static var didSet: Kinds { Kinds(rawValue: 1 << 1) }
      static var `deinit`: Kinds { Kinds(rawValue: 1 << 2) }
    }

    // Callbacks collected under the lock and run after it is released. They
    // go in `storage`, stack-backed temporary storage the caller provides
    // (see `Context.notify`), so collecting up to its capacity does not
    // allocate; any past that go in `spilled`. The caller deinitializes
    // them, with `deinitialize()`, before `storage` goes away.
    struct Callbacks<Callback> {
      private let storage: UnsafeMutableBufferPointer<Callback>
      private var count = 0
      private var spilled = [Callback]()

      init(storage: UnsafeMutableBufferPointer<Callback>) {
        self.storage = storage
      }

      mutating func append(_ callback: Callback) {
        if count < storage.count {
          storage.initializeElement(at: count, to: callback)
          count += 1
        } else {
          spilled.append(callback)
        }
      }

      func forEach(_ body: (Callback) -> Void) {
        for index in 0..<count {
          body(storage[index])
        }
        for callback in spilled {
          body(callback)
        }
      }

      mutating func deinitialize() {
        storage.baseAddress?.deinitialize(count: count)
        count = 0
        spilled = []
      }
    }

    private struct Observer {
      // Generation-tagged: every registration takes the next value of
      // `generation`, which is never reused, so a stale `cancel(_:)` for a
      // record that is gone matches nothing even after its property index in
      // `observers` has been reused by a newer record.
      let token: Int
      let kinds: Kinds
      // Bit `n` is set when the key path with ordinal `n` is observed;
      // ordinals of 64 and above go in `overflow`, sorted and without
      // duplicates (see `sortOverflow(_:)`) so it is binary-searched.
      let mask: UInt64
      let overflow: ContiguousArray<Int>?
      // What to notify: the tracking and its handlers (including the legacy
      // `onChange`) held directly, not captured in wrapper closures.
      let handlers: ObservationTracking.Handlers

      func observes(_ ordinal: Int) -> Bool {
        if ordinal < 64 {
          return mask & (1 << UInt64(ordinal)) != 0
        }
        guard let overflow else { return false }
        var low = 0
        var high = overflow.count
        while low < high {
          let middle = low + (high - low) / 2
          if overflow[middle] < ordinal {
            low = middle + 1
          } else {
            high = middle
          }
        }
        return low < overflow.count && overflow[low] == ordinal
      }
    }

    // Sorts the overflow ordinals a registration collected, and drops any
    // repeats, as `Observer.overflow` requires.
    private static func sortOverflow(_ overflow: inout ContiguousArray<Int>?) {
      guard var ordinals = overflow else { return }
      // Drop the optional's reference first so sorting in place does not copy.
      overflow = nil
      ordinals.sort()
      var kept = 0
      for index in ordinals.indices where kept == 0 || ordinals[index] != ordinals[kept - 1] {
        ordinals[kept] = ordinals[index]
        kept += 1
      }
      ordinals.removeLast(ordinals.count - kept)
      overflow = ordinals
    }

    #if !$Embedded
    // Key paths are only ever interned by a registration, never by a
    // mutation, and ordinals are never reused while the table is alive: a
    // key path's ordinal is the table's count when it was interned, so the
    // ordinals stay dense from 0. Hashed, so a mutation resolves its key path
    // in O(1) however many are interned, for a miss as well as a hit.
    private var ordinals = [AnyKeyPath: Int]()
    // The most recently interned key path. Key path literals are uniqued per
    // pattern, so a mutation of the one property just observed matches this
    // by identity and skips hashing.
    private var lastKeyPath: AnyKeyPath?
    private var lastOrdinal = 0
    private struct PropertyIndexEntry {
      // The key path with this entry's ordinal. A property index-tagged mutation
      // whose property index is its key path's ordinal resolves here by identity,
      // without hashing.
      let keyPath: AnyKeyPath
      // The property index that property index-tagged mutations of that key path pass, learned
      // the first time one takes the lock. A macro-assigned property index is its
      // property's declaration order, not the order properties happen to be
      // interned in, so it is not the ordinal in general, and
      // `observedMask` has to be in terms of property indices.
      var mutationPropertyIndex: Int
    }
    // The other direction of `ordinals`, kept in lockstep by `intern(_:)`:
    // `propertyIndices[n]` is the entry for ordinal `n`. One array, so one allocation.
    private var propertyIndices = ContiguousArray<PropertyIndexEntry>()
    private static var unknownPropertyIndex: Int { -1 }
    // Passed with two different property indices: the mask can't name it by one.
    private static var conflictingPropertyIndex: Int { -2 }
    #endif
    // The extent header's `observedMask`, stored to (relaxed, under this
    // lock) whenever its value changes; `publishedMask` is its value. The
    // extent clears the pointer, through `deinitialize()`, before its memory
    // goes away, so a context outliving its extent never stores to it.
    var observedMask: UnsafeMutablePointer<UInt64>?
    private var publishedMask = UInt64(0)
    // Dense: cancelling swap-removes, so order is not registration order.
    private var observers = ContiguousArray<Observer>()
    private var generation = 0

    // Past `indexThreshold` records, finding a record by token (to cancel
    // it) and the records observing an ordinal (to notify them) go through
    // this instead of scanning every record, so their cost does not grow
    // with the number of observers of other properties. Nil below that
    // (and dropped again below half of it), where a scan is cheaper than
    // keeping the index.
    private struct ObserverIndex {
      // The position in `observers` of each record, by token.
      var positions = [Int: Int]()
      // The positions of the willSet or didSet records observing each
      // ordinal; an ordinal no such record observes has no entry.
      var observing = [Int: Set<Int>]()
    }
    private var observerIndex: ObserverIndex?
    private static var indexThreshold: Int { 32 }

    // The ordinals a mutation of which `observer` is notified of.
    private static func forEachOrdinal(of observer: Observer, _ body: (Int) -> Void) {
      if observer.kinds.isDisjoint(with: [.willSet, .didSet]) {
        return
      }
      var mask = observer.mask
      while mask != 0 {
        body(mask.trailingZeroBitCount)
        mask &= mask - 1
      }
      observer.overflow?.forEach(body)
    }

    private mutating func indexInsert(_ observer: Observer, at position: Int) {
      observerIndex!.positions[observer.token] = position
      Self.forEachOrdinal(of: observer) { ordinal in
        observerIndex!.observing[ordinal, default: []].insert(position)
      }
    }

    private mutating func indexRemove(_ observer: Observer, at position: Int) {
      observerIndex!.positions[observer.token] = nil
      Self.forEachOrdinal(of: observer) { ordinal in
        observerIndex!.observing[ordinal]?.remove(position)
        if observerIndex!.observing[ordinal]?.isEmpty ?? false {
          observerIndex!.observing[ordinal] = nil
        }
      }
    }

    private mutating func appendObserver(_ observer: Observer) {
      observers.append(observer)
      if observerIndex != nil {
        indexInsert(observer, at: observers.count - 1)
      } else if observers.count > Self.indexThreshold {
        observerIndex = ObserverIndex()
        for position in observers.indices {
          indexInsert(observers[position], at: position)
        }
      }
    }

    private func position(ofToken token: Int) -> Int? {
      if let observerIndex {
        return observerIndex.positions[token]
      }
      return observers.firstIndex { $0.token == token }
    }

    // Swap-removes the record at `position`, moving the last one into it.
    private mutating func removeObserver(at position: Int) -> Observer {
      let last = observers.count - 1
      if observerIndex != nil {
        indexRemove(observers[position], at: position)
        if position != last {
          let moved = observers[last]
          indexRemove(moved, at: last)
          indexInsert(moved, at: position)
        }
      }
      observers.swapAt(position, last)
      let observer = observers.removeLast()
      if observerIndex != nil && observers.count < Self.indexThreshold / 2 {
        observerIndex = nil
      }
      return observer
    }

    private mutating func removeAllObservers() {
      observers.removeAll()
      observerIndex = nil
    }

    // A clear bit must mean no willSet or didSet observer observes a key
    // path mutated with that property index; a set bit may be stale, and only costs
    // taking the lock.
    private mutating func publish(_ mask: UInt64) {
      guard mask != publishedMask else { return }
      publishedMask = mask
      if let observedMask {
        _atomic(observedMask).pointee.store(mask, ordering: .relaxed)
      }
    }

    #if !$Embedded
    // Resolves a mutated key path to its ordinal.
    private func ordinal(of keyPath: AnyKeyPath) -> Int? {
      if lastKeyPath === keyPath {
        return lastOrdinal
      }
      return ordinals[keyPath]
    }

    private mutating func intern(_ keyPath: AnyKeyPath) -> Int {
      if let ordinal = ordinal(of: keyPath) {
        return ordinal
      }
      let ordinal = ordinals.count
      ordinals[keyPath] = ordinal
      // A property index-only property's property index is known from its identity, so the mask
      // is exact from its first registration rather than its first mutation.
      var mutationPropertyIndex = Self.unknownPropertyIndex
      if #available(SwiftStdlib 6.5, *),
         let propertyIndexKeyPath = keyPath as? KeyPath<_PropertyIndexIdentity, Int> {
        mutationPropertyIndex = _PropertyIndexIdentity()[keyPath: propertyIndexKeyPath]
      }
      propertyIndices.append(PropertyIndexEntry(keyPath: keyPath, mutationPropertyIndex: mutationPropertyIndex))
      lastKeyPath = keyPath
      lastOrdinal = ordinal
      return ordinal
    }

    // The `observedMask` bit for mutations of the key path with `ordinal`:
    // its property index's, or every bit while its property index is unknown, since any property index
    // might then be its. Property indices of 64 and above have no bit (they always
    // take the lock).
    private func propertyIndexBits(forOrdinal ordinal: Int) -> UInt64 {
      let propertyIndex = propertyIndices[ordinal].mutationPropertyIndex
      if propertyIndex < 0 {
        return .max
      }
      return propertyIndex < 64 ? 1 << UInt64(propertyIndex) : 0
    }

    private func propertyIndexBits(of observer: Observer) -> UInt64 {
      if observer.kinds.isDisjoint(with: [.willSet, .didSet]) {
        return 0
      }
      var bits = UInt64(0)
      var mask = observer.mask
      while mask != 0 {
        bits |= propertyIndexBits(forOrdinal: mask.trailingZeroBitCount)
        mask &= mask - 1
      }
      observer.overflow?.forEach { bits |= propertyIndexBits(forOrdinal: $0) }
      return bits
    }

    private mutating func republish() {
      var mask = UInt64(0)
      if let observerIndex {
        // The index has an entry for exactly the ordinals willSet or didSet
        // records observe, which are the ordinals `propertyIndexBits(of:)` covers.
        for ordinal in observerIndex.observing.keys where mask != .max {
          mask |= propertyIndexBits(forOrdinal: ordinal)
        }
      } else {
        for observer in observers where mask != .max {
          mask |= propertyIndexBits(of: observer)
        }
      }
      publish(mask)
    }

    // Called with the property index a property index-tagged mutation passed for the key path
    // with `ordinal`. The macro passes the same property index for a key path every
    // time, so this changes the mask at most once per key path.
    private mutating func learn(_ propertyIndex: Int, forOrdinal ordinal: Int) {
      let known = propertyIndices[ordinal].mutationPropertyIndex
      guard propertyIndex >= 0, known != propertyIndex, known != Self.conflictingPropertyIndex else { return }
      propertyIndices[ordinal].mutationPropertyIndex = known == Self.unknownPropertyIndex ? propertyIndex : Self.conflictingPropertyIndex
      republish()
    }

    internal mutating func registerTracking(
      for properties: ObservationTracking.SmallArray<AnyKeyPath>,
      handlers: ObservationTracking.Handlers
    ) -> Int {
      generation &+= 1
      let token = generation
      var kinds = Kinds()
      if handlers.observesWillSet { kinds.insert(.willSet) }
      if handlers.observesDidSet { kinds.insert(.didSet) }
      if handlers.observesDeinit { kinds.insert(.deinit) }
      if kinds.isEmpty {
        return token
      }
      var mask = UInt64(0)
      var overflow: ContiguousArray<Int>?
      // A deinit-only record matches no key path, so it interns nothing.
      // `properties` may repeat a key path; interning and setting its bit
      // again are no-ops, and `sortOverflow` drops a repeated overflow
      // ordinal.
      if !kinds.isDisjoint(with: [.willSet, .didSet]) {
        properties.forEach { property in
          let ordinal = intern(property)
          if ordinal < 64 {
            mask |= 1 << UInt64(ordinal)
          } else {
            if overflow == nil { overflow = [] }
            overflow!.append(ordinal)
          }
        }
        Self.sortOverflow(&overflow)
      }
      let observer = Observer(
        token: token,
        kinds: kinds,
        mask: mask,
        overflow: overflow,
        handlers: handlers
      )
      appendObserver(observer)
      publish(publishedMask | propertyIndexBits(of: observer))
      return token
    }
    
    internal mutating func cancel(_ token: Int) {
      guard let position = position(ofToken: token) else { return }
      let observer = removeObserver(at: position)
      if propertyIndexBits(of: observer) != 0 {
        republish()
      }
    }

    // Cancels records by token for as long as `batch` calls its argument,
    // republishing the mask once at the end rather than once per record. The
    // result is the mask a sequence of single cancels leaves, since each of
    // those also recomputes it from the records that remain.
    internal mutating func cancel(batch: ((Int) -> Void) -> Void) {
      var removedBits = UInt64(0)
      batch { token in
        if let position = position(ofToken: token) {
          removedBits |= propertyIndexBits(of: removeObserver(at: position))
        }
      }
      if removedBits != 0 {
        republish()
      }
    }

    // Re-arms the record with `token` for a re-evaluated tracking. If the
    // record would be registered unchanged (the same kinds, and the same
    // ordinals for `properties`), it is kept, notifying `handlers` from now
    // on, and `token` is returned; the mask cannot change, since its bits
    // come only from the kinds and ordinals. Otherwise, or if the record is
    // gone, it is cancelled and a new one registered. The ordinals are
    // computed as `registerTracking` computes them; it is not factored to
    // share this, to keep its path unchanged.
    internal mutating func updateTracking(
      _ token: Int,
      for properties: ObservationTracking.SmallArray<AnyKeyPath>,
      handlers: ObservationTracking.Handlers
    ) -> Int {
      guard let index = position(ofToken: token) else {
        return registerTracking(for: properties, handlers: handlers)
      }
      var kinds = Kinds()
      if handlers.observesWillSet { kinds.insert(.willSet) }
      if handlers.observesDidSet { kinds.insert(.didSet) }
      if handlers.observesDeinit { kinds.insert(.deinit) }
      var mask = UInt64(0)
      var overflow: ContiguousArray<Int>?
      if !kinds.isDisjoint(with: [.willSet, .didSet]) {
        properties.forEach { property in
          let ordinal = intern(property)
          if ordinal < 64 {
            mask |= 1 << UInt64(ordinal)
          } else {
            if overflow == nil { overflow = [] }
            overflow!.append(ordinal)
          }
        }
        Self.sortOverflow(&overflow)
      }
      let observer = observers[index]
      // Both overflows are sorted and free of repeats, so equal sets are
      // equal arrays.
      guard observer.kinds == kinds, observer.mask == mask, observer.overflow == overflow else {
        cancel(token)
        return registerTracking(for: properties, handlers: handlers)
      }
      // Replaced with the same token, kinds and ordinals, so the index
      // (which is keyed by those) needs no update.
      observers[index] = Observer(
        token: token,
        kinds: kinds,
        mask: mask,
        overflow: observer.overflow,
        handlers: handlers
      )
      return token
    }

    internal mutating func deinitialize(
      into trackers: inout Callbacks<ObservationTracking.Handlers>
    ) {
      for observer in observers where observer.kinds.contains(.deinit) {
        trackers.append(observer.handlers)
      }
      removeAllObservers()
      ordinals.removeAll()
      propertyIndices.removeAll()
      lastKeyPath = nil
      publish(0)
      observedMask = nil
    }

    private func trackers(
      for keyPath: AnyKeyPath,
      _ kind: Kinds,
      into trackers: inout Callbacks<ObservationTracking.Handlers>
    ) {
      guard !observers.isEmpty, let ordinal = ordinal(of: keyPath) else {
        return
      }
      self.trackers(forOrdinal: ordinal, kind, into: &trackers)
    }

    // A property index-tagged mutation: `propertyIndices[propertyIndex].keyPath === keyPath` is an ordinal hit;
    // otherwise (a property index that is not the ordinal, out of range, or never
    // interned) it resolves exactly as the key-path-only mutation does.
    private mutating func trackers(
      for keyPath: AnyKeyPath,
      propertyIndex: Int,
      _ kind: Kinds,
      into trackers: inout Callbacks<ObservationTracking.Handlers>
    ) {
      guard !observers.isEmpty else {
        return
      }
      let ordinal: Int
      if propertyIndex >= 0 && propertyIndex < propertyIndices.count && propertyIndices[propertyIndex].keyPath === keyPath {
        ordinal = propertyIndex
      } else if let found = self.ordinal(of: keyPath) {
        ordinal = found
      } else {
        return
      }
      learn(propertyIndex, forOrdinal: ordinal)
      self.trackers(forOrdinal: ordinal, kind, into: &trackers)
    }
    #else
    // Embedded has no key paths to intern: the macro-assigned property index each
    // access recorded is used as the ordinal directly, so it is the bit in
    // `Observer.mask` (or the entry in `overflow`).
    internal mutating func registerTracking(
      for properties: ObservationTracking.SmallArray<Int>,
      handlers: ObservationTracking.Handlers
    ) -> Int {
      generation &+= 1
      let token = generation
      var kinds = Kinds()
      if handlers.observesWillSet { kinds.insert(.willSet) }
      if handlers.observesDidSet { kinds.insert(.didSet) }
      if handlers.observesDeinit { kinds.insert(.deinit) }
      if kinds.isEmpty {
        return token
      }
      var mask = UInt64(0)
      var overflow: ContiguousArray<Int>?
      // A negative property index names no property, and no mutation matches one.
      if !kinds.isDisjoint(with: [.willSet, .didSet]) {
        properties.forEach { propertyIndex in
          if propertyIndex < 0 {
            return
          }
          if propertyIndex < 64 {
            mask |= 1 << UInt64(propertyIndex)
          } else {
            if overflow == nil { overflow = [] }
            overflow!.append(propertyIndex)
          }
        }
        Self.sortOverflow(&overflow)
      }
      let observer = Observer(
        token: token,
        kinds: kinds,
        mask: mask,
        overflow: overflow,
        handlers: handlers
      )
      appendObserver(observer)
      publish(publishedMask | propertyIndexBits(of: observer))
      return token
    }

    // Re-arms the record with `token` as the non-Embedded `updateTracking`
    // does, for `ObservationTracking.Listener`: kept (and `token` returned)
    // if it would be registered unchanged, with the same kinds and property indices;
    // otherwise, or if it is gone, cancelled and a new one registered. The
    // property indices are computed as `registerTracking` computes them.
    internal mutating func updateTracking(
      _ token: Int,
      for properties: ObservationTracking.SmallArray<Int>,
      handlers: ObservationTracking.Handlers
    ) -> Int {
      guard let index = position(ofToken: token) else {
        return registerTracking(for: properties, handlers: handlers)
      }
      var kinds = Kinds()
      if handlers.observesWillSet { kinds.insert(.willSet) }
      if handlers.observesDidSet { kinds.insert(.didSet) }
      if handlers.observesDeinit { kinds.insert(.deinit) }
      var mask = UInt64(0)
      var overflow: ContiguousArray<Int>?
      if !kinds.isDisjoint(with: [.willSet, .didSet]) {
        properties.forEach { propertyIndex in
          if propertyIndex < 0 {
            return
          }
          if propertyIndex < 64 {
            mask |= 1 << UInt64(propertyIndex)
          } else {
            if overflow == nil { overflow = [] }
            overflow!.append(propertyIndex)
          }
        }
        Self.sortOverflow(&overflow)
      }
      let observer = observers[index]
      // Both overflows are sorted and free of repeats, so equal sets are
      // equal arrays.
      guard observer.kinds == kinds, observer.mask == mask, observer.overflow == overflow else {
        cancel(token)
        return registerTracking(for: properties, handlers: handlers)
      }
      // Replaced with the same token, kinds and property indices, so neither the index
      // nor the published mask needs an update.
      observers[index] = Observer(
        token: token,
        kinds: kinds,
        mask: mask,
        overflow: observer.overflow,
        handlers: handlers
      )
      return token
    }

    // The `observedMask` bits for mutations `observer` is notified of. A
    // property index is its property's ordinal, so these are just its mask's bits;
    // property indices of 64 and above have no bit (they always take the lock).
    private func propertyIndexBits(of observer: Observer) -> UInt64 {
      observer.kinds.isDisjoint(with: [.willSet, .didSet]) ? 0 : observer.mask
    }

    private mutating func republish() {
      var mask = UInt64(0)
      if let observerIndex {
        // The index has an entry for exactly the property indices willSet or didSet
        // records observe.
        for propertyIndex in observerIndex.observing.keys where propertyIndex < 64 {
          mask |= 1 << UInt64(propertyIndex)
        }
      } else {
        for observer in observers {
          mask |= propertyIndexBits(of: observer)
        }
      }
      publish(mask)
    }

    internal mutating func cancel(_ token: Int) {
      guard let position = position(ofToken: token) else { return }
      let observer = removeObserver(at: position)
      if propertyIndexBits(of: observer) != 0 {
        republish()
      }
    }

    internal mutating func deinitialize(
      into trackers: inout Callbacks<ObservationTracking.Handlers>
    ) {
      for observer in observers where observer.kinds.contains(.deinit) {
        trackers.append(observer.handlers)
      }
      removeAllObservers()
      publish(0)
      observedMask = nil
    }
    #endif

    private func trackers(
      forOrdinal ordinal: Int,
      _ kind: Kinds,
      into trackers: inout Callbacks<ObservationTracking.Handlers>
    ) {
      if let observerIndex {
        guard let positions = observerIndex.observing[ordinal] else {
          return
        }
        // In `observers` order, as the scan below notifies them.
        if positions.count == 1 {
          let observer = observers[positions.first!]
          if observer.kinds.contains(kind) {
            trackers.append(observer.handlers)
          }
          return
        }
        // Sorted in stack-backed temporary storage, not a new array.
        withUnsafeTemporaryAllocation(of: Int.self, capacity: positions.count) { buffer in
          var count = 0
          for position in positions where observers[position].kinds.contains(kind) {
            buffer.initializeElement(at: count, to: position)
            count += 1
          }
          var sorted = UnsafeMutableBufferPointer(rebasing: buffer[..<count])
          sorted.sort()
          for position in sorted {
            trackers.append(observers[position].handlers)
          }
        }
        return
      }
      for observer in observers where observer.kinds.contains(kind) && observer.observes(ordinal) {
        trackers.append(observer.handlers)
      }
    }
    
    #if !$Embedded
    internal func willSet(
      keyPath: AnyKeyPath,
      into trackers: inout Callbacks<ObservationTracking.Handlers>
    ) {
      self.trackers(for: keyPath, .willSet, into: &trackers)
    }
    
    internal func didSet(
      keyPath: AnyKeyPath,
      into trackers: inout Callbacks<ObservationTracking.Handlers>
    ) {
      self.trackers(for: keyPath, .didSet, into: &trackers)
    }

    internal mutating func willSet(
      keyPath: AnyKeyPath,
      propertyIndex: Int,
      into trackers: inout Callbacks<ObservationTracking.Handlers>
    ) {
      self.trackers(for: keyPath, propertyIndex: propertyIndex, .willSet, into: &trackers)
    }

    internal mutating func didSet(
      keyPath: AnyKeyPath,
      propertyIndex: Int,
      into trackers: inout Callbacks<ObservationTracking.Handlers>
    ) {
      self.trackers(for: keyPath, propertyIndex: propertyIndex, .didSet, into: &trackers)
    }
    #else
    // A property index is its property's ordinal: no interning, and nothing to resolve.
    internal func willSet(
      propertyIndex: Int,
      into trackers: inout Callbacks<ObservationTracking.Handlers>
    ) {
      guard propertyIndex >= 0, !observers.isEmpty else { return }
      self.trackers(forOrdinal: propertyIndex, .willSet, into: &trackers)
    }

    internal func didSet(
      propertyIndex: Int,
      into trackers: inout Callbacks<ObservationTracking.Handlers>
    ) {
      guard propertyIndex >= 0, !observers.isEmpty else { return }
      self.trackers(forOrdinal: propertyIndex, .didSet, into: &trackers)
    }
    #endif
  }
  
  internal struct Context: Sendable {
    private let state: _ManagedCriticalState<State>

    // `observedMask` is the extent header's word, which this context
    // keeps current while the extent is alive.
    init(observedMask: UnsafeMutablePointer<UInt64>) {
      var state = State()
      state.observedMask = observedMask
      self.state = _ManagedCriticalState(state)
    }
    
    // Most notifications deliver to one or two trackings, so room for two
    // handlers goes on the stack; any more spill to the heap. A larger
    // buffer would be reserved at every level of recursive delivery (a
    // handler that writes another observed property), whether used or not.
    private static var inlineCallbackCapacity: Int { 2 }

    // Collects the handlers to notify under the lock, into stack-backed
    // temporary storage (an array only past `inlineCallbackCapacity` of
    // them), and passes each to `body` once the lock is released.
    private func notify(
      _ collect: (inout State, inout State.Callbacks<ObservationTracking.Handlers>) -> Void,
      _ body: (ObservationTracking.Handlers) -> Void
    ) {
      withUnsafeTemporaryAllocation(
        of: ObservationTracking.Handlers.self,
        capacity: Context.inlineCallbackCapacity
      ) { storage in
        var trackers = State.Callbacks(storage: storage)
        state.withCriticalRegion { collect(&$0, &trackers) }
        trackers.forEach(body)
        trackers.deinitialize()
      }
    }

    internal var id: ObjectIdentifier { state.id }
    
    #if !$Embedded
    /// Registers one observer record for a tracking, covering every kind of
    /// change `handlers` has a handler for. Its `willSet`/`didSet` handlers
    /// are notified of mutations of `properties`; its `deinit` handler once
    /// when the observed object is deinitialized.
    /// Returns the token to pass to `cancel(_:)`; tokens are never reused, so
    /// cancelling one twice, or after the object is gone, does nothing.
    internal func registerTracking(
      for properties: ObservationTracking.SmallArray<AnyKeyPath>,
      handlers: ObservationTracking.Handlers
    ) -> Int {
      state.withCriticalRegion {
        $0.registerTracking(for: properties, handlers: handlers)
      }
    }

    /// Re-arms the observer record with `token` for a re-evaluated tracking,
    /// keeping it (and returning `token`) if `properties` and `handlers`
    /// would register it unchanged; otherwise cancels it and registers a new
    /// one, returning the new token.
    internal func updateTracking(
      _ token: Int,
      for properties: ObservationTracking.SmallArray<AnyKeyPath>,
      handlers: ObservationTracking.Handlers
    ) -> Int {
      state.withCriticalRegion {
        $0.updateTracking(token, for: properties, handlers: handlers)
      }
    }

    /// Runs `batch` with the lock held once, for it to register any number of
    /// observer records through its argument, as `registerTracking` does.
    /// `batch` must not call out to anything that could take another lock.
    internal func registerTrackings(
      _ batch: ((ObservationTracking.SmallArray<AnyKeyPath>, ObservationTracking.Handlers) -> Int) -> Void
    ) {
      state.withCriticalRegion { state in
        batch { state.registerTracking(for: $0, handlers: $1) }
      }
    }

    /// Runs `batch` with the lock held once, for it to cancel any number of
    /// records by token through its argument, as `cancel(_:)` does. The same
    /// restriction on `batch` applies.
    internal func cancelTrackings(_ batch: ((Int) -> Void) -> Void) {
      state.withCriticalRegion { $0.cancel(batch: batch) }
    }
    #else
    // Under Embedded, `properties` are the accessed properties' property indices.
    internal func registerTracking(
      for properties: ObservationTracking.SmallArray<Int>,
      handlers: ObservationTracking.Handlers
    ) -> Int {
      state.withCriticalRegion {
        $0.registerTracking(for: properties, handlers: handlers)
      }
    }

    // As the non-Embedded `updateTracking(_:for:handlers:)`, with property indices.
    internal func updateTracking(
      _ token: Int,
      for properties: ObservationTracking.SmallArray<Int>,
      handlers: ObservationTracking.Handlers
    ) -> Int {
      state.withCriticalRegion {
        $0.updateTracking(token, for: properties, handlers: handlers)
      }
    }
    #endif
    
    internal func cancel(_ id: Int) {
      state.withCriticalRegion { $0.cancel(id) }
    }

    internal func deinitialize() {
      notify({ $0.deinitialize(into: &$1) }) { handlers in
        handlers.notifyDeinit()
      }
    }
    
    #if !$Embedded
    internal func willSet<Subject: Observable, Member>(
       _ subject: Subject,
       keyPath: KeyPath<Subject, Member>
    ) {
      notify({ $0.willSet(keyPath: keyPath, into: &$1) }) { handlers in
        handlers.notifyWillSet(keyPath)
      }
    }
    
    internal func didSet<Subject: Observable, Member>(
      _ subject: Subject,
      keyPath: KeyPath<Subject, Member>
    ) {
      notify({ $0.didSet(keyPath: keyPath, into: &$1) }) { handlers in
        handlers.notifyDidSet(keyPath)
      }
    }

    internal func willSet(keyPath: AnyKeyPath, propertyIndex: Int) {
      notify({ $0.willSet(keyPath: keyPath, propertyIndex: propertyIndex, into: &$1) }) { handlers in
        handlers.notifyWillSet(keyPath)
      }
    }

    internal func didSet(keyPath: AnyKeyPath, propertyIndex: Int) {
      notify({ $0.didSet(keyPath: keyPath, propertyIndex: propertyIndex, into: &$1) }) { handlers in
        handlers.notifyDidSet(keyPath)
      }
    }

    // A property index-only mutation: the property index's `_PropertyIndexIdentity` key path stands for
    // the property in the tables, and no key path is reported as `changed`.
    @available(SwiftStdlib 6.5, *)
    internal func willSet(propertyIndex: Int) {
      let keyPath = _PropertyIndexIdentity.keyPath(propertyIndex)
      notify({ $0.willSet(keyPath: keyPath, propertyIndex: propertyIndex, into: &$1) }) { handlers in
        handlers.notifyWillSet(nil)
      }
    }

    @available(SwiftStdlib 6.5, *)
    internal func didSet(propertyIndex: Int) {
      let keyPath = _PropertyIndexIdentity.keyPath(propertyIndex)
      notify({ $0.didSet(keyPath: keyPath, propertyIndex: propertyIndex, into: &$1) }) { handlers in
        handlers.notifyDidSet(nil)
      }
    }
    #else
    internal func willSet(propertyIndex: Int) {
      notify({ $0.willSet(propertyIndex: propertyIndex, into: &$1) }) { handlers in
        handlers.notifyWillSet()
      }
    }

    internal func didSet(propertyIndex: Int) {
      notify({ $0.didSet(propertyIndex: propertyIndex, into: &$1) }) { handlers in
        handlers.notifyDidSet()
      }
    }
    #endif
  }

  // The registrar's only eager allocation: one ManagedBuffer whose header is
  // the (lazily created) observer table and whose element is the lock that
  // guards creating it. Most objects are never observed, so they never pay
  // for the table.
  //
  // Note: "one allocation" holds for UNOBSERVED objects only. Once an object
  // is observed there are two: the extent plus the table's own
  // `_ManagedCriticalState` buffer inside `Context`.
  //
  // `Context` deliberately owns the table, not the extent: access lists (and
  // through them the observer closures stored in the table) hold contexts, so
  // a context holding the extent would keep it alive forever and the deinit
  // observers below would never fire.
  #if !$Embedded
  private struct ExtentHeader {
    // Written once, under the extent's lock, before `hasContext` is set
    // (and read in its deinit); read without the lock only after an acquire
    // load of `hasContext` has seen it set.
    var context: Context?
    // Set once, under the lock, when `context` is created, with release
    // ordering, so that it publishes `context`; otherwise only accessed
    // atomically, through `_atomic`. Placed after `context`; with
    // `observedMask` below, the extent takes a 48-byte malloc block.
    var hasContext: Bool
    // The object's epoch stamps (see Epoch.swift): the epoch a cache's
    // traversal last visited it in, and that of its last write anything
    // could have seen. Only accessed atomically, through `_atomic`. Placed in
    // the padding around `observedMask`, so the extent still takes 48 bytes.
    var visitedStamp: UInt32
    // Bit `s` is set when a willSet or didSet observer may observe a key path
    // that property index-tagged mutations pass property index `s` for. Written only by the
    // context, under its own lock; otherwise, like `hasContext`, only
    // accessed atomically.
    var observedMask: UInt64
    var mutatedStamp: UInt32
  }
  #else
  // Embedded's property indices are its ordinals, so `observedMask` needs no learning:
  // bit `s` is simply whether an observer may observe property index `s`.
  private struct ExtentHeader {
    // Bit `s` is set when a willSet or didSet observer may observe the
    // property with property index `s`. Written only by the context, under its own
    // lock; otherwise, like `hasContext`, only accessed atomically. First,
    // so that it is at offset 0.
    var observedMask: UInt64
    // Set once, under the lock, when `context` is created, with release
    // ordering, so that it publishes `context`; otherwise only accessed
    // atomically, through `_atomic`. Second, so that it is at the offset just
    // past `observedMask` (a `Bool` needs no padding).
    var hasContext: Bool
    // The object's epoch stamps, as above. `visitedStamp` fills the padding
    // after `hasContext`, and `mutatedStamp` follows `context`.
    var visitedStamp: UInt32
    // Written once, under the extent's lock, before `hasContext` is set
    // (and read in its deinit); read without the lock only after an acquire
    // load of `hasContext` has seen it set.
    var context: Context?
    var mutatedStamp: UInt32
  }
  #endif

  private final class Extent: ManagedBuffer<ExtentHeader, Lock.Primitive> {
    #if !$Embedded
    private static let hasContextOffset = MemoryLayout<ExtentHeader>.offset(of: \ExtentHeader.hasContext)!
    private static let observedMaskOffset = MemoryLayout<ExtentHeader>.offset(of: \ExtentHeader.observedMask)!
    private static let visitedStampOffset = MemoryLayout<ExtentHeader>.offset(of: \ExtentHeader.visitedStamp)!
    private static let mutatedStampOffset = MemoryLayout<ExtentHeader>.offset(of: \ExtentHeader.mutatedStamp)!
    #else
    // Stored properties are laid out in declaration order
    // (`MemoryLayout.offset(of:)` takes a key path, which Embedded lacks).
    private static var hasContextOffset: Int { MemoryLayout<UInt64>.size }
    private static var observedMaskOffset: Int { 0 }
    private static var visitedStampOffset: Int { hasContextOffset + MemoryLayout<UInt32>.size }
    // `context` follows at 16, pointer-aligned on 32- and 64-bit targets;
    // its size is a multiple of 4, so `mutatedStamp` directly follows it.
    private static var mutatedStampOffset: Int { 16 + MemoryLayout<Context?>.size }
    #endif

    static func allocate() -> Extent {
      let buffer = Extent.create(minimumCapacity: 1) { buffer in
        buffer.withUnsafeMutablePointerToElements { Lock.initialize($0) }
        #if !$Embedded
        return ExtentHeader(
          context: nil, hasContext: false, visitedStamp: 0,
          observedMask: 0, mutatedStamp: 1)
        #else
        return ExtentHeader(
          observedMask: 0, hasContext: false, visitedStamp: 0,
          context: nil, mutatedStamp: 1)
        #endif
      }
      return unsafeDowncast(buffer, to: Extent.self)
    }

    private static func hasContextFlag(
      _ header: UnsafeMutablePointer<ExtentHeader>
    ) -> UnsafeMutablePointer<Bool> {
      (UnsafeMutableRawPointer(header) + hasContextOffset)
        .assumingMemoryBound(to: Bool.self)
    }

    private static func observedMaskWord(
      _ header: UnsafeMutablePointer<ExtentHeader>
    ) -> UnsafeMutablePointer<UInt64> {
      (UnsafeMutableRawPointer(header) + observedMaskOffset)
        .assumingMemoryBound(to: UInt64.self)
    }

    private static func stampWord(
      _ header: UnsafeMutablePointer<ExtentHeader>, at offset: Int
    ) -> UnsafeMutablePointer<UInt32> {
      (UnsafeMutableRawPointer(header) + offset)
        .assumingMemoryBound(to: UInt32.self)
    }

    // An access from inside the cache's traversal `traversal`, the innermost
    // on this thread: stamps the object visited. The stamp moves only once
    // per epoch.
    func noteRead(in traversal: UnsafeMutableRawPointer) {
      withUnsafeMutablePointerToHeader { header in
        _Epoch.read(
          in: traversal,
          visited: Extent.stampWord(header, at: Extent.visitedStampOffset),
          mutated: Extent.stampWord(header, at: Extent.mutatedStampOffset))
      }
    }

    // A mutation by a property index-tagged didSet, after the value is stored: stamps
    // it if a cache has read the object since its last stamped write, and
    // returns `mayObserve(propertyIndex:)`.
    func noteWrite(mayObservePropertyIndex propertyIndex: Int) -> Bool {
      withUnsafeMutablePointerToHeader { header in
        _Epoch.write(
          visited: Extent.stampWord(header, at: Extent.visitedStampOffset),
          mutated: Extent.stampWord(header, at: Extent.mutatedStampOffset))
      }
      return mayObserve(propertyIndex: propertyIndex)
    }

    // The same for a key-path-only didSet, returning `existingContext`.
    func noteWriteExistingContext() -> Context? {
      withUnsafeMutablePointerToHeader { header in
        _Epoch.write(
          visited: Extent.stampWord(header, at: Extent.visitedStampOffset),
          mutated: Extent.stampWord(header, at: Extent.mutatedStampOffset))
      }
      return existingContext
    }

    // Whether a property index-tagged willSet or didSet with `propertyIndex` must look for
    // observers. Read without the lock, relaxed: a clear bit only ever means
    // there is nothing to notify, and a stale set bit only costs the look.
    // Property indices outside 0..<64 have no bit and always look.
    func mayObserve(propertyIndex: Int) -> Bool {
      guard propertyIndex >= 0 && propertyIndex < 64 else { return true }
      let mask = withUnsafeMutablePointerToHeader {
        _atomic(Extent.observedMaskWord($0)).pointee.load(ordering: .relaxed)
      }
      return mask & (1 << UInt64(propertyIndex)) != 0
    }

    // The context, if one has been published; takes no lock.
    var existingContext: Context? {
      withUnsafeMutablePointerToHeader { header in
        guard _atomic(Extent.hasContextFlag(header)).pointee.load(ordering: .acquiring) else {
          return nil
        }
        return header.pointee.context
      }
    }

    var context: Context {
      if let context = existingContext {
        return context
      }
      return withUnsafeMutablePointers { header, lock in
        Lock.lock(lock)
        defer { Lock.unlock(lock) }
        if let context = header.pointee.context {
          return context
        }
        // The header does not move for the extent's lifetime, and the
        // context stops using the pointer when `deinit` below calls its
        // `deinitialize()`.
        let context = Context(observedMask: Extent.observedMaskWord(header))
        header.pointee.context = context
        // Publishes `context` to the lock-free reads above.
        _atomic(Extent.hasContextFlag(header)).pointee.store(true, ordering: .releasing)
        return context
      }
    }

    deinit {
      // Nothing else can reference the extent while it deinitializes, so the
      // header is read without taking the lock.
      let context = withUnsafeMutablePointerToHeader { $0.pointee.context }
      context?.deinitialize()
      withUnsafeMutablePointerToElements { Lock.deinitialize($0) }
    }
  }
  
  internal var context: Context {
    return extent.context
  }
  
  // ManagedBuffer cannot be Sendable; the extent's header is only touched
  // under its lock, through the atomics, or (`context`) after the acquire
  // load documented above.
  private nonisolated(unsafe) let extent = Extent.allocate()

  /// Creates an instance of the observation registrar.
  ///
  /// You don't need to create an instance of
  /// ``Observation/ObservationRegistrar`` when using the
  /// ``Observation/Observable()`` macro to indicate observability
  /// of a type.
  public init() {
  }

  #if !$Embedded
  /// Registers access to a specific property for observation.
  ///
  /// - Parameters:
  ///   - subject: An instance of an observable type.
  ///   - keyPath: The key path of an observed property.
  public func access<Subject: Observable, Member>(
      _ subject: Subject,
      keyPath: KeyPath<Subject, Member>
  ) {
    if let traversal = _Traversals.current {
      extent.noteRead(in: traversal)
    }
    if let collecting = ObservationTracking.Collecting(_ThreadLocal.value) {
      // Accessed under tracking: this is where the observer table is created.
      collecting.addAccess(keyPath: keyPath, context: self.context)
    }
  }

  /// A property observation called before setting the value of the subject.
  ///
  /// - Parameters:
  ///     - subject: An instance of an observable type.
  ///     - keyPath: The key path of an observed property.
  public func willSet<Subject: Observable, Member>(
      _ subject: Subject,
      keyPath: KeyPath<Subject, Member>
  ) {
    // Fast path: never observed, so there is no table to look the key path up in.
    guard let context = extent.existingContext else { return }
    context.willSet(subject, keyPath: keyPath)
  }

  /// A property observation called after setting the value of the subject.
  ///
  /// - Parameters:
  ///   - subject: An instance of an observable type.
  ///   - keyPath: The key path of an observed property.
  public func didSet<Subject: Observable, Member>(
      _ subject: Subject,
      keyPath: KeyPath<Subject, Member>
  ) {
    // Fast path: never observed, so there is no table to look the key path up in.
    guard let context = extent.noteWriteExistingContext() else { return }
    context.didSet(subject, keyPath: keyPath)
  }
  
  /// Identifies mutations to the transactions registered for observers.
  ///
  /// This method calls ``willset(_:keypath:)`` before the mutation. Then it
  /// calls ``didset(_:keypath:)`` after the mutation.
  /// - Parameters:
  ///   - of: An instance of an observable type.
  ///   - keyPath: The key path of an observed property.
  public func withMutation<Subject: Observable, Member, T>(
    of subject: Subject,
    keyPath: KeyPath<Subject, Member>,
    _ mutation: () throws -> T
  ) rethrows -> T {
    willSet(subject, keyPath: keyPath)
    defer { didSet(subject, keyPath: keyPath) }
    return try mutation()
  }

  // Property index-tagged entry points, for the macro's v2 output: `propertyIndex` is the
  // property's ordinal in its class's declaration order, and is required so
  // these never overload ambiguously with the key-path-only ones above.
  //
  // They are emitted into each client, so they themselves are no symbol an
  // older library could lack, and the macro can call them unconditionally
  // (it cannot see the deployment target). But their bodies are compiled
  // into the client too, and anything they call must exist in whichever
  // library the client runs against: `_willSet` and `_didSet` are symbols
  // only newer libraries have, so willSet and didSet call them only when
  // `#available` says the library is new enough, and otherwise fall back to
  // the key-path-only entry points, which notify the same observers.
  //
  // A key path must be passed with the same property index every time (the macro's
  // literal guarantees it): the lock-free check trusts the property index it learned.

  /// Registers access to a specific property for observation.
  ///
  /// - Parameters:
  ///   - subject: An instance of an observable type.
  ///   - keyPath: The key path of an observed property.
  ///   - propertyIndex: The property's ordinal in its type's declaration order.
  @_alwaysEmitIntoClient
  public func access<Subject: Observable, Member>(
      _ subject: Subject,
      keyPath: KeyPath<Subject, Member>,
      propertyIndex: Int
  ) {
    // Tracked accesses are recorded by key path; the property index is not needed
    // until a mutation.
    access(subject, keyPath: keyPath)
  }

  /// A property observation called before setting the value of the subject.
  ///
  /// - Parameters:
  ///     - subject: An instance of an observable type.
  ///     - keyPath: The key path of an observed property.
  ///     - propertyIndex: The property's ordinal in its type's declaration order.
  @_alwaysEmitIntoClient
  public func willSet<Subject: Observable, Member>(
      _ subject: Subject,
      keyPath: KeyPath<Subject, Member>,
      propertyIndex: Int
  ) {
    // Availability macros are not allowed in @_alwaysEmitIntoClient bodies;
    // this spells out SwiftStdlib 6.5 (placeholder: the '27 release).
    if #available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *) {
      _willSet(keyPath, propertyIndex: propertyIndex)
    } else {
      willSet(subject, keyPath: keyPath)
    }
  }

  /// A property observation called after setting the value of the subject.
  ///
  /// - Parameters:
  ///   - subject: An instance of an observable type.
  ///   - keyPath: The key path of an observed property.
  ///   - propertyIndex: The property's ordinal in its type's declaration order.
  @_alwaysEmitIntoClient
  public func didSet<Subject: Observable, Member>(
      _ subject: Subject,
      keyPath: KeyPath<Subject, Member>,
      propertyIndex: Int
  ) {
    // See willSet(_:keyPath:propertyIndex:) for the spelled-out availability.
    if #available(macOS 27.0, iOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *) {
      _didSet(keyPath, propertyIndex: propertyIndex)
    } else {
      didSet(subject, keyPath: keyPath)
    }
  }

  /// Identifies mutations to the transactions registered for observers.
  ///
  /// This method calls ``willSet(_:keyPath:propertyIndex:)`` before the mutation. Then
  /// it calls ``didSet(_:keyPath:propertyIndex:)`` after the mutation.
  /// - Parameters:
  ///   - of: An instance of an observable type.
  ///   - keyPath: The key path of an observed property.
  ///   - propertyIndex: The property's ordinal in its type's declaration order.
  @_alwaysEmitIntoClient
  public func withMutation<Subject: Observable, Member, T>(
    of subject: Subject,
    keyPath: KeyPath<Subject, Member>,
    propertyIndex: Int,
    _ mutation: () throws -> T
  ) rethrows -> T {
    willSet(subject, keyPath: keyPath, propertyIndex: propertyIndex)
    defer { didSet(subject, keyPath: keyPath, propertyIndex: propertyIndex) }
    return try mutation()
  }

  // New in the library that has the property index-tagged entry points above, so only
  // called by them behind `#available`.
  @available(SwiftStdlib 6.5, *)
  @usableFromInline
  internal func _willSet(_ keyPath: AnyKeyPath, propertyIndex: Int) {
    // Fast path: no willSet or didSet observer of this property index, so no lock.
    guard extent.mayObserve(propertyIndex: propertyIndex),
          let context = extent.existingContext else { return }
    context.willSet(keyPath: keyPath, propertyIndex: propertyIndex)
  }

  @available(SwiftStdlib 6.5, *)
  @usableFromInline
  internal func _didSet(_ keyPath: AnyKeyPath, propertyIndex: Int) {
    // Fast path: no willSet or didSet observer of this property index, so no lock.
    guard extent.noteWrite(mayObservePropertyIndex: propertyIndex),
          let context = extent.existingContext else { return }
    context.didSet(keyPath: keyPath, propertyIndex: propertyIndex)
  }

  // Property index-only entry points, for types that have no key paths to pass: a
  // noncopyable `@Observable` struct, whose properties no key path can name.
  // The same signatures as Embedded's below, so the macro emits one form for
  // both. Each property is identified by its property index alone (see
  // `_PropertyIndexIdentity`), so a type passes a property's property index the same way every
  // time, and does not also observe that property by key path.

  /// Registers access to a specific property for observation.
  ///
  /// Use this form for a type that can't form key paths to its properties,
  /// such as a noncopyable type. A property accessed by property index is notified
  /// only of mutations made by property index.
  ///
  /// - Parameters:
  ///   - propertyIndex: The property's ordinal in its type's declaration order.
  @available(SwiftStdlib 6.5, *)
  public func access(propertyIndex: Int) {
    if let traversal = _Traversals.current {
      extent.noteRead(in: traversal)
    }
    if let collecting = ObservationTracking.Collecting(_ThreadLocal.value) {
      // Accessed under tracking: this is where the observer table is created.
      collecting.addAccess(propertyIndex: propertyIndex, context: self.context)
    }
  }

  /// A property observation called before setting the value of the subject,
  /// for a property identified by its property index.
  ///
  /// - Parameters:
  ///   - propertyIndex: The property's ordinal in its type's declaration order.
  @available(SwiftStdlib 6.5, *)
  public func willSet(propertyIndex: Int) {
    // Fast path: no willSet or didSet observer of this property index, so no lock.
    guard extent.mayObserve(propertyIndex: propertyIndex),
          let context = extent.existingContext else { return }
    context.willSet(propertyIndex: propertyIndex)
  }

  /// A property observation called after setting the value of the subject,
  /// for a property identified by its property index.
  ///
  /// - Parameters:
  ///   - propertyIndex: The property's ordinal in its type's declaration order.
  @available(SwiftStdlib 6.5, *)
  public func didSet(propertyIndex: Int) {
    // Fast path: no willSet or didSet observer of this property index, so no lock.
    guard extent.noteWrite(mayObservePropertyIndex: propertyIndex),
          let context = extent.existingContext else { return }
    context.didSet(propertyIndex: propertyIndex)
  }

  /// Identifies mutations to the transactions registered for observers, for
  /// a property identified by its property index.
  ///
  /// This method calls ``willSet(propertyIndex:)`` before the mutation. Then it calls
  /// ``didSet(propertyIndex:)`` after the mutation.
  /// - Parameters:
  ///   - propertyIndex: The property's ordinal in its type's declaration order.
  @available(SwiftStdlib 6.5, *)
  public func withMutation<T, Failure: Error>(
    propertyIndex: Int,
    _ mutation: () throws(Failure) -> T
  ) throws(Failure) -> T {
    willSet(propertyIndex: propertyIndex)
    defer { didSet(propertyIndex: propertyIndex) }
    return try mutation()
  }
  #else
  // Embedded Swift cannot form key paths at all, so its entry points take
  // only the property's property index: its ordinal in its type's declaration order,
  // which Embedded observers are keyed by directly. There is no subject
  // parameter either; no body ever used it.

  /// Registers access to a specific property for observation.
  ///
  /// - Parameters:
  ///   - propertyIndex: The property's ordinal in its type's declaration order.
  public func access(propertyIndex: Int) {
    if let traversal = _Traversals.current {
      extent.noteRead(in: traversal)
    }
    if let collecting = ObservationTracking.Collecting(_ThreadLocal.value) {
      // Accessed under tracking: this is where the observer table is created.
      collecting.addAccess(propertyIndex: propertyIndex, context: self.context)
    }
  }

  /// A property observation called before setting the value of the subject.
  ///
  /// - Parameters:
  ///   - propertyIndex: The property's ordinal in its type's declaration order.
  public func willSet(propertyIndex: Int) {
    // Fast path: no willSet or didSet observer of this property index (or never
    // observed at all), so no lock.
    guard extent.mayObserve(propertyIndex: propertyIndex),
          let context = extent.existingContext else { return }
    context.willSet(propertyIndex: propertyIndex)
  }

  /// A property observation called after setting the value of the subject.
  ///
  /// - Parameters:
  ///   - propertyIndex: The property's ordinal in its type's declaration order.
  public func didSet(propertyIndex: Int) {
    // Fast path: no willSet or didSet observer of this property index (or never
    // observed at all), so no lock.
    guard extent.noteWrite(mayObservePropertyIndex: propertyIndex),
          let context = extent.existingContext else { return }
    context.didSet(propertyIndex: propertyIndex)
  }

  /// Identifies mutations to the transactions registered for observers.
  ///
  /// This method calls ``willSet(propertyIndex:)`` before the mutation. Then it calls
  /// ``didSet(propertyIndex:)`` after the mutation.
  /// - Parameters:
  ///   - propertyIndex: The property's ordinal in its type's declaration order.
  public func withMutation<T, Failure: Error>(
    propertyIndex: Int,
    _ mutation: () throws(Failure) -> T
  ) throws(Failure) -> T {
    willSet(propertyIndex: propertyIndex)
    defer { didSet(propertyIndex: propertyIndex) }
    return try mutation()
  }
  #endif
}

// Codable is not available in Embedded Swift. The conformance only exists so
// that Codable types can contain a registrar; it deliberately encodes nothing.
#if !$Embedded
@available(SwiftStdlib 5.9, *)
extension ObservationRegistrar: Codable {
  public init(from decoder: any Decoder) throws {
    self.init()
  }

  public func encode(to encoder: any Encoder) {
    // Don't encode a registrar's transient state.
  }
}
#endif

@available(SwiftStdlib 5.9, *)
extension ObservationRegistrar: Hashable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    // A registrar should be ignored for the purposes of determining its
    // parent type's equality.
    return true
  }
  
  public func hash(into hasher: inout Hasher) {
    // Don't include a registrar's transient state in its parent type's
    // hash value.
  }
}
