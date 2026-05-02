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
    @Published var gaplessCrossfade: Double = 0   // seconds, 0 = true gapless

    // Reference to the server for URL building
    var server: Server? {
        didSet { rebuildPlayerItems() }
    }

    var currentSong: Song? {
        guard !queue.isEmpty, currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    private var originalQueue: [Song] = []  // for shuffle restore

    override init() {
        super.init()
        configureAudioSession()
        setupPlayer()
        setupRemoteCommandCenter()
    }

    // MARK: - Audio Session
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }

    // MARK: - Player setup
    private func setupPlayer() {
        player.automaticallyWaitsToMinimizeStalling = true

        // Observe status
        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isPlaying = (status == .playing)
                self.isBuffering = (status == .waitingToPlayAtSpecifiedRate)
            }
            .store(in: &cancellables)

        // Time observer - update every 0.5s
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = time.seconds
                if let dur = self.player.currentItem?.duration, !dur.isIndefinite {
                    self.duration = dur.seconds
                }
            }
        }

        // Observe item changes for queue advancement
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

    // MARK: - Remote Command Center (for Siri Remote on tvOS)
    private func setupRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.addTarget { [weak self] _ in
            self?.play(); return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            self?.pause(); return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipNext(); return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.skipPrevious(); return .success
        }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: e.positionTime)
            return .success
        }
    }

    // MARK: - Load songs
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

    func rebuildPlayerItems() {
        guard let srv = server else { return }
        player.pause()
        player.removeAllItems()
        playerItems = []

        let songsFromCurrent = Array(queue.dropFirst(currentIndex))
        let items = songsFromCurrent.compactMap { song -> AVPlayerItem? in
            guard let url = SubsonicClient.shared.streamURL(songId: song.id, server: srv) else { return nil }
            let item = AVPlayerItem(url: url)
            // For gapless: preload
            item.preferredForwardBufferDuration = 10
            return item
        }
        playerItems = items
        for item in items { player.insert(item, after: nil) }
    }

    // MARK: - Playback controls
    func play() {
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func skipNext() {
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            currentIndex = nextIndex
            player.advanceToNextItem()
            updateNowPlaying()
            prependItemsIfNeeded()
        } else if repeatMode == .all {
            load(songs: queue, startIndex: 0)
        }
    }

    func skipPrevious() {
        if currentTime > 3 {
            seek(to: 0)
        } else if currentIndex > 0 {
            currentIndex -= 1
            rebuildPlayerItems()
            player.play()
            updateNowPlaying()
        } else if repeatMode == .all {
            load(songs: queue, startIndex: queue.count - 1)
        }
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
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
            player.insert(item, after: nil)
        }
    }

    func addToQueueNext(_ song: Song) {
        let insertIndex = currentIndex + 1
        queue.insert(song, at: min(insertIndex, queue.count))
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

    // MARK: - Observers
    @objc private func playerItemDidFinish(_ notification: Notification) {
        Task { @MainActor in
            if self.repeatMode == .one {
                self.seek(to: 0)
                self.player.play()
                return
            }
            let nextIndex = self.currentIndex + 1
            if nextIndex < self.queue.count {
                self.currentIndex = nextIndex
                self.updateNowPlaying()
                self.prependItemsIfNeeded()
                Task {
                    if let song = self.currentSong {
                        try? await SubsonicClient.shared.scrobble(id: song.id, server: self.server)
                    }
                }
            } else if self.repeatMode == .all {
                self.load(songs: self.queue, startIndex: 0)
            } else {
                self.isPlaying = false
            }
        }
    }

    @objc private func playerItemFailed(_ notification: Notification) {
        print("Player item failed: \(notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] ?? "unknown")")
    }

    // Pre-insert items for truly gapless
    private func prependItemsIfNeeded() {
        // AVQueuePlayer handles gapless natively; just ensure next items are queued
        let remaining = player.items().count
        if remaining < 3 {
            let nextNeeded = currentIndex + remaining
            guard nextNeeded < queue.count, let srv = server else { return }
            for i in nextNeeded..<min(nextNeeded + 2, queue.count) {
                let song = queue[i]
                if let url = SubsonicClient.shared.streamURL(songId: song.id, server: srv) {
                    let item = AVPlayerItem(url: url)
                    player.insert(item, after: nil)
                }
            }
        }
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
        if let track = song.track {
            info[MPMediaItemPropertyAlbumTrackNumber] = track
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
