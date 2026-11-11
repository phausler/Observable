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

@available(SwiftStdlib 5.9, *)
public struct ObservationTracking: Sendable {
  // A collection whose first element is stored inline, so the common case of
  // one element allocates nothing; the rest go in `tail`. Access lists touch
  // few objects, so entries are searched linearly until there are many (see
  // `TrackedEntries.index(of:)`); key paths are not searched at all (see
  // `Entry.insert(_:)`).
  struct SmallArray<Element>: RandomAccessCollection {
    private var head: Element?
    private var tail = ContiguousArray<Element>()

    init() { }

    var startIndex: Int { 0 }
    var endIndex: Int { head == nil ? 0 : tail.count + 1 }
    var count: Int { endIndex }
    var last: Element? { tail.last ?? head }

    // The hot paths use these rather than the generic Collection algorithms,
    // which in unoptimized builds go through IndexingIterator and this
    // type's witnesses for every element.
    func forEach(_ body: (Element) throws -> Void) rethrows {
      guard let head else { return }
      try body(head)
      for element in tail {
        try body(element)
      }
    }

    func firstIndex(where predicate: (Element) throws -> Bool) rethrows -> Int? {
      guard let head else { return nil }
      if try predicate(head) { return 0 }
      for index in tail.indices where try predicate(tail[index]) {
        return index + 1
      }
      return nil
    }

    subscript(position: Int) -> Element {
      get { position == 0 ? head! : tail[position - 1] }
      _modify {
        if position == 0 {
          yield &head!
        } else {
          yield &tail[position - 1]
        }
      }
    }

    mutating func append(_ element: Element) {
      if head == nil {
        head = element
      } else {
        tail.append(element)
      }
    }

    // Keeps `tail`'s storage, for reuse.
    mutating func removeAll() {
      head = nil
      tail.removeAll(keepingCapacity: true)
    }
  }

  struct Entry: @unchecked Sendable {
    let context: ObservationRegistrar.Context
    
    #if !$Embedded
    var properties = SmallArray<AnyKeyPath>()
    #else
    // Embedded Swift has no key paths: the accessed properties' propertyIndexs.
    var properties = SmallArray<Int>()
    #endif
    
    init(_ context: ObservationRegistrar.Context) {
      self.context = context
    }
    
    #if !$Embedded
    // Repeats are harmless: registering interns each key path and sets its
    // bit, so a repeat only sets a bit again. Searching for them on every
    // access made building a list of N properties O(N²), so only a repeat of
    // the last access (key path literals are uniqued per pattern) is dropped
    // here; the rest are bounded by `appendCompacting(_:)`.
    mutating func insert(_ keyPath: AnyKeyPath) {
      if properties.last === keyPath {
        return
      }
      properties.appendCompacting(keyPath)
    }
    #else
    // As above: only a repeat of the last access is dropped here.
    mutating func insert(_ propertyIndex: Int) {
      if properties.last == propertyIndex {
        return
      }
      properties.appendCompacting(propertyIndex)
    }
    #endif

    mutating func formUnion(_ entry: Entry) {
      entry.properties.forEach { insert($0) }
    }
  }

  // The access list collected by this module's own entry points, and the one
  // a tracking registers and cancels with (its registrar tokens are parallel
  // to `entries`). SwiftUI collects into an `_AccessList` instead, which a
  // tracking converts once (see `Collecting`).
  struct TrackedEntries: Sendable {
    // One entry per observed object, deduplicated by the identity of its
    // registrar's context.
    internal var entries = SmallArray<Entry>()
    // Each entry's index by its context's identity, built once there are
    // more than `indexThreshold` entries: searching them linearly made
    // building a list of N objects O(N²).
    private var indexByID: [ObjectIdentifier: Int]?
    private static var indexThreshold: Int { 16 }

    // A derived value whose `input` ran under this collection (see
    // `ObservationDerivedValue.compute(registrar:propertyIndex:input:update:)`).
    // Kept apart from `entries`, which registration iterates.
    struct DerivedVisit: Sendable {
      let context: ObservationRegistrar.Context
      let index: Int
    }
    struct DerivedVisitKey: Hashable {
      let id: ObjectIdentifier
      let index: Int
    }
    private var derivedVisits = SmallArray<DerivedVisit>()
    // Built like `indexByID`, once there are more than `indexThreshold` visits.
    private var derivedVisitIndex: Set<DerivedVisitKey>?

    internal init() { }

    // Empties the list, keeping its storage (and `indexByID`, if built, which
    // `append(_:)` then keeps complete from the first entry on) for reuse.
    internal mutating func removeAll() {
      entries.removeAll()
      indexByID?.removeAll(keepingCapacity: true)
      derivedVisits.removeAll()
      derivedVisitIndex?.removeAll(keepingCapacity: true)
    }

    // Whether the list has neither entries nor derived visits.
    internal var isEmpty: Bool {
      entries.isEmpty && derivedVisits.isEmpty
    }

    // Whether `input` of the derived value (`context`, `index`) already ran
    // under this collection.
    internal func containsDerivedVisit(context: ObservationRegistrar.Context, index: Int) -> Bool {
      let id = context.id
      if let derivedVisitIndex {
        return derivedVisitIndex.contains(DerivedVisitKey(id: id, index: index))
      }
      let last = derivedVisits.count - 1
      if last >= 0 && derivedVisits[last].context.id == id && derivedVisits[last].index == index {
        return true
      }
      return derivedVisits.firstIndex { $0.context.id == id && $0.index == index } != nil
    }

    internal mutating func addDerivedVisit(context: ObservationRegistrar.Context, index: Int) {
      guard !containsDerivedVisit(context: context, index: index) else { return }
      derivedVisits.append(DerivedVisit(context: context, index: index))
      if derivedVisitIndex != nil {
        derivedVisitIndex!.insert(DerivedVisitKey(id: context.id, index: index))
      } else if derivedVisits.count > Self.indexThreshold {
        var built = Set<DerivedVisitKey>(minimumCapacity: 2 * derivedVisits.count)
        derivedVisits.forEach { built.insert(DerivedVisitKey(id: $0.context.id, index: $0.index)) }
        derivedVisitIndex = built
      }
    }

    // Frees the derived visits, for a list kept only for registration.
    internal mutating func releaseDerivedVisits() {
      derivedVisits = SmallArray()
      derivedVisitIndex = nil
    }

    internal func index(of context: ObservationRegistrar.Context) -> Int? {
      let id = context.id
      // The common case: another access to the object accessed last.
      let lastIndex = entries.count - 1
      if lastIndex >= 0 && entries[lastIndex].context.id == id {
        return lastIndex
      }
      if let indexByID {
        return indexByID[id]
      }
      return entries.firstIndex { $0.context.id == id }
    }

    // The only way entries are added, so `indexByID` stays complete.
    private mutating func append(_ entry: Entry) {
      entries.append(entry)
      if indexByID != nil {
        indexByID![entry.context.id] = entries.count - 1
      } else if entries.count > Self.indexThreshold {
        var built = [ObjectIdentifier: Int](minimumCapacity: 2 * entries.count)
        for index in 0..<entries.count {
          built[entries[index].context.id] = index
        }
        indexByID = built
      }
    }

