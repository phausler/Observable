// Counts malloc *events* during a region: libsystem_malloc calls `malloc_logger`,
// when it is set, on every allocation, so a hook installed there sees each
// one, including allocations freed again before the region ends. Net
// `malloc_zone_statistics` deltas (`blocksInUse()` in main.swift) only see
// what is still retained at the end, so they cannot rule out per-call churn.
//
// The hook counts allocations on every thread; measure
// single-threaded regions.

#if canImport(Darwin)
import Darwin
import Synchronization

// void (*)(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3,
//          uintptr_t result, uint32_t num_hot_frames_to_skip)
typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

// MALLOC_LOG_TYPE_ALLOCATE; set for malloc, calloc, and realloc events.
private let mallocLogTypeAllocate: UInt32 = 2

private let mallocEventCounter = Atomic<Int>(0)

// `malloc_logger` is exported by libsystem_malloc but declared in no public
// header, so it is looked up by name (dlsym's RTLD_DEFAULT is -2 on Darwin).
private nonisolated(unsafe) let mallocLoggerPtr: UnsafeMutablePointer<MallocLogger?>? =
  dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")?
    .assumingMemoryBound(to: MallocLogger?.self)

// Must not allocate: it runs inside malloc.
private let countingMallocLogger: MallocLogger = { type, _, _, _, _, _ in
  if type & mallocLogTypeAllocate != 0 {
    mallocEventCounter.add(1, ordering: .relaxed)
  }
}

// Whether malloc events can be counted in this process.
var canCountMallocEvents: Bool { mallocLoggerPtr != nil }

// Runs `body` and returns its result and the number of allocations made
// while it ran, or -1 for the count if `malloc_logger` could not be found.
@inline(never)
func countingMallocEvents<T>(_ body: () throws -> T) rethrows -> (result: T, mallocs: Int) {
  guard let loggerPtr = mallocLoggerPtr else { return (try body(), -1) }
  // Touch the counter (and its lazy initialization) before hooking malloc.
  mallocEventCounter.store(0, ordering: .sequentiallyConsistent)
  loggerPtr.pointee = countingMallocLogger
  defer { loggerPtr.pointee = nil }
  let result = try body()
  return (result, mallocEventCounter.load(ordering: .sequentiallyConsistent))
}
#else
var canCountMallocEvents: Bool { false }

func countingMallocEvents<T>(_ body: () throws -> T) rethrows -> (result: T, mallocs: Int) {
  (try body(), -1)
}
#endif
