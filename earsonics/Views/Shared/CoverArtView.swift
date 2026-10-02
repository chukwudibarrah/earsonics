// Views/Shared/CoverArtView.swift
import SwiftUI

struct CoverArtView: View {
    let id: String?
    var size: Int = 300
    @State private var image: Image? = nil
    @State private var isLoading = true

    var body: some View {
        ZStack {
//            RoundedRectangle(cornerRadius: 10)
//                .fill(Color.gray.opacity(0.25))
            if let img = image {
                img
                    .resizable()
                    .scaledToFill()
                    .clipped()
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 40))
//                    .foregroundColor(.gray)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: id) { await loadImage() }
    }

    private func loadImage() async {
        guard let artId = id,
              let server = SubsonicClient.shared.server,
              let url = SubsonicClient.shared.coverArtURL(id: artId, size: size, server: server) else {
            image = nil
            isLoading = false
            return
        }
        isLoading = true
        let uiImage = await ImageCache.shared.image(for: artId, size: size, serverID: server.id, url: url)
        // Replace (not just set on success) so a failed load never leaves the
        // previous id's artwork showing.
        image = uiImage.map { Image(uiImage: $0) }
        isLoading = false
    }
}
