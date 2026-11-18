import Foundation
import Testing
@testable import earsonics
@testable import EarsonicsCore

/// Offline checks of the shared library store and messages (no server is
/// active in unit tests; see `TestIsolationTests`).
@MainActor
@Suite("Library store and messages", .serialized)
struct LibraryStoreTests {
    let store = LibraryStore.shared

    @Test func starredFallsBackToWhatTheServerSaid() {
        store.reset()
        #expect(store.isStarred(.song, id: "x", fetched: Date()))
        #expect(!store.isStarred(.song, id: "x", fetched: nil))
    }

    @Test func withoutAServerThereAreNoPlaylists() async {
        store.reset()
        await store.loadPlaylists()
        #expect(store.playlists.isEmpty)
    }

    @Test func cancellationsAreNotReportedAsFailures() {
        let messages = Messages.shared
        messages.showFailure("search", CancellationError())
        #expect(messages.banner == nil)
        messages.showFailure("search", URLError(.cancelled))
        #expect(messages.banner == nil)
        messages.showFailure("search", URLError(.notConnectedToInternet))
        #expect(messages.banner?.hasPrefix("Couldn’t search.") == true)
    }
}
