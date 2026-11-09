import Foundation
import Testing
@testable import earsonics

@Suite("Keychain", .serialized)
struct KeychainHelperTests {
    /// A throwaway account, so no real server's entry is touched.
    private let account = "unit-test-\(UUID().uuidString)"

    @Test func savesUpdatesAndDeletes() {
        defer { KeychainHelper.delete(account: account) }
        #expect(KeychainHelper.read(account: account) == nil)

        #expect(KeychainHelper.save("first", account: account))
        #expect(KeychainHelper.read(account: account) == "first")

        // Saving again updates in place.
        #expect(KeychainHelper.save("second", account: account))
        #expect(KeychainHelper.read(account: account) == "second")

        KeychainHelper.delete(account: account)
        #expect(KeychainHelper.read(account: account) == nil)
    }

    @Test func handlesUnicodeAndEmptyPasswords() {
        defer { KeychainHelper.delete(account: account) }
        #expect(KeychainHelper.save("pässwörd 🔑", account: account))
        #expect(KeychainHelper.read(account: account) == "pässwörd 🔑")
        #expect(KeychainHelper.save("", account: account))
        #expect(KeychainHelper.read(account: account) == "")
    }
}