    // An `_AccessList` (SwiftUI's collection) in this representation.
    init(converting list: _AccessList?) {
      guard let list else { return }
      for accessed in list.entries.values {
        var entry = Entry(accessed.context)
        for property in accessed.properties {
          // Derived visits are for collecting only; registration ignores them.
          #if !$Embedded
          if property is KeyPath<_DerivedIdentity, Int> { continue }
          #else
          if property < 0 { continue }
          #endif
          entry.insert(property)
        }
        if !entry.properties.isEmpty {
          append(entry)
        }
      }
    }

    #if !$Embedded
    internal mutating func addAccess<Subject: Observable>(
      keyPath: PartialKeyPath<Subject>,
      context: ObservationRegistrar.Context
    ) {
      if let index = index(of: context) {
        entries[index].insert(keyPath)
      } else {
        var entry = Entry(context)
        entry.insert(keyPath)
        append(entry)
      }
    }

    // A propertyIndex-only access, recorded by the propertyIndex's `_PropertyIndexIdentity` key path.
    @available(SwiftStdlib 6.5, *)
    internal mutating func addAccess(
      propertyIndex: Int,
      context: ObservationRegistrar.Context
    ) {
      let keyPath = _PropertyIndexIdentity.keyPath(propertyIndex)
      if let index = index(of: context) {
        entries[index].insert(keyPath)
      } else {
        var entry = Entry(context)
        entry.insert(keyPath)
        append(entry)
      }
    }
    #else
    internal mutating func addAccess(
      propertyIndex: Int,
      context: ObservationRegistrar.Context
    ) {
      if let index = index(of: context) {
        entries[index].insert(propertyIndex)
      } else {
        var entry = Entry(context)
        entry.insert(propertyIndex)
        append(entry)
      }
    }
    #endif

    // Merges like a dictionary keyed by object: an object already present
    // takes the union of both entries' properties; a new one is added.
    internal mutating func merge(_ other: TrackedEntries) {
      other.entries.forEach { entry in
        if let index = index(of: entry.context) {
          entries[index].formUnion(entry)
        } else {
          append(entry)
        }
      }
      other.derivedVisits.forEach { addDerivedVisit(context: $0.context, index: $0.index) }
    }

    // The same, into SwiftUI's representation.
    internal func merge(into list: inout _AccessList) {
      entries.forEach { entry in
        list.entries[entry.context.id, default: AccessEntry(entry.context)]
          .properties.formUnion(entry.properties)
      }
      derivedVisits.forEach { list.addDerivedVisit(context: $0.context, index: $0.index) }
    }
  }

  // An access list entry: one observed object and the properties of it that
  // were read.
  //
  // SwiftUI reads and writes `_AccessList` as `[ObjectIdentifier: (AnyObject,
  // Set<AnyKeyPath>)]`, so this layout, and `_AccessList`'s, must not change.
  struct AccessEntry: @unchecked Sendable {
    let context: ObservationRegistrar.Context
    #if !$Embedded
    var properties = Set<AnyKeyPath>()
    #else
    // Embedded Swift has no key paths: the accessed properties' indices.
    var properties = Set<Int>()
    #endif

    init(_ context: ObservationRegistrar.Context) {
      self.context = context
    }
  }

  // The properties read during a tracked closure. SwiftUI collects one by
  // installing a pointer to an `_AccessList?` in the observation thread-local
  // itself, and merges two by their layout (see `AccessEntry`): this must
  // stay a single `[ObjectIdentifier: AccessEntry]`.
  @_spi(SwiftUI)
  public struct _AccessList: Sendable {
    internal var entries = [ObjectIdentifier: AccessEntry]()

    internal init() { }

    // Empties the list, keeping its storage for reuse.
    internal mutating func removeAll() {
      entries.removeAll(keepingCapacity: true)
    }

    #if !$Embedded
    internal mutating func addAccess<Subject: Observable>(
      keyPath: PartialKeyPath<Subject>,
      context: ObservationRegistrar.Context
    ) {
      entries[context.id, default: AccessEntry(context)].properties.insert(keyPath)
    }

    // A propertyIndex-only access, recorded by the propertyIndex's `_PropertyIndexIdentity` key path.
    @available(SwiftStdlib 6.5, *)
    internal mutating func addAccess(
      propertyIndex: Int,
      context: ObservationRegistrar.Context
    ) {
      let keyPath = _PropertyIndexIdentity.keyPath(propertyIndex)
      entries[context.id, default: AccessEntry(context)].properties.insert(keyPath)
    }
    #else
    internal mutating func addAccess(
      propertyIndex: Int,
      context: ObservationRegistrar.Context
    ) {
      entries[context.id, default: AccessEntry(context)].properties.insert(propertyIndex)
    }
    #endif

    // Derived visits live in the owner's own entry, because SwiftUI fixes this
    // type's layout; registration drops them (`TrackedEntries(converting:)`).
    internal func containsDerivedVisit(context: ObservationRegistrar.Context, index: Int) -> Bool {
      #if !$Embedded
      let key = _DerivedIdentity.keyPath(index)
      #else
      let key = _DerivedKey.key(index)
      #endif
      return entries[context.id]?.properties.contains(key) ?? false
    }

    internal mutating func addDerivedVisit(context: ObservationRegistrar.Context, index: Int) {
      #if !$Embedded
      let key = _DerivedIdentity.keyPath(index)
      #else
      let key = _DerivedKey.key(index)
      #endif
      entries[context.id, default: AccessEntry(context)].properties.insert(key)
    }

    // An object already present takes the union of both entries'
    // properties; a new one is added.
    internal mutating func merge(_ other: _AccessList) {
      entries.merge(other.entries) { existing, entry in
        var merged = existing
        merged.properties.formUnion(entry.properties)
        return merged
      }
    }
  }

  /// The observable properties read while running a closure, collected with
  /// ``_collectAccessList(_:)``.
  ///
  /// This is what to use in place of ``_AccessList``, whose layout must stay
  /// fixed for the clients that read it directly. This type's
  /// representation is opaque: combine lists with ``merge(_:)`` and observe
  /// one with ``ObservationTracking/init(_:)-(_TrackedAccessList)``.
  @available(SwiftStdlib 6.5, *)
  @_spi(SwiftUI)
  public struct _TrackedAccessList: Sendable {
    internal var entries: TrackedEntries

    internal init(_ entries: TrackedEntries) {
      self.entries = entries
    }

    /// Adds the properties `other` read: an object both read is observed for
    /// the properties either read.
    public mutating func merge(_ other: _TrackedAccessList) {
      entries.merge(other.entries)
    }
  }

