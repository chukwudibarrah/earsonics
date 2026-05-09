// Views/Shared/StarButton.swift
import SwiftUI

struct StarButton: View {
    let isStarred: Bool
    var songId: String? = nil
    var albumId: String? = nil
    var artistId: String? = nil
    var onToggle: ((Bool) -> Void)? = nil

    @State private var working = false

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Image(systemName: isStarred ? "heart.fill" : "heart")
                .foregroundColor(isStarred ? .red : .white)
                .font(.title2)
        }
        .disabled(working)
        .buttonStyle(.plain)
    }

    private func toggle() async {
        working = true
        do {
            if isStarred {
                try await SubsonicClient.shared.unstar(songId: songId, albumId: albumId, artistId: artistId)
                onToggle?(false)
            } else {
                try await SubsonicClient.shared.star(songId: songId, albumId: albumId, artistId: artistId)
                onToggle?(true)
            }
        } catch { }
        working = false
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
