// Services/AudioPlayerService.swift
import AVFoundation
import MediaPlayer
import Combine
import SwiftUI

// MARK: - Repeat Mode
enum RepeatMode: String, CaseIterable {
    case off, one, all
    var icon: String {
        switch self {
        case .off: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }
}

// MARK: - Audio Player Service
@MainActor
class AudioPlayerService: NSObject, ObservableObject {
    static let shared = AudioPlayerService()

    private var player: AVQueuePlayer = AVQueuePlayer()
    private var playerItems: [AVPlayerItem] = []
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    @Published var queue: [Song] = []
    @Published var currentIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isBuffering: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isShuffled: Bool = false

    var server: Server? {
        didSet { rebuildPlayerItems() }
    }

    var currentSong: Song? {
        guard !queue.isEmpty, currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    private var originalQueue: [Song] = []

    override init() {
        super.init()
        configureAudioSession()
        setupPlayer()
        setupRemoteCommandCenter()
    }

    // MARK: - Audio Session
    private func configureAudioSession() {
        #if os(tvOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
        #endif
    }

    // MARK: - Player setup
    private func setupPlayer() {
        player.automaticallyWaitsToMinimizeStalling = true

        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isPlaying = (status == .playing)
                self.isBuffering = (status == .waitingToPlayAtSpecifiedRate)
            }
            .store(in: &cancellables)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = time.seconds
                if let dur = self.player.currentItem?.duration,
                   dur.isNumeric, dur.seconds > 0 {
                    self.duration = dur.seconds
                }
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailed),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: nil
        )
    }

    // MARK: - Remote Command Center
    private func setupRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        cc.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        cc.nextTrackCommand.addTarget { [weak self] _ in self?.skipNext(); return .success }
        cc.previousTrackCommand.addTarget { [weak self] _ in self?.skipPrevious(); return .success }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: e.positionTime)
            return .success
        }
    }

    // MARK: - Load songs (pre-loads ALL items for true gapless)
    func load(songs: [Song], startIndex: Int = 0) {
        originalQueue = songs
        if isShuffled {
            var shuffled = songs
            let first = shuffled.remove(at: startIndex)
            shuffled.shuffle()
            shuffled.insert(first, at: 0)
            queue = shuffled
            currentIndex = 0
        } else {
            queue = songs
            currentIndex = startIndex
        }
        rebuildPlayerItems()
        player.play()
        updateNowPlaying()
    }

    // MARK: - Rebuild: loads all remaining songs into AVQueuePlayer upfront
    // This is the key to gapless — AVQueuePlayer pre-buffers the next item.
    // We call pause() only here (structural change), never during natural advance.
    func rebuildPlayerItems() {
        guard let srv = server else { return }
        let wasPlaying = isPlaying
        player.pause()
        player.removeAllItems()
        playerItems = []

        // Load from currentIndex to end so all upcoming tracks are pre-queued
        let songsFromCurrent = Array(queue.dropFirst(currentIndex))
        let items: [AVPlayerItem] = songsFromCurrent.compactMap { song in
            guard let url = SubsonicClient.shared.streamURL(songId: song.id, server: srv) else { return nil }
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 60  // 60s pre-buffer for gapless
            return item
        }
        playerItems = items
        for item in items { player.insert(item, after: nil) }
        if wasPlaying { player.play() }
    }

    // MARK: - Playback controls
    func play() { player.play(); updateNowPlaying() }
    func pause() { player.pause(); updateNowPlaying() }
    func togglePlayPause() { isPlaying ? pause() : play() }

    func skipNext() {
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            // Scrobble current before advancing
            let prev = queue[currentIndex]
            Task { try? await SubsonicClient.shared.scrobble(id: prev.id, server: self.server) }
            currentIndex = nextIndex
            // AVQueuePlayer already has all items pre-queued — just advance
            player.advanceToNextItem()
            updateNowPlaying()
        } else if repeatMode == .all {
            load(songs: queue, startIndex: 0)
        }
    }

    func skipPrevious() {
        if currentTime > 3 {
            seek(to: 0)
        } else if currentIndex > 0 {
            currentIndex -= 1
            rebuildPlayerItems()  // must rebuild: AVQueuePlayer has no go-back API
            player.play()
            updateNowPlaying()
        } else if repeatMode == .all {
            load(songs: queue, startIndex: queue.count - 1)
        }
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    func playFromQueue(index: Int) {
        currentIndex = index
        rebuildPlayerItems()
        player.play()
        updateNowPlaying()
    }

    func addToQueue(_ song: Song) {
        queue.append(song)
        if let srv = server, let url = SubsonicClient.shared.streamURL(songId: song.id, server: srv) {
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 60
            player.insert(item, after: nil)
        }
    }

    func addToQueueNext(_ song: Song) {
        let insertIndex = min(currentIndex + 1, queue.count)
        queue.insert(song, at: insertIndex)
        rebuildPlayerItems()
    }

    func removeFromQueue(at offsets: IndexSet) {
        let affectsPlayback = offsets.contains(where: { $0 <= currentIndex })
        queue.remove(atOffsets: offsets)
        if affectsPlayback { rebuildPlayerItems() }
    }

    func moveQueueItem(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        rebuildPlayerItems()
    }

    // MARK: - Shuffle
    func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled {
            originalQueue = queue
            let current = currentSong
            var rest = queue
            if let c = current { rest.removeAll { $0.id == c.id } }
            rest.shuffle()
            if let c = current { rest.insert(c, at: 0) }
            queue = rest
            currentIndex = 0
        } else {
            if let current = currentSong,
               let origIdx = originalQueue.firstIndex(where: { $0.id == current.id }) {
                queue = originalQueue
                currentIndex = origIdx
            } else {
                queue = originalQueue
                currentIndex = 0
            }
        }
        rebuildPlayerItems()
    }

    // MARK: - Repeat
    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        player.actionAtItemEnd = repeatMode == .one ? .none : .advance
    }

    // MARK: - Item finished (natural gapless advance — no rebuild needed)
    @objc private func playerItemDidFinish(_ notification: Notification) {
        Task { @MainActor in
            if self.repeatMode == .one {
                self.seek(to: 0)
                self.player.play()
                return
            }
            // Scrobble
            let prevSong = self.queue[self.currentIndex]
            Task { try? await SubsonicClient.shared.scrobble(id: prevSong.id, server: self.server) }

            let nextIndex = self.currentIndex + 1
            if nextIndex < self.queue.count {
                // AVQueuePlayer has already advanced to next item (gapless)
                // We just update our index and metadata
                self.currentIndex = nextIndex
                self.updateNowPlaying()
            } else if self.repeatMode == .all {
                self.load(songs: self.queue, startIndex: 0)
            } else {
                self.isPlaying = false
                self.updateNowPlaying()
            }
        }
    }

    @objc private func playerItemFailed(_ notification: Notification) {
        print("Player item failed: \(notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] ?? "unknown")")
    }

    // MARK: - Now Playing Info
    func updateNowPlaying() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist ?? "",
            MPMediaItemPropertyAlbumTitle: song.album ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyPlaybackDuration: song.duration.map { Double($0) } ?? 0
        ]
        if let track = song.track { info[MPMediaItemPropertyAlbumTrackNumber] = track }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
