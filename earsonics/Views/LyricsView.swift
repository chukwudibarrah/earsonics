import SwiftUI

/// Lyrics for the current track.
///
/// tvOS scrolls by moving focus, so every lyric line is focusable — plain
/// text in a ScrollView can't be scrolled with the remote, and a screen with
/// nothing focusable lets Menu fall through and exit the app. Menu itself is
/// handled by `NowPlayingView`, which closes this screen.
struct LyricsView: View {
    let structured: [StructuredLyrics]
    let plain: Lyrics?
    let currentTime: Double   // seconds
    let onSeek: (Double) -> Void
    let onDismiss: () -> Void

    /// Time-synced lyrics, if the server has them.
    private var syncedLines: [StructuredLyrics.Line]? {
        guard let lines = structured.first(where: { $0.synced == true })?.lines, !lines.isEmpty else { return nil }
        return lines
    }

    /// Unsynced lyrics as individual lines: structured-but-unsynced lyrics
    /// first, then the legacy plain-text endpoint.
    private var plainLines: [String]? {
        if let lines = structured.first?.lines, !lines.isEmpty {
            return lines.map(\.value)
        }
        if let value = plain?.value, !value.isEmpty {
            return value.components(separatedBy: .newlines)
        }
        return nil
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

                if let lines = syncedLines {
                    SyncedLyricsView(lines: lines, currentTime: currentTime, onSeek: onSeek)
                } else if let lines = plainLines {
                    PlainLyricsView(lines: lines)
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
    }
}

// MARK: - Line appearance
private struct LyricLineText: View {
    let text: String
    var isCurrent: Bool = false
    let isFocused: Bool
    @Environment(\.appAccent) private var appAccent

    var body: some View {
        Text(text)
            .font(isCurrent ? .title2 : .title3)
            .fontWeight(isCurrent ? .bold : .regular)
            .foregroundColor(isFocused ? appAccent : (isCurrent ? .white : .white.opacity(0.5)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .animation(.easeInOut(duration: 0.3), value: isCurrent)
    }
}

// MARK: - Synced Lyrics
/// Follows playback: the current line is highlighted, kept centred and
/// focused. Moving focus to browse pauses following for a few seconds;
/// selecting a line seeks playback to it.
struct SyncedLyricsView: View {
    let lines: [StructuredLyrics.Line]
    let currentTime: Double  // seconds
    let onSeek: (Double) -> Void

    @FocusState private var focusedLine: Int?
    /// When the user last moved focus to a line other than the current one.
    @State private var lastBrowse = Date.distantPast
    private static let browsePause: TimeInterval = 6

    private var currentLineIndex: Int {
        let ms = Int(currentTime * 1000)
        return lines.lastIndex { ($0.start ?? 0) <= ms } ?? 0
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Button {
                            if let start = line.start {
                                lastBrowse = .distantPast   // resume following from here
                                onSeek(Double(start) / 1000)
                            }
                        } label: {
                            // Instrumental gaps are empty lines; keep them visible
                            // (and focusable) so following never loses its place.
                            LyricLineText(text: line.value.isEmpty ? "♪" : line.value,
                                          isCurrent: idx == currentLineIndex,
                                          isFocused: focusedLine == idx)
                        }
                        .buttonStyle(CardlessButtonStyle())
                        .focused($focusedLine, equals: idx)
                        .id(idx)
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
            .defaultFocus($focusedLine, currentLineIndex)
            .onAppear {
                proxy.scrollTo(currentLineIndex, anchor: .center)
            }
            .onChange(of: focusedLine) { _, new in
                if let new, new != currentLineIndex { lastBrowse = Date() }
            }
            .onChange(of: currentLineIndex) { _, new in
                guard Date().timeIntervalSince(lastBrowse) > Self.browsePause else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(new, anchor: .center)
                }
                // Carry focus along only while it's on the lyrics — never pull
                // it away from the Back button.
                if focusedLine != nil { focusedLine = new }
            }
        }
    }
}

// MARK: - Plain Lyrics
/// Unsynced lyrics: each line is focusable so up/down scrolls through them.
/// Blank lines become stanza gaps and are skipped by focus.
struct PlainLyricsView: View {
    let lines: [String]
    @FocusState private var focusedLine: Int?

    private var firstLyricLine: Int? {
        lines.firstIndex { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                    if line.trimmingCharacters(in: .whitespaces).isEmpty {
                        Color.clear.frame(height: 24)
                    } else {
                        LyricLineText(text: line, isFocused: focusedLine == idx)
                            .focusable()
                            .focused($focusedLine, equals: idx)
                    }
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .defaultFocus($focusedLine, firstLyricLine)
    }
}
