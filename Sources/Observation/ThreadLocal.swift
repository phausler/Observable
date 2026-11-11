//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

@_silgen_name("_swift_observation_tls_get")
func _tlsGet() -> UnsafeMutableRawPointer?

@_silgen_name("_swift_observation_tls_set")
func _tlsSet(_ value: UnsafeMutableRawPointer?)

@_silgen_name("_swift_observation_delivering_get")
func _deliveringGet() -> UnsafeMutableRawPointer?

@_silgen_name("_swift_observation_delivering_set")
func _deliveringSet(_ value: UnsafeMutableRawPointer?)

@_silgen_name("_swift_observation_traversal_get")
func _traversalGet() -> UnsafeMutableRawPointer?

@_silgen_name("_swift_observation_traversal_set")
func _traversalSet(_ value: UnsafeMutableRawPointer?)

@available(SwiftStdlib 5.9, *)
struct _ThreadLocal {
  static var value: UnsafeMutableRawPointer? {
    get {
      return _tlsGet()
    }
    set {
      _tlsSet(newValue)
    }
  }

  // The innermost `ObservationTracking.Listener` delivery under way on this
  // thread; see `ObservationTracking.ListenerDeliveryFrame`.
  static var delivering: UnsafeMutableRawPointer? {
    get {
      return _deliveringGet()
    }
    set {
      _deliveringSet(newValue)
    }
  }

  // The innermost `ObservationDerivedValue` traversal under way on this
  // thread; reached through `_Traversals`, which keeps it.
  static var traversal: UnsafeMutableRawPointer? {
    get {
      return _traversalGet()
    }
    set {
      _traversalSet(newValue)
    }
  }
}
