// Views/Shared/StarButton.swift
import SwiftUI
import EarsonicsCore

/// A heart that stars or un-stars a song, album or artist. Its state comes
/// from `LibraryStore`, so it stays in step with every other screen.
struct StarButton: View {
    let kind: LibraryStore.StarKind
    let id: String
    /// The item's starred date as fetched from the server.
    let fetched: Date?

    @State private var working = false

    private var isStarred: Bool {
        LibraryStore.shared.isStarred(kind, id: id, fetched: fetched)
    }

    var body: some View {
        Button {
            Task {
                working = true
                await LibraryStore.shared.toggleStar(kind, id: id, isStarred: isStarred)
                working = false
            }
        } label: {
            Image(systemName: isStarred ? "heart.fill" : "heart")
                .foregroundColor(isStarred ? .red : .white)
                .font(.title2)
        }
        .disabled(working)
        .buttonStyle(AccentPillButtonStyle())
        .accessibilityLabel(isStarred ? "Remove from Favourites" : "Add to Favourites")
    }
}

struct FormatBadge: View {
    let song: Song
    var body: some View {
        if let suffix = song.suffix?.uppercased() {
            Text(suffix)
                .font(.caption2).bold()
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(song.isLossless ? Color.green : Color.blue)
                .foregroundColor(.white)
                .clipShape(Capsule())
        }
    }
}
