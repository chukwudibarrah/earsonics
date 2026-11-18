// EarsonicsCore/Messages.swift
import Foundation
import Observation

/// A short message shown at the bottom of the screen for a few seconds —
/// the outcome of an action ("Added to …"), or why it failed — so nothing
/// fails silently. Shown once, at the app root (`ContentView`).
@MainActor
@Observable
public final class Messages {
    public static let shared = Messages()

    public private(set) var banner: String?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    public func show(_ message: String) {
        hideTask?.cancel()
        banner = message
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }

    /// "Couldn't <action>." plus the reason, for a failed action. A request
    /// that was cancelled (e.g. a search superseded by more typing, or a
    /// screen closed mid-load) isn't a failure and shows nothing.
    public func showFailure(_ action: String, _ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        show("Couldn’t \(action). \(error.localizedDescription)")
    }
}
