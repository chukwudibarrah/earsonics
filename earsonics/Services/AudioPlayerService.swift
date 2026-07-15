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

// MARK: - Playback Transition State
enum PlaybackTransitionState {
    case idle
    case prewarming
    case crossfading
}

// MARK: - Audio Player Service
@MainActor
class AudioPlayerService: NSObject, ObservableObject {
    static let shared = AudioPlayerService()

    private var deckA: AVPlayer
    private var deckB: AVPlayer
    private var activeDeck: AVPlayer
    
    // Observers and Timers
    private var timeObserverA: Any?
    private var timeObserverB: Any?
    private var fadeDisplayLink: CADisplayLink?
    
    // Transition State
    private var transitionState: PlaybackTransitionState = .idle
    private var fadeStartTime: CFTimeInterval = 0
    private var fadeStartDuration: Double = 0
    private var hasUpdatedMetadataDuringFade = false
    
    // Telemetry for startup latency
    private var lastStreamRequestTime: CFTimeInterval = 0
    private var recentStartupLatencies: [Double] = []
    
    // Settings mapping
    @AppStorage("crossfadeDuration") private var appCrossfadeDuration: Double = 0.0
    @AppStorage("normalizeVolume") var normalizeVolume: Bool = true
    
    // Transition State additions
    private var fadeOutVolume: Float = 1.0
    private var fadeInVolume: Float = 1.0

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

    // Caching: one resource-loader delegate per streaming player item. The
    // resource loader holds its delegate weakly, so we keep a strong reference
    // here keyed by item and release it (cancelling its download) when the item
    // is replaced. Items played straight from the cache file have no delegate.
    private var loaderDelegates: [ObjectIdentifier: CachingResourceLoaderDelegate] = [:]
    private static let cacheScheme = "earsonicscache"

    override init() {
        self.deckA = AVPlayer()
        self.deckB = AVPlayer()
        self.activeDeck = self.deckA
        
        super.init()
        
        deckA.automaticallyWaitsToMinimizeStalling = true
        deckB.automaticallyWaitsToMinimizeStalling = true
        activeDeck.volume = 1.0

        configureAudioSession()
        setupPlayer(deck: deckA, isDeckA: true)
        setupPlayer(deck: deckB, isDeckA: false)
        setupItemNotifications()
        setupRemoteCommandCenter()
    }
    
    deinit {
        fadeDisplayLink?.invalidate()
    }