  /// Runs `body` and returns what it returns, with the observable properties
  /// it read, or `nil` if it read none.
  ///
  /// Unlike ``withObservationTracking(_:onChange:)``, the reads are not also
  /// reported to a collection that encloses this one.
  @available(SwiftStdlib 6.5, *)
  @_spi(SwiftUI)
  public static func _collectAccessList<Result, Failure: Error>(
    _ body: () throws(Failure) -> Result
  ) throws(Failure) -> (result: Result, accessList: _TrackedAccessList?) {
    var collected: TrackedEntries? = nil
    let result = try withUnsafeMutablePointer(to: &collected) { (ptr: UnsafeMutablePointer<TrackedEntries?>) throws(Failure) -> Result in
      let previous = _ThreadLocal.value
      _ThreadLocal.value = Collecting.value(ptr)
      defer { _ThreadLocal.value = previous }
      return try body()
    }
    return (result, collected.map(_TrackedAccessList.init))
  }

  /// Creates a tracking of the properties in `list`, to install with
  /// ``_installTracking(_:willSet:didSet:)``; a `nil` list tracks nothing.
  @available(SwiftStdlib 6.5, *)
  @_spi(SwiftUI)
  public init(_ list: _TrackedAccessList?) {
    self.init(entries: list?.entries)
  }

  // What a registrar observer record notifies: the tracking and the handlers
  // it was installed with, stored in the record itself rather than captured
  // in wrapper closures. Records are removed on cancel, so, as before, a
  // handler that captures its tracking does not keep it alive forever.
  struct Handlers: Sendable {
    let tracking: ObservationTracking
    var willSet: (@Sendable (ObservationTracking) -> Void)?
    var didSet: (@Sendable (ObservationTracking) -> Void)?
    var `deinit`: (@Sendable () -> Void)?
    // The legacy `withObservationTracking(_:onChange:)` handler: called on
    // the first willSet, which then cancels the tracking.
    var onChange: (@Sendable () -> Void)?

    var observesWillSet: Bool { self.willSet != nil || onChange != nil }
    var observesDidSet: Bool { self.didSet != nil }
    var observesDeinit: Bool { self.deinit != nil }

    #if !$Embedded
    // `keyPath` is nil for a propertyIndex-only mutation, which names no property.
    func notifyWillSet(_ keyPath: AnyKeyPath?) {
      tracking.state.withCriticalRegion { $0.changed = keyPath }
      if let onChange {
        onChange()
        tracking.cancel()
      } else {
        willSet?(tracking)
      }
    }

    func notifyDidSet(_ keyPath: AnyKeyPath?) {
      tracking.state.withCriticalRegion { $0.changed = keyPath }
      didSet?(tracking)
    }
    #else
    // Embedded mutations name no key path, so there is no `changed` to record.
    func notifyWillSet() {
      if let onChange {
        onChange()
        tracking.cancel()
      } else {
        willSet?(tracking)
      }
    }

    func notifyDidSet() {
      didSet?(tracking)
    }
    #endif

    func notifyDeinit() {
      `deinit`?()
    }
  }

  private func install(_ handlers: Handlers) {
    let list = state.withCriticalRegion { $0.list }
    var tokens = SmallArray<Int>()
    list.entries.forEach { entry in
      tokens.append(entry.context.registerTracking(for: entry.properties, handlers: handlers))
    }
    let cancelled = state.withCriticalRegion {
      if !$0.cancelled {
        $0.tokens = tokens
      }
      return $0.cancelled
    }
    // Cancelled while installing (a handler fired and cancelled it): its
    // cancel found no tokens, so cancel the registrations here.
    if cancelled {
      for index in 0..<tokens.count {
        list.entries[index].context.cancel(tokens[index])
      }
    }
  }

  #if !$Embedded
  // Re-arms a tracking: installs this tracking in place of `previous`, which
  // it consumes. `previous` is marked cancelled and its registrations are
  // taken over, so cancelling it afterwards does nothing.
  // Per registrar context (by identity, as `TrackedEntries.index(of:)`), a
  // registration of `previous` whose properties are unchanged is kept and
  // notifies `handlers` from now on; the rest are cancelled or registered.
  // A registration notifying `previous` concurrently is not lost: that
  // notification is delivered to `previous`, as it would have been had the
  // registration been cancelled a moment later.
  private func install(_ handlers: Handlers, rearming previous: ObservationTracking) {
    let list = state.withCriticalRegion { $0.list }
    let (previousList, previousTokens) = previous.state.withCriticalRegion {
      $0.cancelled = true
      let tokens = $0.tokens
      $0.tokens = SmallArray()
      return ($0.list, tokens)
    }
    // `previousTokens` is parallel to `previousList.entries`, or empty if
    // `previous` was never installed or was already cancelled.
    var kept = SmallArray<Bool>()
    for _ in 0..<previousTokens.count { kept.append(false) }
    var tokens = SmallArray<Int>()
    list.entries.forEach { entry in
      if previousTokens.count > 0,
         let index = previousList.index(of: entry.context) {
        kept[index] = true
        tokens.append(entry.context.updateTracking(
          previousTokens[index], for: entry.properties, handlers: handlers))
      } else {
        tokens.append(entry.context.registerTracking(for: entry.properties, handlers: handlers))
      }
    }
    for index in 0..<previousTokens.count where !kept[index] {
      previousList.entries[index].context.cancel(previousTokens[index])
    }
    let cancelled = state.withCriticalRegion {
      if !$0.cancelled {
        $0.tokens = tokens
      }
      return $0.cancelled
    }
    // Cancelled while installing (a handler fired and cancelled it): its
    // cancel found no tokens, so cancel the registrations here.
    if cancelled {
      for index in 0..<tokens.count {
        list.entries[index].context.cancel(tokens[index])
      }
    }
  }

  // The entry point for re-arming, shaped like `_installTracking(_:onChange:)`:
  // installs a tracking of `list` that calls `onChange` on the first change,
  // re-arming `previous` if given (see `install(_:rearming:)`).
  @available(SwiftStdlib 6.5, *)
  @_spi(Prototype)
  public static func _updateTracking(
    _ previous: ObservationTracking?,
    _ list: _AccessList?,
    onChange: @escaping @Sendable () -> Void
  ) -> ObservationTracking {
    _updateTracking(previous, entries: TrackedEntries(converting: list), onChange: onChange)
  }

  @available(SwiftStdlib 6.5, *)
  static func _updateTracking(
    _ previous: ObservationTracking?,
    entries: TrackedEntries?,
    onChange: @escaping @Sendable () -> Void
  ) -> ObservationTracking {
    let tracking = ObservationTracking(entries: entries)
    let handlers = Handlers(tracking: tracking, onChange: onChange)
    if let previous {
      tracking.install(handlers, rearming: previous)
    } else {
      tracking.install(handlers)
    }
    return tracking
  }

  // The registrar tokens of the tracking's registrations, one per observed
  // object, in access order; empty before install and after cancel.
  @available(SwiftStdlib 6.5, *)
  @_spi(Prototype)
  public var _registrationTokens: [Int] {
    state.withCriticalRegion { Array($0.tokens) }
  }
  #endif

  @available(SwiftStdlib 6.4, *)
  static func _installTracking(
    options: ObservationTracking.Options,
    _ tracking: ObservationTracking,
    willSet: (@Sendable (ObservationTracking) -> Void)? = nil,
    didSet: (@Sendable (ObservationTracking) -> Void)? = nil,
    `deinit`: (@Sendable () -> Void)? = nil
  ) {
    tracking.install(Handlers(tracking: tracking, willSet: willSet, didSet: didSet, deinit: `deinit`))
  }

