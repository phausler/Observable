import Testing
@_spi(SwiftUI) import Observation
import Dispatch
import Synchronization
#if canImport(Darwin)
import Darwin

// Review note R2: the stack each level of recursive synchronous delivery
// uses, and the allocations delivery makes for the handlers it collects
// (`Context.notify` and `inlineCallbackCapacity` in ObservationRegistrar.swift).
//
// Stack use is measured by painting: the chain runs on a thread whose stack is
// memory this file maps (under a guard page) and fills with a pattern, and
// what the thread used is the part of it no longer holding the pattern. Two
// chain depths are measured, so the thread's fixed cost cancels out of the
// bytes per level. Run in release to compare with the review's `-O` figures:
//   swift test -c release --filter deliveryChainStackBytesPerLevel

private let stackPattern: UInt64 = 0xA5A5_5A5A_A5A5_5A5A

// Runs `body` on a new thread with a painted stack of `stackSize` bytes (a
// multiple of the page size) and returns how many bytes of it were used, or
// nil if the thread could not be run.
private func stackHighWaterMark(stackSize: Int, _ body: @escaping @Sendable () -> Void) -> Int? {
  let page = Int(getpagesize())
  let mapped = page + stackSize
  guard let region = mmap(nil, mapped, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0),
        region != UnsafeMutableRawPointer(bitPattern: -1) else { return nil }
  // The lowest page is the guard page: overflowing faults instead of
  // writing past the mapping.
  guard mprotect(region, page, PROT_NONE) == 0 else {
    munmap(region, mapped)
    return nil
  }
  let stack = region + page
  let wordCount = stackSize / MemoryLayout<UInt64>.stride
  let words = stack.bindMemory(to: UInt64.self, capacity: wordCount)
  words.initialize(repeating: stackPattern, count: wordCount)

  final class Box: @unchecked Sendable {
    let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
  }
  let done = DispatchSemaphore(value: 0)
  let box = Unmanaged.passRetained(Box {
    body()
    done.signal()
  })
  var attributes = pthread_attr_t()
  pthread_attr_init(&attributes)
  pthread_attr_setstack(&attributes, stack, stackSize)
  var thread: pthread_t?
  let result = pthread_create(&thread, &attributes, { context in
    let box = Unmanaged<Box>.fromOpaque(context).takeRetainedValue()
    box.body()
    return nil
  }, box.toOpaque())
  pthread_attr_destroy(&attributes)
  guard result == 0, let thread else {
    box.release()
    munmap(region, mapped)
    return nil
  }
  // Bounded, so a hung chain fails the test; its stack is then left mapped.
  guard done.wait(timeout: .now() + .seconds(30)) == .success else { return nil }
  pthread_join(thread, nil)

  var untouched = 0
  while untouched < wordCount && words[untouched] == stackPattern {
    untouched += 1
  }
  munmap(region, mapped)
  return stackSize - untouched * MemoryLayout<UInt64>.stride
}

// The stack used by a chain of `depth` synchronous deliveries, as
// `parityDeepSynchronousDeliveryChainOnSecondaryThreadStack` runs one: each
// link's onChange writes to the next link.
private func deliveryChainStackUse(depth: Int) -> Int? {
  let links = (0...depth).map { _ in ParityLink() }
  let reached = Mutex(0)
  for index in 0..<depth {
    let next = links[index + 1]
    withObservationTracking {
      _ = links[index].value
    } onChange: {
      reached.withLock { $0 = max($0, index + 1) }
      next.value += 1
    }
  }
  let used = stackHighWaterMark(stackSize: 4 << 20) {
    links[0].value += 1
  }
  guard reached.withLock({ $0 }) == depth else { return nil }
  return used
}

@Test(.timeLimit(.minutes(1)))
func deliveryChainStackBytesPerLevel() throws {
  let shallow = 50
  let deep = 100
  let shallowUse = try #require(deliveryChainStackUse(depth: shallow))
  let deepUse = try #require(deliveryChainStackUse(depth: deep))
  let perLevel = (deepUse - shallowUse) / (deep - shallow)
  print("R2 stack probe: depth \(shallow): \(shallowUse) B, depth \(deep): \(deepUse) B, \(perLevel) B per level")
  #expect(perLevel > 0)
}

// Counts allocations, through `malloc_logger` as the benchmark's
// MallocEventCount.swift does, but only those made on the counting thread,
// so tests running alongside are not counted.
private typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

private nonisolated(unsafe) let mallocLoggerPtr: UnsafeMutablePointer<MallocLogger?>? =
  dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")?
    .assumingMemoryBound(to: MallocLogger?.self)

private let countedThread = Atomic<UInt>(0)
private let countedMallocs = Atomic<Int>(0)

// Must not allocate: it runs inside malloc.
private let countingMallocLogger: MallocLogger = { type, _, _, _, _, _ in
  // MALLOC_LOG_TYPE_ALLOCATE
  if type & 2 != 0, UInt(bitPattern: pthread_self()) == countedThread.load(ordering: .relaxed) {
    countedMallocs.add(1, ordering: .relaxed)
  }
}

private let mallocCounting = Mutex(())

// The allocations made on this thread while `body` ran, or nil if
// `malloc_logger` could not be found.
private func countingMallocEvents(_ body: () -> Void) -> Int? {
  guard let ptr = mallocLoggerPtr else { return nil }
  return mallocCounting.withLock { _ in
    countedMallocs.store(0, ordering: .sequentiallyConsistent)
    countedThread.store(UInt(bitPattern: pthread_self()), ordering: .sequentiallyConsistent)
    let previous = ptr.pointee
    ptr.pointee = countingMallocLogger
    body()
    ptr.pointee = previous
    countedThread.store(0, ordering: .sequentiallyConsistent)
    return countedMallocs.load(ordering: .sequentiallyConsistent)
  }
}

// The common case, a mutation delivered to one or two trackings, collects
// its handlers without allocating. Only optimized builds are held to that:
// unoptimized code allocates per write and per handler regardless of
// `inlineCallbackCapacity` (4 and 7 allocations per write for one and two).
// Run with `swift test -c release --filter deliveryToFewHandlersDoesNotAllocate`.
@Test(arguments: [1, 2])
func deliveryToFewHandlersDoesNotAllocate(handlers: Int) throws {
  let link = ParityLink()
  let fired = Atomic<Int>(0)
  for _ in 0..<handlers {
    withObservationTracking({ _ = link.value }, willSet: { _ in fired.add(1, ordering: .relaxed) })
  }
  link.value = 1  // warm
  let writes = 1000
  guard let mallocs = countingMallocEvents({
    for index in 0..<writes { link.value = index + 2 }
  }) else { return }
  print("R2 malloc probe: \(handlers) handler(s): \(mallocs) mallocs in \(writes) writes")
  #expect(fired.load(ordering: .relaxed) == handlers * (writes + 1))
  #if !DEBUG
  #expect(mallocs == 0)
  #endif
}
#endif
