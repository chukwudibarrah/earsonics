import Foundation
import SwiftUI
import Testing
@testable import earsonics
@testable import EarsonicsCore

/// The queue's own move/remove helpers must behave exactly like SwiftUI's
/// (which the queue used before it stopped depending on SwiftUI): compared
/// on many random cases.
@Suite("Queue collection helpers")
struct CollectionHelperTests {
    @Test func moveMatchesSwiftUI() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let count = Int.random(in: 1...8, using: &generator)
            let original = Array(0..<count)
            let source = IndexSet(original.filter { _ in Bool.random(using: &generator) })
            guard !source.isEmpty else { continue }
            let destination = Int.random(in: 0...count, using: &generator)

            var ours = original
            ours.moveElements(fromOffsets: source, toOffset: destination)
            var swiftUI = original
            swiftUI.move(fromOffsets: source, toOffset: destination)
            #expect(ours == swiftUI, "move \(Array(source)) to \(destination) in \(original)")
        }
    }

    @Test func removeMatchesSwiftUI() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let count = Int.random(in: 0...8, using: &generator)
            let original = Array(0..<count)
            let offsets = IndexSet(original.filter { _ in Bool.random(using: &generator) })

            var ours = original
            ours.removeElements(atOffsets: offsets)
            var swiftUI = original
            swiftUI.remove(atOffsets: offsets)
            #expect(ours == swiftUI, "remove \(Array(offsets)) from \(original)")
        }
    }
}