    // MARK: - Audio Session
    private func configureAudioSession() {
        #if os(tvOS)
        // Session activation can block, so keep it off the main thread.
        // Playback starts on user action long after launch, so the async
        // activation always completes in time.
        Task.detached(priority: .userInitiated) {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
            } catch {
                print("Audio session error: \(error)")
            }
        }
        #endif
    }

    // MARK: - Player setup
    private func setupPlayer(deck: AVPlayer, isDeckA: Bool) {
        deck.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self = self, self.activeDeck === deck else { return }
                self.isPlaying = (status == .playing)
                self.isBuffering = (status == .waitingToPlayAtSpecifiedRate)
            }
            .store(in: &cancellables)

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        let observer = deck.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.handleTimeTick(for: deck, time: time.seconds)
            }
        }
        
        if isDeckA {
            timeObserverA = observer
        } else {
            timeObserverB = observer
        }
    }

    // MARK: - Item notifications
    // Registered once (not per deck) so each notification is delivered a single
    // time — otherwise a natural track end would double-skip and double-scrobble.
    private func setupItemNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidFinish(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailed(_:)),
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
            // Guard against seeking during fade (it's handled in seek method, but adding here as safety)
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
    }

    // MARK: - Target Volume helper
    private func getTargetVolume(for song: Song?) -> Float {
        guard normalizeVolume, let gain = song?.replayGain?.trackGain else { return 1.0 }
        
        let scalar = pow(10.0, gain / 20.0)
        let peak = song?.replayGain?.trackPeak ?? 0.0
        let peakSafeScalar = peak > 0 ? min(scalar, 1.0 / peak) : scalar
        return Float(min(peakSafeScalar, 1.0))
    }

    // MARK: - Player item construction / teardown

    /// Builds a player item for a song, honouring the streaming/cache quality
    /// setting. Plays from the cache file on a hit; otherwise streams through the
    /// caching resource loader (unless caching is disabled).
    private func makePlayerItem(for song: Song, server srv: Server) -> AVPlayerItem? {
        let quality = StreamQuality.current
        guard let streamURL = SubsonicClient.shared.streamURL(songId: song.id, quality: quality, server: srv) else {
            return nil
        }
        let cachingEnabled = UserDefaults.standard.object(forKey: "audioCacheEnabled") as? Bool ?? true
        guard cachingEnabled else { return AVPlayerItem(url: streamURL) }

        if let cached = AudioCache.cachedFileURL(for: song.id, quality: quality) {
            return AVPlayerItem(url: cached)
        }

        // Swap the scheme to a custom one so AVFoundation routes byte requests
        // through our resource-loader delegate.
        guard var comps = URLComponents(url: streamURL, resolvingAgainstBaseURL: false) else {
            return AVPlayerItem(url: streamURL)
        }
        comps.scheme = Self.cacheScheme
        guard let customURL = comps.url else { return AVPlayerItem(url: streamURL) }

        let delegate = CachingResourceLoaderDelegate(
            realURL: streamURL, songId: song.id, quality: quality,
            contentType: song.contentType, suffix: song.suffix,
            size: song.size.map(Int64.init))
        let asset = AVURLAsset(url: customURL)
        asset.resourceLoader.setDelegate(delegate, queue: delegate.loaderQueue)
        let item = AVPlayerItem(asset: asset)
        loaderDelegates[ObjectIdentifier(item)] = delegate
        return item
    }

    /// Replaces the current item on a deck, tearing down the outgoing item's
    /// resource-loader delegate (if any) so its download is cancelled.
    private func setItem(_ item: AVPlayerItem?, on deck: AVPlayer) {
        if let old = deck.currentItem,
           let delegate = loaderDelegates.removeValue(forKey: ObjectIdentifier(old)) {
            delegate.invalidate()
        }
        deck.replaceCurrentItem(with: item)
    }

    // MARK: - Rebuild: sets up current track on active deck
    func rebuildPlayerItems() {
        guard let srv = server else { return }
        
        transitionState = .idle
        stopCrossfadeDisplayLink()
        hasUpdatedMetadataDuringFade = false

        // Stop both decks
        deckA.pause()
        setItem(nil, on: deckA)
        deckB.pause()
        setItem(nil, on: deckB)

        activeDeck = deckA
        activeDeck.volume = getTargetVolume(for: currentSong)

        guard currentIndex >= 0, currentIndex < queue.count else { return }
        let currentSong = queue[currentIndex]

        guard let item = makePlayerItem(for: currentSong, server: srv) else { return }

        // Setup observer for when it's ready to play (for latency telemetry if it was prewarmed, though here it's direct play)
        setItem(item, on: activeDeck)
        activeDeck.play()
        updateNowPlaying()
    }

    // MARK: - Time Tick and Transitions
    private func handleTimeTick(for deck: AVPlayer, time: Double) {
        // Only drive UI and transition logic from the active deck
        guard deck === activeDeck else { return }
        
        self.currentTime = time
        if let dur = deck.currentItem?.duration, dur.isNumeric, dur.seconds > 0 {
            self.duration = dur.seconds
            
            checkTransitionPhase(currentTime: time, duration: dur.seconds)
        }
    }
    
    private func getAdaptivePrewarmBudget() -> Double {
        // Minimum budget of 2s, maximum of 10s based on recent transcoder startups
        guard !recentStartupLatencies.isEmpty else { return 4.0 }
        let avg = recentStartupLatencies.reduce(0, +) / Double(recentStartupLatencies.count)
        return min(max(avg * 1.5, 2.0), 10.0)
    }

    private func checkTransitionPhase(currentTime: Double, duration: Double) {
        let fadeDuration = appCrossfadeDuration
        let prewarmBudget = getAdaptivePrewarmBudget()
        
        let remainingTime = duration - currentTime
        
        // 1. Check for Prewarming (start T-(fade+budget) )
        if transitionState == .idle && remainingTime <= (fadeDuration + prewarmBudget) {
            startPrewarming()
        }
        
        // 2. Check for Crossfading (start T-fade )
        if transitionState == .prewarming && remainingTime <= fadeDuration {
            // For 0s crossfade, we just trigger the swap here
            startCrossfade()
        }
    }
    
    private func getNextSong() -> Song? {
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            return queue[nextIndex]
        } else if repeatMode == .all {
            return queue.first
        }
        // repeatMode == .one is handled at end of track by seeking
        return nil
    }

    private func startPrewarming() {
        guard transitionState == .idle else { return }
        guard let nextSong = getNextSong(), let srv = server else { return }
        guard let item = makePlayerItem(for: nextSong, server: srv) else { return }

        transitionState = .prewarming

        let standbyDeck = (activeDeck === deckA) ? deckB : deckA
        standbyDeck.volume = 0.0

        lastStreamRequestTime = CACurrentMediaTime()
        
        // KVO for ready to play status to update recentStartupLatencies
        item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self = self else { return }
                if status == .readyToPlay {
                    let latency = CACurrentMediaTime() - self.lastStreamRequestTime
                    self.recentStartupLatencies.append(latency)
                    if self.recentStartupLatencies.count > 5 { self.recentStartupLatencies.removeFirst() }
                }
            }
            .store(in: &cancellables)
        
        setItem(item, on: standbyDeck)
        // Ensure standby deck starts loading
        standbyDeck.play()
        standbyDeck.pause() // Play/pause forces buffer to start
    }
    
    private func startCrossfade() {
        guard transitionState == .prewarming else { return }
        guard let nextSong = getNextSong() else { return }
        
        transitionState = .crossfading
        hasUpdatedMetadataDuringFade = false
        
        fadeOutVolume = getTargetVolume(for: currentSong)
        fadeInVolume = getTargetVolume(for: nextSong)
        
        let standbyDeck = (activeDeck === deckA) ? deckB : deckA
        standbyDeck.play()
        
        let fadeDuration = appCrossfadeDuration
        
        if fadeDuration == 0.0 {
            // Instant cut with 10ms micro fade to avoid pop
            self.fadeStartTime = CACurrentMediaTime()
            self.fadeStartDuration = 0.01
        } else {
            self.fadeStartTime = CACurrentMediaTime()
            self.fadeStartDuration = fadeDuration
        }
        
        fadeDisplayLink?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(handleCrossfadeTick))
        link.add(to: .main, forMode: .common)
        fadeDisplayLink = link
    }
    
    @objc private func handleCrossfadeTick() {
        let elapsed = CACurrentMediaTime() - fadeStartTime
        let fadeDur = max(fadeStartDuration, 0.01)
        let progress = min(elapsed / fadeDur, 1.0)
        
        let standbyDeck = (activeDeck === deckA) ? deckB : deckA
        
        // Equal power curve scaled by target volumes
        activeDeck.volume = fadeOutVolume * Float(cos(progress * .pi / 2))
        standbyDeck.volume = fadeInVolume * Float(sin(progress * .pi / 2))
        
        if progress >= 0.5 && !hasUpdatedMetadataDuringFade {
            hasUpdatedMetadataDuringFade = true
            
            // Scrobble previous track
            let prevSong = queue[currentIndex]
            Task { try? await SubsonicClient.shared.scrobble(id: prevSong.id, server: self.server) }
            
            // Advance index
            let nextIndex = currentIndex + 1
            if nextIndex < queue.count {
                currentIndex = nextIndex
            } else if repeatMode == .all {
                currentIndex = 0
            }
            updateNowPlaying()
        }
        
        if progress >= 1.0 {
            completeCrossfade()
        }
    }
    
    private func completeCrossfade() {
        fadeDisplayLink?.invalidate()
        
        let oldActiveDeck = activeDeck
        activeDeck = (activeDeck === deckA) ? deckB : deckA
        
        activeDeck.volume = getTargetVolume(for: currentSong)
        
        // Full reset and stop transcoder
        oldActiveDeck.pause()
        setItem(nil, on: oldActiveDeck)

        transitionState = .idle
    }
    
    private func stopCrossfadeDisplayLink() {
        fadeDisplayLink?.invalidate()
        fadeDisplayLink = nil
    }

    // MARK: - Playback controls
    func play() { activeDeck.play(); updateNowPlaying() }
    func pause() { activeDeck.pause(); updateNowPlaying() }
    func togglePlayPause() { isPlaying ? pause() : play() }

    func skipNext() {
        guard transitionState != .crossfading else { return }
        
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            let prev = queue[currentIndex]
            Task { try? await SubsonicClient.shared.scrobble(id: prev.id, server: self.server) }
            currentIndex = nextIndex
            rebuildPlayerItems()
        } else if repeatMode == .all {
            load(songs: queue, startIndex: 0)
        }
    }

    func skipPrevious() {
        guard transitionState != .crossfading else { return }
        
        if currentTime > 3 {
            seek(to: 0)
        } else if currentIndex > 0 {
            currentIndex -= 1
            rebuildPlayerItems()
        } else if repeatMode == .all {
            load(songs: queue, startIndex: queue.count - 1)
        }
    }

    func seek(to seconds: Double) {
        guard transitionState != .crossfading else { return }
        
        // If we are prewarming, cancel the prewarm because the track might not end soon anymore
        if transitionState == .prewarming {
            let standbyDeck = (activeDeck === deckA) ? deckB : deckA
            standbyDeck.pause()
            setItem(nil, on: standbyDeck)
            transitionState = .idle
        }
        
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        activeDeck.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    func playFromQueue(index: Int) {
        currentIndex = index
        rebuildPlayerItems()
    }

    func addToQueue(_ song: Song) {
        queue.append(song)
    }

    func addToQueueNext(_ song: Song) {
        let insertIndex = min(currentIndex + 1, queue.count)
        queue.insert(song, at: insertIndex)
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
        // Don't rebuild if simply shuffling future items, but if we do re-order, prewarm state might be wrong.
        if transitionState == .prewarming {
            let standbyDeck = (activeDeck === deckA) ? deckB : deckA
            standbyDeck.pause()
            setItem(nil, on: standbyDeck)
            transitionState = .idle
        }
    }

    // MARK: - Repeat
    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: - Item finished
    @objc private func playerItemDidFinish(_ notification: Notification) {
        // If the item represents the activeDeck and finished prematurely or without triggering crossfade loop
        // It can also be repeat .one case
        guard let item = notification.object as? AVPlayerItem, item == activeDeck.currentItem else { return }
        
        Task { @MainActor in
            if self.repeatMode == .one {
                self.seek(to: 0)
                self.activeDeck.play()
                return
            }
            
            // If it finishes naturally without hitting prewarm logic (e.g., short track or stream issue)
            if self.transitionState != .crossfading {
                self.skipNext()
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