  @_spi(SwiftUI)
  public static func _installTracking(
    _ tracking: ObservationTracking,
    willSet: (@Sendable (ObservationTracking) -> Void)? = nil,
    didSet: (@Sendable (ObservationTracking) -> Void)? = nil
  ) {
    tracking.install(Handlers(tracking: tracking, willSet: willSet, didSet: didSet))
  }

  @_spi(SwiftUI)
  public static func _installTracking(
    _ list: _AccessList,
    onChange: @escaping @Sendable () -> Void
  ) {
    let tracking = ObservationTracking(list)
    tracking.install(Handlers(tracking: tracking, onChange: onChange))
  }

  static func _installTracking(
    entries: TrackedEntries,
    onChange: @escaping @Sendable () -> Void
  ) {
    let tracking = ObservationTracking(entries: entries)
    tracking.install(Handlers(tracking: tracking, onChange: onChange))
  }

  // The tracking's one allocation: its access list, and the state and the
  // per-entry registrar tokens behind the buffer's lock.
  struct State: @unchecked Sendable {
    // Replaced by each `Listener.track(_:)`; otherwise fixed.
    var list: TrackedEntries
    // Parallel to `list.entries` once installed; empty before and after.
    var tokens = SmallArray<Int>()
    var cancelled = false
    #if !$Embedded
    var changed: AnyKeyPath?
    #endif
    // Set only for a `Listener`'s tracking: its handler, and, if coalesced,
    // whether it is armed.
    var listener: ListenerHandler?
    var armed = false
  }
  
  private let state: _ManagedCriticalState<State>
  
  #if !$Embedded
  @_spi(SwiftUI)
  public init(_ list: _AccessList?) {
    self.init(list, changed: nil)
  }

  init(_ list: _AccessList?, changed: AnyKeyPath?) {
    state = _ManagedCriticalState(State(list: TrackedEntries(converting: list), changed: changed))
  }
  #else
  // Embedded cannot report which property changed, only that one did.
  @_spi(SwiftUI)
  public init(_ list: _AccessList?) {
    state = _ManagedCriticalState(State(list: TrackedEntries(converting: list)))
  }
  #endif

  // A tracking of entries this module collected, which need no conversion.
  init(entries: TrackedEntries?) {
    var list = entries ?? TrackedEntries()
    // Registration ignores derived visits.
    list.releaseDerivedVisits()
    state = _ManagedCriticalState(State(list: list))
  }

  var isCancelled: Bool {
    state.withCriticalRegion { $0.cancelled }
  }

  @_spi(SwiftUI)
  public func cancel() {
    let (list, tokens) = state.withCriticalRegion {
      $0.cancelled = true
      let tokens = $0.tokens
      $0.tokens = SmallArray()
      return ($0.list, tokens)
    }
    for index in 0..<tokens.count {
      list.entries[index].context.cancel(tokens[index])
    }
  }

  #if !$Embedded
  @available(SwiftStdlib 6.0, *)
  @_spi(SwiftUI)
  public var changed: AnyKeyPath? {
      state.withCriticalRegion { $0.changed }
  }
  #endif

  @available(SwiftStdlib 6.4, *)
  public struct Options {
    struct RawValue: OptionSet {
      var rawValue: Int

      init(rawValue: Int) {
        self.rawValue = rawValue
      }

      static var willSet: RawValue { .init(rawValue: 1 << 0) }
      static var didSet: RawValue { .init(rawValue: 1 << 1) }
      static var `deinit`: RawValue { .init(rawValue: 1 << 2) }
      static var continuous: RawValue { .init(rawValue: 1 << 3) }
      static var updating: RawValue { .init(rawValue: 1 << 4) }
      static var coalesced: RawValue { .init(rawValue: 1 << 5) }
    }
    var rawValue: RawValue

    init(rawValue: RawValue) {
      self.rawValue = rawValue
    }

    @available(SwiftStdlib 6.4, *)
    public init() { 
      rawValue = RawValue()
    }

    @available(SwiftStdlib 6.4, *)
    public static var willSet: Options { Options(rawValue: .willSet) }

    @available(SwiftStdlib 6.4, *)
    public static var didSet: Options { Options(rawValue: .didSet) }
    
    @available(SwiftStdlib 6.4, *)
    public static var `deinit`: Options { Options(rawValue: .deinit) }

    /// Delivers at most once per arming: a ``ObservationTracking/Listener``
    /// with this option is told of the first change to anything it tracked,
    /// and not again until it tracks again outside its own handler. Only
    /// `Listener` honors it.
    @available(SwiftStdlib 6.5, *)
    public static var coalesced: Options { Options(rawValue: .coalesced) }
  }

  @available(SwiftStdlib 6.4, *)
  public struct Event: ~Copyable {
    @available(SwiftStdlib 6.4, *)
    public struct Kind: Equatable, Sendable {
      enum RawValue {
        case initial
        case willSet
        case didSet
        case `deinit`
      }

      var rawValue: RawValue
      
      @available(SwiftStdlib 6.4, *)
      public static var initial: Kind { Kind(rawValue: .initial) }
      
      @available(SwiftStdlib 6.4, *)
      public static var willSet: Kind { Kind(rawValue: .willSet) }
      
      @available(SwiftStdlib 6.4, *)
      public static var didSet: Kind { Kind(rawValue: .didSet) }
      
      @available(SwiftStdlib 6.4, *)
      public static var `deinit`: Kind { Kind(rawValue: .deinit) }
    }

    @available(SwiftStdlib 6.4, *)
    public private(set) var kind: Kind

    var tracking: ObservationTracking?
    var continuousState: _ManagedCriticalState<ContinuousObservation.State>?

    init(_ tracking: ObservationTracking?, kind: Kind) {
      self.kind = kind
      self.tracking = tracking
    }

    init(_ tracking: ObservationTracking?, continuousState: _ManagedCriticalState<ContinuousObservation.State>, kind: Kind) {
      self.kind = kind
      self.tracking = tracking
      self.continuousState = continuousState
    }

    #if !$Embedded
    @available(SwiftStdlib 6.4, *)
    public func matches(_ keyPath: PartialKeyPath<some Observable>) -> Bool {
      return tracking?.changed == keyPath
    }
    #endif

    @available(SwiftStdlib 6.4, *)
    public func cancel() {
      tracking?.cancel()
      if let continuousState {
        ContinuousObservation.State.cancel(continuousState)
      }
    }
  }
}

@available(SwiftStdlib 6.4, *)
extension ObservationTracking.Options: SetAlgebra {
  @available(SwiftStdlib 6.4, *)
  public init(arrayLiteral elements: ObservationTracking.Options...) {
    var rawValue = RawValue()
    for element in elements {
      rawValue.rawValue |= element.rawValue.rawValue
    }
    self.init(rawValue: rawValue)
  }

  @available(SwiftStdlib 6.4, *)
  public func union(_ other: Self) -> Self {
    Self(rawValue: rawValue.union(other.rawValue))
  }

