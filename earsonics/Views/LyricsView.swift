// Views/LyricsView.swift
import SwiftUI

struct LyricsView: View {
    let structured: [StructuredLyrics]
    let plain: Lyrics?
    let currentTime: Double   // seconds
    let onDismiss: () -> Void

    // Use synced lyrics if available
    var syncedLyrics: StructuredLyrics? {
        structured.first(where: { $0.synced == true }) ?? structured.first
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button(action: onDismiss) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                            Text("Back")
                                .font(.headline)
                        }
                    }
                    .buttonStyle(AccentIconButtonStyle())
                    
                    Text("Lyrics")
                        .font(.largeTitle).bold()
                        .padding(.leading, 30)
                    Spacer()
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 30)

                Divider().background(Color.white.opacity(0.2))

                if let synced = syncedLyrics, let lines = synced.lines, !lines.isEmpty {
                    SyncedLyricsView(lines: lines, currentTime: currentTime)
                } else if let value = plain?.value, !value.isEmpty {
                    PlainLyricsView(text: value)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 60)).foregroundColor(.secondary)
                        Text("No lyrics available").font(.title).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onExitCommand {
            onDismiss()
        }
    }
}

// MARK: - Synced Lyrics
struct SyncedLyricsView: View {
    let lines: [StructuredLyrics.Line]
    let currentTime: Double  // seconds

    var currentMs: Int { Int(currentTime * 1000) }

    var currentLineIndex: Int {
        var idx = 0
        for (i, line) in lines.enumerated() {
            if let start = line.start, start <= currentMs { idx = i }
        }
        return idx
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line.value)
                            .font(idx == currentLineIndex ? .title2 : .title3)
                            .fontWeight(idx == currentLineIndex ? .bold : .regular)
                            .foregroundColor(idx == currentLineIndex ? .white : .white.opacity(0.4))
                            .id(idx)
                            .animation(.easeInOut(duration: 0.3), value: currentLineIndex)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
            .onChange(of: currentLineIndex) { _, newIdx in
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(max(0, newIdx - 3), anchor: .top)
                }
            }
        }
    }
}

// MARK: - Plain Lyrics
struct PlainLyricsView: View {
    let text: String
    var body: some View {
        ScrollView {
            Text(text)
                .font(.title3)
                .lineSpacing(10)
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
        }
    }
}
