// EarsonicsCore/NetworkMonitor.swift
import Foundation
import Network
import os

/// Whether the device is online, and whether the connection costs the user
/// (mobile data, a personal hotspot, or Low Data Mode). Readable from any
/// thread; `onChange` runs on the main actor.
public nonisolated final class NetworkMonitor: @unchecked Sendable {
    public static let shared = NetworkMonitor()

    public struct Status: Equatable, Sendable {
        public var isOnline = true
        public var isCostly = false
    }

    private let monitor = NWPathMonitor()
    private let status = OSAllocatedUnfairLock(initialState: Status())
    private let observers = OSAllocatedUnfairLock(initialState: [@Sendable (Status) -> Void]())

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let new = Status(isOnline: path.status == .satisfied,
                             isCostly: path.isExpensive || path.isConstrained)
            let changed = self.status.withLock { old -> Bool in
                defer { old = new }
                return old != new
            }
            guard changed else { return }
            for observer in self.observers.withLock({ $0 }) { observer(new) }
        }
        monitor.start(queue: DispatchQueue(label: "earsonics.network-monitor"))
    }

    public var current: Status { status.withLock { $0 } }
    public var isOnline: Bool { current.isOnline }
    /// Mobile data, a hotspot, or Low Data Mode.
    public var isCostly: Bool { current.isCostly }

    /// Called (on any thread) whenever the status changes.
    public func observe(_ handler: @escaping @Sendable (Status) -> Void) {
        observers.withLock { $0.append(handler) }
    }
}