  @available(SwiftStdlib 6.4, *)
  public func intersection(_ other: Self) -> Self {
    Self(rawValue: rawValue.intersection(other.rawValue))
  }

  @available(SwiftStdlib 6.4, *)
  public func symmetricDifference(_ other: Self) -> Self {
    Self(rawValue: rawValue.symmetricDifference(other.rawValue))
  }

  @available(SwiftStdlib 6.4, *)
  public mutating func formUnion(_ other: Self) {
    rawValue.formUnion(other.rawValue)
  }

  @available(SwiftStdlib 6.4, *)
  public mutating func formIntersection(_ other: Self) {
    rawValue.formIntersection(other.rawValue)
  }

  @available(SwiftStdlib 6.4, *)
  public mutating func formSymmetricDifference(_ other: Self) {
    rawValue.formSymmetricDifference(other.rawValue)
  }
  
  @available(SwiftStdlib 6.4, *)
  public func contains(_ member: Self) -> Bool {
    rawValue.contains(member.rawValue)
  }

  @available(SwiftStdlib 6.4, *)
  @discardableResult
  public mutating func insert(_ newMember: Self) -> (inserted: Bool, memberAfterInsert: Self) {
    let (inserted, memberAfterInsert) = rawValue.insert(newMember.rawValue)
    return (inserted, Self(rawValue: memberAfterInsert))
  }
  
  @available(SwiftStdlib 6.4, *)
  @discardableResult
  public mutating func remove(_ member: Self) -> Self? {
    rawValue.remove(member.rawValue).map { Self(rawValue: $0) }
  }

  @available(SwiftStdlib 6.4, *)
  @discardableResult
  public mutating func update(with newMember: Self) -> Self? {
    rawValue.update(with: newMember.rawValue).map { Self(rawValue: $0) }
  }
}

@available(SwiftStdlib 6.4, *)
extension ObservationTracking.Options: Sendable { }

// The elements' own sendability; `Entry` is `@unchecked Sendable`, as before.
extension ObservationTracking.SmallArray: Sendable where Element: Sendable { }

extension ObservationTracking.SmallArray where Element: Hashable {
  // Appending never searches for an equal element, so it is O(1). Repeats
  // are instead dropped all at once, when `tail` is at least 16 long and
  // full, just before it would grow, and room is left for as many elements
  // again as survive. So compacting is O(1) amortized per append, and the
  // array stays within about twice its number of distinct elements.
  mutating func appendCompacting(_ element: Element) {
    if tail.count >= 16 && tail.count == tail.capacity, let head {
      var seen: Set<Element> = [head]
      var unique = ContiguousArray<Element>()
      for tailElement in tail where seen.insert(tailElement).inserted {
        unique.append(tailElement)
      }
      unique.reserveCapacity(Swift.max(16, 2 * unique.count))
      tail = unique
    }
    append(element)
  }
}

@available(SwiftStdlib 5.9, *)
extension ObservationTracking {
  // The access list being collected on this thread, as `_ThreadLocal.value`
  // holds it. Two kinds of collector install one, each a pointer to an
  // optional list on the collector's stack: this module's (`TrackedEntries`),
  // tagged in the low bit, which such a pointer never has set; and SwiftUI's
  // (`_AccessList`), untagged, which SwiftUI installs in the thread-local
  // itself and so can never change.
  enum Collecting {
    case tracked(UnsafeMutablePointer<TrackedEntries?>)
    case swiftUI(UnsafeMutablePointer<_AccessList?>)

    private static var tag: UInt { 1 }

    @inline(__always)
    init?(_ value: UnsafeMutableRawPointer?) {
      guard let value else { return nil }
      let bits = UInt(bitPattern: value)
      if bits & Self.tag != 0 {
        self = .tracked(UnsafeMutablePointer(bitPattern: bits & ~Self.tag)!)
      } else {
        self = .swiftUI(value.assumingMemoryBound(to: _AccessList?.self))
      }
    }

    // The thread-local value that installs `list`.
    static func value(
      _ list: UnsafeMutablePointer<TrackedEntries?>
    ) -> UnsafeMutableRawPointer {
      UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: list) | tag)!
    }

    #if !$Embedded
    @inline(__always)
    func addAccess<Subject: Observable>(
      keyPath: PartialKeyPath<Subject>,
      context: ObservationRegistrar.Context
    ) {
      switch self {
      case .tracked(let list):
        if list.pointee == nil { list.pointee = TrackedEntries() }
        list.pointee!.addAccess(keyPath: keyPath, context: context)
      case .swiftUI(let list):
        if list.pointee == nil { list.pointee = _AccessList() }
        list.pointee!.addAccess(keyPath: keyPath, context: context)
      }
    }

    @available(SwiftStdlib 6.5, *)
    @inline(__always)
    func addAccess(propertyIndex: Int, context: ObservationRegistrar.Context) {
      switch self {
      case .tracked(let list):
        if list.pointee == nil { list.pointee = TrackedEntries() }
        list.pointee!.addAccess(propertyIndex: propertyIndex, context: context)
      case .swiftUI(let list):
        if list.pointee == nil { list.pointee = _AccessList() }
        list.pointee!.addAccess(propertyIndex: propertyIndex, context: context)
      }
    }
    #else
    @inline(__always)
    func addAccess(propertyIndex: Int, context: ObservationRegistrar.Context) {
      switch self {
      case .tracked(let list):
        if list.pointee == nil { list.pointee = TrackedEntries() }
        list.pointee!.addAccess(propertyIndex: propertyIndex, context: context)
      case .swiftUI(let list):
        if list.pointee == nil { list.pointee = _AccessList() }
        list.pointee!.addAccess(propertyIndex: propertyIndex, context: context)
      }
    }
    #endif

    @inline(__always)
    func containsDerivedVisit(context: ObservationRegistrar.Context, index: Int) -> Bool {
      switch self {
      case .tracked(let list):
        return list.pointee?.containsDerivedVisit(context: context, index: index) ?? false
      case .swiftUI(let list):
        return list.pointee?.containsDerivedVisit(context: context, index: index) ?? false
      }
    }

    func addDerivedVisit(context: ObservationRegistrar.Context, index: Int) {
      switch self {
      case .tracked(let list):
        if list.pointee == nil { list.pointee = TrackedEntries() }
        list.pointee!.addDerivedVisit(context: context, index: index)
      case .swiftUI(let list):
        if list.pointee == nil { list.pointee = _AccessList() }
        list.pointee!.addDerivedVisit(context: context, index: index)
      }
    }

    // Adds the accesses of a nested collection, which an enclosing one sees
    // as its own.
    func merge(_ nested: TrackedEntries) {
      switch self {
      case .tracked(let list):
        if list.pointee == nil {
          list.pointee = nested
        } else {
          list.pointee!.merge(nested)
        }
      case .swiftUI(let list):
        if list.pointee == nil { list.pointee = _AccessList() }
        nested.merge(into: &list.pointee!)
      }
    }
  }
}

@available(SwiftStdlib 5.9, *)
struct AccessListResult<T: ~Copyable>: ~Copyable {
  var result: T
  var accessList: ObservationTracking.TrackedEntries?
}

