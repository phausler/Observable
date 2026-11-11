#if defined(__APPLE__)
#include <TargetConditionals.h>
#include <pthread.h>
#endif
#include <stdint.h>
#include <stdbool.h>
#include <stdatomic.h>
// The Darwin thread-specific-data fast path below reads the TSD base register
// directly on arm64 non-simulator only. clang defines __APPLE__ only for Darwin
// targets, so bare-metal Embedded triples (armv7em-none-none-eabi,
// riscv32-none-none-eabi), which have neither TargetConditionals.h nor a TSD
// base, take the fallback after it. x86_64 macOS and all simulators (regardless
// of architecture) use portable pthread_getspecific/pthread_setspecific.
#if defined(__APPLE__) && defined(__arm64__) && !TARGET_OS_SIMULATOR
__attribute__((always_inline, const))
static __inline__ void**
_os_tsd_get_base(void)
{
	/*
	 * <rdar://73762648> Do not use __builtin_arm_rsr64("TPIDRRO_EL0")
	 * so that the "const" attribute takes effect and repeated use
	 * is coalesced properly.
	 */
	uint64_t tsd;
	__asm__ ("mrs %0, TPIDRRO_EL0" : "=r" (tsd));
	return (void**)(uintptr_t)tsd;
}
#define _os_tsd_get_base()  _os_tsd_get_base()

#ifdef _os_tsd_get_base
__attribute__((always_inline))
static __inline__ void*
_os_tsd_get_direct(unsigned long slot)
{
	return _os_tsd_get_base()[slot];
}

__attribute__((always_inline))
static __inline__ int
_os_tsd_set_direct(unsigned long slot, void *val)
{
	_os_tsd_get_base()[slot] = val;
	return 0;
}
#endif

void *_swift_observation_tls_get(void) {
	return _os_tsd_get_direct(106);
}

void _swift_observation_tls_set(void *value) {
	_os_tsd_set_direct(106, value);
}
#elif defined(__APPLE__)
// x86_64 macOS and all simulators use portable pthread_getspecific/setspecific
void *_swift_observation_tls_get(void) {
	return pthread_getspecific(106);
}

void _swift_observation_tls_set(void *value) {
	pthread_setspecific(106, value);
}
#elif defined(__linux__) || defined(_WIN32) || defined(__FreeBSD__) || defined(__OpenBSD__)
// Thread-local slot for hosted non-Apple targets (Linux, Windows, FreeBSD, OpenBSD).
static _Thread_local void *_swift_observation_tls_value;

void *_swift_observation_tls_get(void) {
	return _swift_observation_tls_value;
}

void _swift_observation_tls_set(void *value) {
	_swift_observation_tls_value = value;
}
#else
// Bare-metal fallback. These triples are compile-only in the Embedded matrix
// (Scripts/embedded-check.sh), so one global stands in for the thread-local
// slot; it is only correct while a single thread uses it.
static void *_swift_observation_tls_value;

void *_swift_observation_tls_get(void) {
	return _swift_observation_tls_value;
}

void _swift_observation_tls_set(void *value) {
	_swift_observation_tls_value = value;
}
#endif

// The innermost ObservationTracking.Listener delivery under way on this
// thread (a stack frame linked to the ones it is nested in), so a listener's
// track() can tell a call from inside its own handler on this thread from a
// call on any other thread. A C11 thread-local on hosted targets; on the
// bare-metal triples, as above, one global stands in.
#if defined(__APPLE__) || defined(__linux__) || defined(_WIN32) || defined(__FreeBSD__) || defined(__OpenBSD__)
static _Thread_local void *_swift_observation_delivering_value;
#else
static void *_swift_observation_delivering_value;
#endif

void *_swift_observation_delivering_get(void) {
	return _swift_observation_delivering_value;
}

void _swift_observation_delivering_set(void *value) {
	_swift_observation_delivering_value = value;
}

// The innermost ObservationDerivedValue traversal under way on this thread (a
// stack frame linked to the ones it is nested in), which a registrar's access
// stamps as visited and folds its mutation stamp into. Placed as the slot
// above. Kept by `_Traversals` (Sources/Observation/ObservationDerived.swift),
// which reaches it only while some traversal is under way.
#if defined(__APPLE__) || defined(__linux__) || defined(_WIN32) || defined(__FreeBSD__) || defined(__OpenBSD__)
static _Thread_local void *_swift_observation_traversal_value;
#else
static void *_swift_observation_traversal_value;
#endif

void *_swift_observation_traversal_get(void) {
	return _swift_observation_traversal_value;
}

void _swift_observation_traversal_set(void *value) {
	_swift_observation_traversal_value = value;
}

// A compare-and-swap spinlock backing Lock (Sources/Observation/Locking.swift)
// on Embedded targets that have no OS mutex. 0 is unlocked, 1 is locked.
// Compiled for every target, so it can also be exercised on the host.
_Static_assert(sizeof(_Atomic(uint32_t)) == sizeof(uint32_t), "atomic uint32_t must be four bytes");

void _swift_observation_embedded_lock_init(_Atomic(uint32_t) *lock) {
	atomic_init(lock, 0);
}

void _swift_observation_embedded_lock_lock(_Atomic(uint32_t) *lock) {
	for (;;) {
		uint32_t expected = 0;
		if (atomic_compare_exchange_weak_explicit(lock, &expected, 1,
				memory_order_acquire, memory_order_relaxed)) {
			return;
		}
		// Wait until it looks free before trying the exchange again, so
		// waiters spin on a read instead of contending writes.
		while (atomic_load_explicit(lock, memory_order_relaxed) != 0) {
		}
	}
}

void _swift_observation_embedded_lock_unlock(_Atomic(uint32_t) *lock) {
	atomic_store_explicit(lock, 0, memory_order_release);
}
