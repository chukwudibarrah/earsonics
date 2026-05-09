// Views/Shared/CoverArtView.swift
import SwiftUI

struct CoverArtView: View {
    let id: String?
    var size: Int = 300
    @State private var image: Image? = nil
    @State private var isLoading = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
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
              let url = SubsonicClient.shared.coverArtURL(id: artId, size: size) else {
            isLoading = false
            return
        }
        isLoading = true
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let uiImage = UIImage(data: data) {
                image = Image(uiImage: uiImage)
            }
        } catch { }
        isLoading = false
    }
}