// Collects the accesses `apply` makes, which an enclosing collection (of
// either kind; see `ObservationTracking.Collecting`) also sees.
@available(SwiftStdlib 5.9, *)
fileprivate func generateAccessList<T: ~Copyable, Failure: Error>(
  reusing seed: consuming ObservationTracking.TrackedEntries? = nil,
  _ apply: () throws(Failure) -> T
) throws(Failure) -> AccessListResult<T> {
  // A seed with derived visits would make those values skip `input`, and
  // their dependencies would never be collected.
  assert(seed?.isEmpty ?? true, "a collection must start empty")
  // An empty `seed` is filled in place, reusing its storage; it is moved,
  // not copied, so the storage stays uniquely referenced.
  var accessList = consume seed
  let result = try withUnsafeMutablePointer(to: &accessList) { (ptr: UnsafeMutablePointer<ObservationTracking.TrackedEntries?>) throws(Failure) -> T in
    let previous = _ThreadLocal.value
    _ThreadLocal.value = ObservationTracking.Collecting.value(ptr)
    defer {
      if let scoped = ptr.pointee, let enclosing = ObservationTracking.Collecting(previous) {
        enclosing.merge(scoped)
      }
      _ThreadLocal.value = previous
    }
    let result = try apply()
    return result
  }
  return AccessListResult(result: result, accessList: accessList)
}

@available(SwiftStdlib 6.4, *)
public func withObservationTracking<Result: ~Copyable, Failure: Error>(
  options: ObservationTracking.Options,
  _ apply: () throws(Failure) -> Result,
  onChange: @escaping @Sendable (borrowing ObservationTracking.Event) -> Void
) throws(Failure) -> Result {
  let accessListResult = try generateAccessList(apply)
  let willSet: (@Sendable (ObservationTracking) -> Void)?
  if options.contains(.willSet) {
    willSet = { tracking in
      onChange(ObservationTracking.Event(tracking, kind: .willSet))
      if !options.rawValue.contains(.continuous) && !options.contains(.didSet) {
        tracking.cancel()
      }
    }
  } else {
    willSet = nil
  }
  let didSet: (@Sendable (ObservationTracking) -> Void)?
  if options.contains(.didSet) {
    didSet = { tracking in
      onChange(ObservationTracking.Event(tracking, kind: .didSet))
      if !options.rawValue.contains(.continuous) {
        tracking.cancel()
      }
    }
  } else {
    didSet = nil
  }
  let `deinit`: (@Sendable () -> Void)?
  if options.contains(.deinit) {
    `deinit` = { 
      onChange(ObservationTracking.Event(nil, kind: .deinit))
    }
  } else {
    `deinit` = nil
  }
  let tracking = ObservationTracking(entries: accessListResult.accessList)
  ObservationTracking._installTracking(options: options, tracking, willSet: willSet, didSet: didSet, deinit: `deinit`)
  return accessListResult.result
}


/// Tracks access to properties.
///
/// This method tracks access to any property within the `apply` closure, and
/// informs the caller of value changes made to participating properties by way
/// of the `onChange` closure. For example, the following code tracks changes
/// to the name of cars, but it doesn't track changes to any other property of
/// `Car`:
/// 
///     func render() {
///         withObservationTracking {
///             for car in cars {
///                 print(car.name)
///             }
///         } onChange: {
///             print("Schedule renderer.")
///         }
///     }
///
/// - Parameters:
///     - apply: A closure that contains properties to track.
///     - onChange: The closure invoked when the value of a property changes.
///
/// - Returns: The value that the `apply` closure returns if it has a return
/// value; otherwise, there is no return value.
@available(SwiftStdlib 5.9, *)
public func withObservationTracking<T>(
  _ apply: () -> T,
  onChange: @autoclosure () -> @Sendable () -> Void
) -> T {
  let accessListResult = generateAccessList(apply)
  if let accessList = accessListResult.accessList {
    ObservationTracking._installTracking(entries: accessList, onChange: onChange())
  }
  return accessListResult.result
}

@available(SwiftStdlib 5.9, *)
@_spi(SwiftUI)
public func withObservationTracking<T>(
  _ apply: () -> T,
  willSet: @escaping @Sendable (ObservationTracking) -> Void,
  didSet: @escaping @Sendable (ObservationTracking) -> Void
) -> T {
  let accessListResult = generateAccessList(apply)
  ObservationTracking._installTracking(ObservationTracking(entries: accessListResult.accessList), willSet: willSet, didSet: didSet)
  return accessListResult.result
}

@available(SwiftStdlib 5.9, *)
@_spi(SwiftUI)
public func withObservationTracking<T>(
  _ apply: () -> T,
  willSet: @escaping @Sendable (ObservationTracking) -> Void
) -> T {
  let accessListResult = generateAccessList(apply)
  ObservationTracking._installTracking(ObservationTracking(entries: accessListResult.accessList), willSet: willSet, didSet: nil)
  return accessListResult.result
}

@available(SwiftStdlib 5.9, *)
@_spi(SwiftUI)
public func withObservationTracking<T>(
  _ apply: () -> T,
  didSet: @escaping @Sendable (ObservationTracking) -> Void
) -> T {
  let accessListResult = generateAccessList(apply)
  ObservationTracking._installTracking(ObservationTracking(entries: accessListResult.accessList), willSet: nil, didSet: didSet)
  return accessListResult.result
}

#if !$Embedded
// `withObservationTracking(_:onChange:)` for a body that is re-evaluated,
// re-arming the tracking `previous` returned last time instead
// of cancelling it and registering anew (see
// `ObservationTracking._updateTracking(_:_:onChange:)`). Returns the new
// tracking to pass next time; `previous` must not be used again.
@available(SwiftStdlib 6.5, *)
@_spi(Prototype)
public func _withObservationTracking<T>(
  rearming previous: ObservationTracking?,
  _ apply: () -> T,
  onChange: @escaping @Sendable () -> Void
) -> (result: T, tracking: ObservationTracking) {
  let accessListResult = generateAccessList(apply)
  let tracking = ObservationTracking._updateTracking(
    previous, entries: accessListResult.accessList, onChange: onChange)
  return (accessListResult.result, tracking)
}
#endif

#if !$Embedded
// Batch install and cancel for one update pass. Trackings of one pass often
// observe the same objects; installing or cancelling them one at a time
// takes each shared registrar's lock once per tracking, where these take it
// once per registrar for the whole batch.
extension ObservationTracking {
  fileprivate struct Pending {
    let tracking: ObservationTracking
    let list: TrackedEntries
    let handlers: Handlers
  }

