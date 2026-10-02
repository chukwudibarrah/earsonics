// Services/AudioPlayerService.swift
import AVFoundation
import MediaPlayer
import Combine
import SwiftUI
import os

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

    private static let log = Logger(subsystem: "com.wonderworks.earsonics", category: "player")

    private var deckA: AVPlayer
    private var deckB: AVPlayer
    private var activeDeck: AVPlayer

    /// The deck that isn't playing the current track — where the next track is
    /// prewarmed and faded in from.
    private var standbyDeck: AVPlayer { activeDeck === deckA ? deckB : deckA }

    // Observers and Timers
    private var timeObserverA: Any?
    private var timeObserverB: Any?
    private var fadeDisplayLink: CADisplayLink?
    private var notificationTokens: [NSObjectProtocol] = []

    /// One status observer per deck, replaced whenever that deck's item changes,
    /// so observers never outlive (or retain) the items they watch.
    private var itemStatusObservers: [ObjectIdentifier: AnyCancellable] = [:]

    // Transition State
    private var transitionState: PlaybackTransitionState = .idle
    private var fadeStartTime: CFTimeInterval = 0
    private var fadeStartDuration: Double = 0
    private var hasUpdatedMetadataDuringFade = false

    /// Id of the song loaded on the standby deck while prewarming. A queue edit
    /// that changes which song comes next invalidates the prewarm.
    private var prewarmedSongID: String?

    // Telemetry for startup latency
    private var lastStreamRequestTime: CFTimeInterval = 0
    private var recentStartupLatencies: [Double] = []

    /// Tracks in a row that failed to play. Auto-skipping stops at
    /// `maxConsecutiveFailures` so an unreachable server can't race through
    /// the whole queue.
    private var consecutiveFailures = 0
    private static let maxConsecutiveFailures = 3

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

    /// User-facing message when a track couldn't be played; cleared when the
    /// next track starts.
    @Published var playbackError: String?

    var server: Server? {
        didSet {
            // Queue entries are song ids from the previous server's library —
            // meaningless (or a different song) on another server. Edits to the
            // same server (name, credentials) leave playback alone; new player
            // items pick up the updated details automatically.
            guard oldValue?.id != server?.id else { return }
            clearQueue()
        }
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
    // Delivered on the main queue, so handlers run on the main actor.
    private func setupItemNotifications() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            MainActor.assumeIsolated { self?.handleItemDidFinish(item) }
        })
        notificationTokens.append(center.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main
        ) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            MainActor.assumeIsolated {
                guard let self, item === self.activeDeck.currentItem else { return }
                self.handleActiveItemFailure(error)
            }
        })
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
        // An empty list would leave nothing to play (and crash the shuffle
        // path below), so keep whatever is currently playing instead.
        guard !songs.isEmpty else { return }
        let start = min(max(startIndex, 0), songs.count - 1)
        consecutiveFailures = 0

        originalQueue = songs
        if isShuffled {
            var shuffled = songs
            let first = shuffled.remove(at: start)
            shuffled.shuffle()
            shuffled.insert(first, at: 0)
            queue = shuffled
            currentIndex = 0
        } else {
            queue = songs
            currentIndex = start
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

        if let cached = AudioCache.cachedFileURL(for: song.id, serverID: srv.id, quality: quality) {
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
            realURL: streamURL, songId: song.id, serverID: srv.id, quality: quality,
            contentType: song.contentType, suffix: song.suffix,
            size: song.size.map(Int64.init))
        let asset = AVURLAsset(url: customURL)
        asset.resourceLoader.setDelegate(delegate, queue: delegate.loaderQueue)
        let item = AVPlayerItem(asset: asset)
        loaderDelegates[ObjectIdentifier(item)] = delegate
        return item
    }

    /// Replaces the current item on a deck, tearing down the outgoing item's
    /// resource-loader delegate (if any) so its download is cancelled, and
    /// moving the deck's status observer onto the new item.
    private func setItem(_ item: AVPlayerItem?, on deck: AVPlayer) {
        if let old = deck.currentItem,
           let delegate = loaderDelegates.removeValue(forKey: ObjectIdentifier(old)) {
            delegate.invalidate()
        }
        itemStatusObservers[ObjectIdentifier(deck)] = item.map { observeStatus(of: $0, on: deck) }
        deck.replaceCurrentItem(with: item)
    }

    /// Watches an item's load status: records prewarm latency, and routes a
    /// failure on the active deck to `handleActiveItemFailure`. A failure on the
    /// standby deck is picked up when it becomes active (see `completeCrossfade`).
    private func observeStatus(of item: AVPlayerItem, on deck: AVPlayer) -> AnyCancellable {
        item.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak item] status in
                guard let self, let item, deck.currentItem === item else { return }
                switch status {
                case .readyToPlay:
                    if deck === self.activeDeck {
                        self.consecutiveFailures = 0
                    } else if self.transitionState == .prewarming {
                        let latency = CACurrentMediaTime() - self.lastStreamRequestTime
                        self.recentStartupLatencies.append(latency)
                        if self.recentStartupLatencies.count > 5 { self.recentStartupLatencies.removeFirst() }
                    }
                case .failed:
                    if deck === self.activeDeck { self.handleActiveItemFailure(item.error) }
                default:
                    break
                }
            }
    }

    // MARK: - Rebuild: sets up current track on active deck
    func rebuildPlayerItems() {
        guard let srv = server else { return }

        resetTransition()

        // Stop both decks
        deckA.pause()
        setItem(nil, on: deckA)
        deckB.pause()
        setItem(nil, on: deckB)

        activeDeck = deckA
        activeDeck.volume = getTargetVolume(for: currentSong)
        playbackError = nil

        guard currentIndex >= 0, currentIndex < queue.count else { return }
        let currentSong = queue[currentIndex]

        guard let item = makePlayerItem(for: currentSong, server: srv) else { return }

        setItem(item, on: activeDeck)
        activeDeck.play()
        updateNowPlaying()
    }

    /// Stops playback and empties the queue.
    func clearQueue() {
        resetTransition()
        deckA.pause()
        setItem(nil, on: deckA)
        deckB.pause()
        setItem(nil, on: deckB)
        activeDeck = deckA

        queue = []
        originalQueue = []
        currentIndex = 0
        currentTime = 0
        duration = 0
        // Set directly: the paused deck's status update may arrive after
        // `activeDeck` has switched, and would then be ignored.
        isPlaying = false
        isBuffering = false
        playbackError = nil
        consecutiveFailures = 0
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
        // Repeat One loops the track with a seek when it ends (see
        // `handleItemDidFinish`); there's no different next track to prepare.
        guard repeatMode != .one else { return }

        let fadeDuration = appCrossfadeDuration
        let prewarmBudget = getAdaptivePrewarmBudget()

        let remainingTime = duration - currentTime

        // 1. Check for Prewarming (start T-(fade+budget) )
        if transitionState == .idle && remainingTime <= (fadeDuration + prewarmBudget) {
            startPrewarming()
        }

        // 2. Check for Crossfading (start T-fade). With a 0s crossfade this
        // rarely fires — the switch happens on the end-of-item notification.
        if transitionState == .prewarming && remainingTime <= fadeDuration {
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
        prewarmedSongID = nextSong.id

        let standbyDeck = self.standbyDeck
        standbyDeck.volume = 0.0

        // Startup latency is recorded by the status observer (`observeStatus`).
        lastStreamRequestTime = CACurrentMediaTime()

        setItem(item, on: standbyDeck)
        // Ensure standby deck starts loading
        standbyDeck.play()
        standbyDeck.pause() // Play/pause forces buffer to start
    }

    /// Discards the prewarmed next track, if any.
    private func cancelPrewarm() {
        guard transitionState == .prewarming else { return }
        let standbyDeck = self.standbyDeck
        standbyDeck.pause()
        setItem(nil, on: standbyDeck)
        transitionState = .idle
        prewarmedSongID = nil
    }

    /// After a queue edit, drops the prewarmed track if it's no longer the one
    /// that plays next. The next time tick prewarms the correct one.
    private func revalidatePrewarm() {
        if transitionState == .prewarming, getNextSong()?.id != prewarmedSongID {
            cancelPrewarm()
        }
    }

    /// Brings any in-progress transition to a stable state before an edit that
    /// reorders or removes queue entries: a prewarm is discarded, and a running
    /// crossfade is completed instantly.
    private func settleTransition() {
        switch transitionState {
        case .idle:
            break
        case .prewarming:
            cancelPrewarm()
        case .crossfading:
            if !hasUpdatedMetadataDuringFade { advanceForCrossfade() }
            completeCrossfade()
        }
    }

    private func resetTransition() {
        transitionState = .idle
        stopCrossfadeDisplayLink()
        hasUpdatedMetadataDuringFade = false
        prewarmedSongID = nil
    }

    private func startCrossfade() {
        guard transitionState == .prewarming else { return }
        guard let nextSong = getNextSong() else { return }

        transitionState = .crossfading
        hasUpdatedMetadataDuringFade = false

        fadeOutVolume = getTargetVolume(for: currentSong)
        fadeInVolume = getTargetVolume(for: nextSong)

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

        // Equal power curve scaled by target volumes
        activeDeck.volume = fadeOutVolume * Float(cos(progress * .pi / 2))
        standbyDeck.volume = fadeInVolume * Float(sin(progress * .pi / 2))

        if progress >= 0.5 && !hasUpdatedMetadataDuringFade {
            advanceForCrossfade()
        }

        if progress >= 1.0 {
            completeCrossfade()
        }
    }

    /// Moves the queue position onto the incoming track. Runs once per
    /// crossfade, at its midpoint.
    private func advanceForCrossfade() {
        hasUpdatedMetadataDuringFade = true

        // Scrobble previous track
        if let prevSong = currentSong {
            Task { try? await SubsonicClient.shared.scrobble(id: prevSong.id, server: self.server) }
        }

        // Advance index
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            currentIndex = nextIndex
        } else if repeatMode == .all {
            currentIndex = 0
        }
        playbackError = nil
        updateNowPlaying()
    }

    private func completeCrossfade() {
        stopCrossfadeDisplayLink()

        let oldActiveDeck = activeDeck
        activeDeck = standbyDeck

        activeDeck.volume = getTargetVolume(for: currentSong)

        // Full reset and stop transcoder
        oldActiveDeck.pause()
        setItem(nil, on: oldActiveDeck)

        transitionState = .idle
        prewarmedSongID = nil

        // Status updates from the new deck were ignored while it was on
        // standby, so sync them now.
        isPlaying = activeDeck.timeControlStatus == .playing
        isBuffering = activeDeck.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if let item = activeDeck.currentItem, item.status == .failed {
            handleActiveItemFailure(item.error)
        }
    }

    private func stopCrossfadeDisplayLink() {
        fadeDisplayLink?.invalidate()
        fadeDisplayLink = nil
    }

    // MARK: - Playback controls
    func play() {
        // A track that failed to load can't simply resume — retry it.
        if currentSong != nil,
           activeDeck.currentItem == nil || activeDeck.currentItem?.status == .failed {
            rebuildPlayerItems()
            return
        }
        activeDeck.play()
        updateNowPlaying()
    }
    func pause() { activeDeck.pause(); updateNowPlaying() }
    func togglePlayPause() { isPlaying ? pause() : play() }

    func skipNext() {
        guard transitionState != .crossfading, !queue.isEmpty else { return }

        let nextIndex = currentIndex + 1
        if nextIndex < queue.count || repeatMode == .all {
            let prev = queue[currentIndex]
            Task { try? await SubsonicClient.shared.scrobble(id: prev.id, server: self.server) }
            currentIndex = nextIndex < queue.count ? nextIndex : 0
            rebuildPlayerItems()
        }
    }

    func skipPrevious() {
        guard transitionState != .crossfading, !queue.isEmpty else { return }

        if currentTime > 3 {
            seek(to: 0)
        } else if currentIndex > 0 {
            currentIndex -= 1
            rebuildPlayerItems()
        } else if repeatMode == .all {
            currentIndex = queue.count - 1
            rebuildPlayerItems()
        }
    }

    func seek(to seconds: Double) {
        guard transitionState != .crossfading else { return }

        // If we are prewarming, cancel the prewarm because the track might not end soon anymore
        cancelPrewarm()

        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        activeDeck.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    func playFromQueue(index: Int) {
        guard queue.indices.contains(index) else { return }
        consecutiveFailures = 0
        currentIndex = index
        rebuildPlayerItems()
    }

    func addToQueue(_ song: Song) {
        queue.append(song)
        if isShuffled { originalQueue.append(song) }
        revalidatePrewarm()
    }

    func addToQueueNext(_ song: Song) {
        // Mid-crossfade (before the midpoint) the incoming track is already
        // committed as "next", so the new song goes after it. If that incoming
        // track is a Repeat All wrap to the start, finish the fade first so
        // "next" is unambiguous.
        if transitionState == .crossfading && !hasUpdatedMetadataDuringFade
            && currentIndex + 1 >= queue.count {
            settleTransition()
        }
        let incomingPending = transitionState == .crossfading && !hasUpdatedMetadataDuringFade

        if isShuffled {
            let anchor = (incomingPending ? getNextSong() : currentSong)
                .flatMap { s in originalQueue.firstIndex { $0.id == s.id } }
            originalQueue.insert(song, at: anchor.map { $0 + 1 } ?? originalQueue.count)
        }
        let insertIndex = min(currentIndex + (incomingPending ? 2 : 1), queue.count)
        queue.insert(song, at: insertIndex)
        revalidatePrewarm()
    }

    func removeFromQueue(at offsets: IndexSet) {
        let valid = offsets.filteredIndexSet { $0 < queue.count }
        guard !valid.isEmpty else { return }
        if transitionState == .crossfading { settleTransition() }

        let removesCurrent = valid.contains(currentIndex)
        let removedBefore = valid.count(in: 0..<currentIndex)
        if isShuffled {
            for index in valid {
                let id = queue[index].id
                if let i = originalQueue.firstIndex(where: { $0.id == id }) { originalQueue.remove(at: i) }
            }
        }
        queue.remove(atOffsets: valid)

        if queue.isEmpty {
            clearQueue()
        } else if removesCurrent {
            // Play whichever track slid into the removed one's place.
            currentIndex = min(currentIndex - removedBefore, queue.count - 1)
            rebuildPlayerItems()
        } else {
            currentIndex -= removedBefore
            revalidatePrewarm()
        }
    }

    func moveQueueItem(from source: IndexSet, to destination: Int) {
        if transitionState == .crossfading { settleTransition() }
        // Apply the same move to the positions so the current track keeps
        // playing uninterrupted at its new index.
        var positions = Array(queue.indices)
        positions.move(fromOffsets: source, toOffset: destination)
        queue.move(fromOffsets: source, toOffset: destination)
        if let newIndex = positions.firstIndex(of: currentIndex) { currentIndex = newIndex }
        revalidatePrewarm()
    }

    // MARK: - Shuffle
    func toggleShuffle() {
        if transitionState == .crossfading { settleTransition() }
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
        revalidatePrewarm()
    }

    // MARK: - Repeat
    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        // Repeat One never transitions to another track; otherwise the mode
        // can change what comes after the last track.
        if repeatMode == .one { cancelPrewarm() } else { revalidatePrewarm() }
    }

    // MARK: - Item finished / failed
    private func handleItemDidFinish(_ item: AVPlayerItem) {
        guard item === activeDeck.currentItem else { return }

        if repeatMode == .one {
            seek(to: 0)
            activeDeck.play()
            return
        }

        switch transitionState {
        case .prewarming:
            // The next track is already buffered on the standby deck — always
            // the case with a 0s crossfade, whose fade point is the very end —
            // so switch to it rather than rebuilding (which would discard it
            // and leave a gap).
            startCrossfade()
            if transitionState != .crossfading {
                cancelPrewarm()
                skipNext()
            }
        case .crossfading:
            break
        case .idle:
            // e.g. a track too short to reach the prewarm window
            skipNext()
        }
    }

    /// The current track failed to load or stopped mid-stream. Skips ahead
    /// (without scrobbling) unless several tracks in a row have failed, in
    /// which case playback stops with a message.
    private func handleActiveItemFailure(_ error: Error?) {
        let title = currentSong?.title ?? "track"
        // Only the localized description: the full error can embed the stream
        // URL, which carries the auth token and salt.
        Self.log.error("Playback failed: \(error?.localizedDescription ?? "unknown error", privacy: .public)")
        consecutiveFailures += 1

        let hasNext = currentIndex + 1 < queue.count || (repeatMode == .all && queue.count > 1)
        if consecutiveFailures < Self.maxConsecutiveFailures, hasNext {
            currentIndex = currentIndex + 1 < queue.count ? currentIndex + 1 : 0
            rebuildPlayerItems()
            playbackError = "Skipped “\(title)” because it couldn’t be played."
        } else {
            cancelPrewarm()
            activeDeck.pause()
            isPlaying = false
            isBuffering = false
            playbackError = "Couldn’t play “\(title)”. Check your connection to the server."
            updateNowPlaying()
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
        if let track = song.track { info[MPMediaItemPropertyAlbumTrackNumber] = track }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
