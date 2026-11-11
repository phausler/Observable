import Testing
import Dispatch

// The Embedded spinlock in the Support C shim (Sources/Support/TLS.c) backs
// Lock only on Embedded targets without an OS mutex, but it is compiled for
// every target, so its mutual exclusion is checked here on the host.
@_silgen_name("_swift_observation_embedded_lock_init")
private func _embeddedLockInit(_ lock: UnsafeMutablePointer<UInt32>)

@_silgen_name("_swift_observation_embedded_lock_lock")
private func _embeddedLockLock(_ lock: UnsafeMutablePointer<UInt32>)

@_silgen_name("_swift_observation_embedded_lock_unlock")
private func _embeddedLockUnlock(_ lock: UnsafeMutablePointer<UInt32>)

@Test(.timeLimit(.minutes(1)))
func testEmbeddedSpinlockContention() async {
  let threads = 2
  let iterations = 100_000
  nonisolated(unsafe) let lock = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
  nonisolated(unsafe) let counter = UnsafeMutablePointer<Int>.allocate(capacity: 1)
  defer {
    lock.deallocate()
    counter.deallocate()
  }
  _embeddedLockInit(lock)
  counter.initialize(to: 0)

  await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
    DispatchQueue.global().async {
      DispatchQueue.concurrentPerform(iterations: threads) { _ in
        for _ in 0..<iterations {
          _embeddedLockLock(lock)
          // A non-atomic read-modify-write: lost updates if exclusion fails.
          counter.pointee += 1
          _embeddedLockUnlock(lock)
        }
      }
      done.resume()
    }
  }

  #expect(counter.pointee == threads * iterations)
  #expect(lock.pointee == 0)
}