  // Installs each tracking as `install(_:)` does, but registering all of the
  // batch's records on a registrar under one acquisition of its lock.
  fileprivate static func installAll(_ pending: ContiguousArray<Pending>) {
    // Parallel to `pending`, then to each list's entries, as `State.tokens`.
    var tokens = ContiguousArray<SmallArray<Int>>()
    tokens.reserveCapacity(pending.count)
    for item in pending {
      var entryTokens = SmallArray<Int>()
      item.list.entries.forEach { _ in entryTokens.append(0) }
      tokens.append(entryTokens)
    }
    // Each registrar is visited from the first tracking that observes it;
    // no earlier tracking does, so the later ones are all it must look at.
    var visited = SmallArray<ObjectIdentifier>()
    for first in pending.indices {
      pending[first].list.entries.forEach { entry in
        let id = entry.context.id
        if visited.firstIndex(where: { $0 == id }) != nil { return }
        visited.append(id)
        entry.context.registerTrackings { register in
          for index in first..<pending.count {
            let item = pending[index]
            if let entryIndex = item.list.entries.firstIndex(where: { $0.context.id == id }) {
              tokens[index][entryIndex] = register(item.list.entries[entryIndex].properties, item.handlers)
            }
          }
        }
      }
    }
    for index in pending.indices {
      let item = pending[index]
      let cancelled = item.tracking.state.withCriticalRegion {
        if !$0.cancelled {
          $0.tokens = tokens[index]
        }
        return $0.cancelled
      }
      // Cancelled while installing (a handler fired and cancelled it): its
      // cancel found no tokens, so cancel the registrations here.
      if cancelled {
        for entryIndex in 0..<tokens[index].count {
          item.list.entries[entryIndex].context.cancel(tokens[index][entryIndex])
        }
      }
    }
  }

  // Cancels each tracking as `cancel()` does, but cancelling all of the
  // batch's records on a registrar under one acquisition of its lock.
  fileprivate static func cancelAll(_ trackings: [ObservationTracking]) {
    var taken = ContiguousArray<(list: TrackedEntries, tokens: SmallArray<Int>)>()
    taken.reserveCapacity(trackings.count)
    for tracking in trackings {
      taken.append(tracking.state.withCriticalRegion {
        $0.cancelled = true
        let tokens = $0.tokens
        $0.tokens = SmallArray()
        return ($0.list, tokens)
      })
    }
    // `tokens` is parallel to `list.entries`, or empty if the tracking was
    // never installed or was already cancelled.
    var visited = SmallArray<ObjectIdentifier>()
    for first in taken.indices {
      let (list, tokens) = taken[first]
      for entryIndex in 0..<tokens.count {
        let context = list.entries[entryIndex].context
        let id = context.id
        if visited.firstIndex(where: { $0 == id }) != nil { continue }
        visited.append(id)
        context.cancelTrackings { cancel in
          for index in first..<taken.count {
            let (otherList, otherTokens) = taken[index]
            if otherTokens.count > 0,
               let otherIndex = otherList.entries.firstIndex(where: { $0.context.id == id }) {
              cancel(otherTokens[otherIndex])
            }
          }
        }
      }
    }
  }

  // Cancels every tracking in `trackings`, taking each registrar's lock once
  // for all of them (see `cancelAll(_:)`).
  @available(SwiftStdlib 6.5, *)
  @_spi(Prototype)
  public static func _cancel(_ trackings: [ObservationTracking]) {
    cancelAll(trackings)
  }
}

// One update pass. `track(_:onChange:)` evaluates a body as
// `withObservationTracking(_:onChange:)` does but defers installing its
// tracking; `install()` then installs every tracking of the pass at once. A
// mutation between a body's evaluation and `install()` is not observed, as
// with any mutation before a tracking is installed; batching only lengthens
// that window to the rest of the pass.
@available(SwiftStdlib 6.5, *)
@_spi(Prototype)
public struct _TrackingPass {
  private var pending = ContiguousArray<ObservationTracking.Pending>()

  public init() { }

  public mutating func track<T>(
    _ apply: () -> T,
    onChange: @escaping @Sendable () -> Void
  ) -> (result: T, tracking: ObservationTracking) {
    let accessListResult = generateAccessList(apply)
    guard let list = accessListResult.accessList else {
      return (accessListResult.result, ObservationTracking(entries: nil))
    }
    let tracking = ObservationTracking(entries: list)
    pending.append(ObservationTracking.Pending(
      tracking: tracking,
      list: list,
      handlers: ObservationTracking.Handlers(tracking: tracking, onChange: onChange)
    ))
    return (accessListResult.result, tracking)
  }

  public mutating func install() {
    ObservationTracking.installAll(pending)
    pending.removeAll()
  }
}
#endif

// The machinery behind `ObservationTracking.Listener`, shared by the
// Embedded and non-Embedded builds. A listener's registrations are ordinary
// registrar records, whose `Handlers` closures are the non-capturing
// trampolines below; they reach the listener through its tracking's state.
@available(SwiftStdlib 5.9, *)
extension ObservationTracking {
  // What a listener's deliveries call, and how. Immutable once created, so
  // it is read without the tracking's lock once taken from its state.
  final class ListenerHandler: @unchecked Sendable {
    enum Body {
      case closure(@Sendable (Int) -> Void)
      // Allocates nothing of its own: the context is the caller's.
      case c(@convention(c) (UnsafeMutableRawPointer?, Int) -> Void, UnsafeMutableRawPointer?)
    }

    // The kind of change passed to `Body`, in a C-representable form.
    static var willSetCode: Int { 0 }
    static var didSetCode: Int { 1 }

    let coalesced: Bool
    let body: Body

    init(coalesced: Bool, body: Body) {
      self.coalesced = coalesced
      self.body = body
    }

    func call(_ code: Int) {
      switch body {
      case .closure(let closure):
        closure(code)
      case .c(let function, let context):
        function(context, code)
      }
    }
  }

  // The `Handlers` closures of a listener's registrations. They capture
  // nothing, so forming them allocates nothing.
  fileprivate static var listenerWillSet: @Sendable (ObservationTracking) -> Void {
    { $0.deliverToListener(ListenerHandler.willSetCode) }
  }

  fileprivate static var listenerDidSet: @Sendable (ObservationTracking) -> Void {
    { $0.deliverToListener(ListenerHandler.didSetCode) }
  }

  // A coalesced listener's delivery under way on the current thread, on
  // that thread's stack; `_ThreadLocal.delivering` points at the innermost,
  // and each at the one it is nested in (a handler's write may deliver to
  // another listener).
  struct ListenerDeliveryFrame {
    let listener: ObjectIdentifier
    let previous: UnsafeMutableRawPointer?
  }

  // Whether the current thread is inside a call of `listener`'s handler,
  // however deeply nested. Deliveries on other threads do not count.
  static func isDeliveringOnCurrentThread(_ listener: ListenerHandler) -> Bool {
    let id = ObjectIdentifier(listener)
    var next = _ThreadLocal.delivering
    while let pointer = next {
      let frame = pointer.assumingMemoryBound(to: ListenerDeliveryFrame.self).pointee
      if frame.listener == id { return true }
      next = frame.previous
    }
    return false
  }

  // A coalesced listener delivers only if it is armed, disarming it under
  // the lock, so concurrent writers deliver once. Its handler is called with
  // a frame pushed on this thread's delivery chain, so that `Listener.track`
  // called from the handler, on this thread, does not re-arm it; a call on
  // any other thread meanwhile arms it as usual. Without `.coalesced` every
  // delivery goes through.
  fileprivate func deliverToListener(_ code: Int) {
    let listener: ListenerHandler? = state.withCriticalRegion { state in
      guard !state.cancelled, let listener = state.listener else { return nil }
      if listener.coalesced {
        guard state.armed else { return nil }
        state.armed = false
      }
      return listener
    }
    guard let listener else { return }
    guard listener.coalesced else {
      listener.call(code)
      return
    }
    var frame = ListenerDeliveryFrame(
      listener: ObjectIdentifier(listener),
      previous: _ThreadLocal.delivering
    )
    withUnsafeMutablePointer(to: &frame) { pointer in
      _ThreadLocal.delivering = UnsafeMutableRawPointer(pointer)
      listener.call(code)
      _ThreadLocal.delivering = pointer.pointee.previous
    }
  }
}

@available(SwiftStdlib 6.5, *)
extension ObservationTracking {
  /// A persistent tracking, re-armed in place.
  ///
  /// Each call to ``track(_:)`` records the observable properties its body
  /// reads, replacing what the previous call recorded; the listener is then
  /// notified of changes to them, with the kinds of change its options name
  /// (`.willSet` by default, `.didSet`, or both), until it is cancelled or
  /// dropped. Registrations whose properties are unchanged from the previous
  /// call are kept, and the previous call's storage is reused, so tracking
  /// the same properties again allocates nothing.
  ///
  /// With ``ObservationTracking/Options/coalesced``, the listener is instead
  /// told at least once before the first change to anything it read since
  /// its last notification: a notification disarms it, and only a call to
  /// `track(_:)` made outside its own handler arms it again. A call made
  /// from inside the handler, on the thread running it (to snapshot the new
  /// state), refreshes what is tracked without re-arming, so a burst of
  /// writes notifies once. A call made on any other thread arms it, even
  /// while a handler call is under way elsewhere.
  ///
  ///     var listener = ObservationTracking.Listener(options: [.willSet, .coalesced]) { _ in
  ///       scheduleRender()
  ///     }
  ///     listener.track { render(model) }
  public struct Listener: ~Copyable, Sendable {
    /// The kind code a C-convention handler is passed for a willSet.
    public static var willSetCode: Int { ListenerHandler.willSetCode }

    /// The kind code a C-convention handler is passed for a didSet.
    public static var didSetCode: Int { ListenerHandler.didSetCode }

    private let tracking: ObservationTracking
    private let handlers: Handlers
    // The storage of the list and tokens the previous `track(_:)` replaced,
    // emptied and refilled by the next one, and its per-entry scratch.
    private var spareList = TrackedEntries()
    private var spareTokens = SmallArray<Int>()
    private var kept = ContiguousArray<Bool>()

    /// Creates a listener that calls `onChange` with the kind of each change
    /// it is notified of.
    public init(
      options: ObservationTracking.Options = .willSet,
      onChange: @escaping @Sendable (ObservationTracking.Event.Kind) -> Void
    ) {
      self.init(options: options, body: .closure { code in
        onChange(code == ListenerHandler.willSetCode ? .willSet : .didSet)
      })
    }

    /// Creates a listener that calls the C function `onChange` with
    /// `context` and ``willSetCode`` or ``didSetCode``, allocating nothing
    /// for the handler. `context` must stay valid until the listener is
    /// cancelled or dropped.
    public init(
      options: ObservationTracking.Options = .willSet,
      context: UnsafeMutableRawPointer?,
      onChange: @convention(c) (UnsafeMutableRawPointer?, Int) -> Void
    ) {
      self.init(options: options, body: .c(onChange, context))
    }

    private init(options: ObservationTracking.Options, body: ListenerHandler.Body) {
      let tracking = ObservationTracking(entries: nil)
      let listener = ListenerHandler(coalesced: options.contains(.coalesced), body: body)
      tracking.state.withCriticalRegion { $0.listener = listener }
      self.tracking = tracking
      self.handlers = Handlers(
        tracking: tracking,
        willSet: options.contains(.willSet) ? ObservationTracking.listenerWillSet : nil,
        didSet: options.contains(.didSet) ? ObservationTracking.listenerDidSet : nil
      )
    }

    deinit {
      tracking.cancel()
    }

    /// Stops the listener; it is not notified again.
    public consuming func cancel() {
      // Consuming `self` ends it, and its deinit cancels the tracking.
    }

    /// Tracks the observable properties `apply` reads, in place of those the
    /// previous call tracked, and returns what `apply` returns.
    ///
    /// With ``ObservationTracking/Options/coalesced``, this arms the
    /// listener, unless it is called from inside the listener's own handler
    /// on the thread running that handler.
    public mutating func track<T: ~Copyable, Failure: Error>(
      _ apply: () throws(Failure) -> T
    ) throws(Failure) -> T {
      // Armed before `apply` reads, so a change between the reads and the
      // registrations below is delivered through a kept registration, not
      // lost; but not from inside this listener's own handler on this
      // thread. A handler call on another thread does not stop it.
      let (previousList, previousTokens, cancelled) = tracking.state.withCriticalRegion { state in
        let listener = state.listener!
        if listener.coalesced && !ObservationTracking.isDeliveringOnCurrentThread(listener) {
          state.armed = true
        }
        return (state.list, state.tokens, state.cancelled)
      }
      var seed = TrackedEntries()
      swap(&seed, &spareList)
      seed.removeAll()
      let accessListResult = try generateAccessList(reusing: consume seed, apply)
      guard !cancelled, let list = accessListResult.accessList else {
        return accessListResult.result
      }

      // Per object (by identity, as `TrackedEntries.index(of:)`), a previous
      // registration is re-armed in place, as `install(_:rearming:)` does;
      // the previous registrations of objects no longer read are cancelled.
      var tokens = SmallArray<Int>()
      swap(&tokens, &spareTokens)
      tokens.removeAll()
      var kept = ContiguousArray<Bool>()
      swap(&kept, &self.kept)
      kept.removeAll(keepingCapacity: true)
      for _ in 0..<previousTokens.count { kept.append(false) }
      let handlers = self.handlers
      list.entries.forEach { entry in
        if previousTokens.count > 0,
           let index = previousList.index(of: entry.context) {
          kept[index] = true
          tokens.append(entry.context.updateTracking(
            previousTokens[index], for: entry.properties, handlers: handlers))
        } else {
          tokens.append(entry.context.registerTracking(for: entry.properties, handlers: handlers))
        }
      }
      for index in 0..<previousTokens.count where !kept[index] {
        previousList.entries[index].context.cancel(previousTokens[index])
      }
      self.kept = kept

      let replaced = tracking.state.withCriticalRegion { state -> (TrackedEntries, SmallArray<Int>)? in
        guard !state.cancelled else { return nil }
        let replaced = (state.list, state.tokens)
        state.list = list
        state.tokens = tokens
        return replaced
      }
      if let replaced {
        // Emptied by the next call, once nothing else references them.
        spareList = replaced.0
        spareTokens = replaced.1
      } else {
        // Cancelled while tracking: its cancel found the previous tokens,
        // so cancel these registrations here.
        for index in 0..<tokens.count {
          list.entries[index].context.cancel(tokens[index])
        }
      }
      return accessListResult.result
    }
  }
}
