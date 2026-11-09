// Services/AudioPlayerService.swift
import AVFoundation
import MediaPlayer
import Combine
import SwiftUI
import os

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

    /// Queue entry loaded on the standby deck while prewarming. A queue edit
    /// that changes which entry comes next invalidates the prewarm.
    private var prewarmedEntryID: UUID?

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

    /// Play order, position, shuffle and repeat. All queue rules live in
    /// `PlayQueue`; this class turns its changes into player actions.
    @Published private(set) var playQueue = PlayQueue() {
        didSet { scheduleQueueSave() }
    }
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isBuffering: Bool = false

    var queue: [Song] { playQueue.songs }
    var currentIndex: Int { playQueue.currentIndex }
    var isShuffled: Bool { playQueue.isShuffled }
    var repeatMode: RepeatMode { playQueue.repeatMode }

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
            // Keep the old server's queue (and position) for when it's
            // switched back to — unless it was deleted — then empty the queue
            // without saving the empty queue over the new server's.
            if let old = oldValue, ServerStore.shared.servers.contains(where: { $0.id == old.id }) {
                saveQueue(to: old)
            }
            suppressQueueSaves = true
            clearQueue()
            suppressQueueSaves = false
        }
    }

    var currentSong: Song? { playQueue.currentSong }

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
        Task { await AudioCache.shared.removeUnplayableFiles() }
        setupPlayer(deck: deckA, isDeckA: true)
        setupPlayer(deck: deckB, isDeckA: false)
        setupItemNotifications()
        setupAudioSessionObservers()
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
                let wasPlaying = self.isPlaying
                self.isPlaying = (status == .playing)
                self.isBuffering = (status == .waitingToPlayAtSpecifiedRate)
                // Publish the new rate: `play()`/`pause()` update Now Playing
                // before the deck actually changes state, so on its own the
                // system would keep showing the old one (e.g. "paused").
                if wasPlaying != self.isPlaying { self.updateNowPlaying() }
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

    // MARK: - Audio session interruptions and route changes
    /// What an audio-session notification means for playback.
    enum InterruptionEvent: Equatable {
        case began
        case ended(shouldResume: Bool)
    }

    /// True between an interruption starting while music was playing and the
    /// system saying whether to resume.
    private(set) var resumesAfterInterruption = false

    /// Whether the user wants music playing — set by play/pause and track
    /// loads, and unaffected by the system pausing the player during an
    /// interruption (which `isPlaying` would reflect).
    private(set) var intendsToPlay = false

    private func setupAudioSessionObservers() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        if #available(tvOS 27.0, *) {
            // tvOS 27 models interruptions as deactivation + a resumption
            // recommendation, which can't get stuck if an "ended" signal never
            // arrives. Both are posted on the main queue.
            notificationTokens.append(center.addObserver(
                forName: AVAudioSession.didBecomeInactiveNotification, object: session, queue: .main
            ) { [weak self] note in
                guard let context = note.userInfo?[AVAudioSession.deactivationContextKey]
                        as? AVAudioSession.DeactivationContext,
                      context.source == .system else { return }
                MainActor.assumeIsolated { self?.handleInterruption(.began) }
            })
            notificationTokens.append(center.addObserver(
                forName: AVAudioSession.resumptionRecommendationNotification, object: session, queue: .main
            ) { [weak self] note in
                guard let context = note.userInfo?[AVAudioSession.resumptionContextKey]
                        as? AVAudioSession.ResumptionContext else { return }
                let shouldResume = context.recommendation == .shouldResume
                MainActor.assumeIsolated { self?.handleInterruption(.ended(shouldResume: shouldResume)) }
            })
        } else {
            notificationTokens.append(center.addObserver(
                forName: AVAudioSession.interruptionNotification, object: session, queue: .main
            ) { [weak self] note in
                guard let event = Self.interruptionEvent(fromLegacy: note.userInfo) else { return }
                MainActor.assumeIsolated { self?.handleInterruption(event) }
            })
        }

        // An output that disappears (Bluetooth headphones, an AirPlay speaker)
        // pauses rather than switching to the TV speakers mid-song.
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.pause() }
        })
    }

    /// Reads the pre-tvOS 27 interruption notification. Returns nil for
    /// anything it doesn't recognise.
    nonisolated static func interruptionEvent(fromLegacy userInfo: [AnyHashable: Any]?) -> InterruptionEvent? {
        guard let raw = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
        switch type {
        case .began:
            return .began
        case .ended:
            let options = AVAudioSession.InterruptionOptions(
                rawValue: userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            return .ended(shouldResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }

    /// AVPlayer pauses itself when an interruption begins; this decides
    /// whether to resume when it ends: only if music was playing beforehand
    /// and the system recommends it.
    func handleInterruption(_ event: InterruptionEvent) {
        switch event {
        case .began:
            resumesAfterInterruption = intendsToPlay
            // Both decks were paused mid-fade; finish the fade so a single
            // deck is left to resume.
            if transitionState == .crossfading { settleTransition() }
        case .ended(let shouldResume):
            let resume = resumesAfterInterruption && shouldResume
            resumesAfterInterruption = false
            guard resume else {
                intendsToPlay = false
                updateNowPlaying()
                return
            }
            // Reactivate the session (which can block) off the main thread,
            // then resume.
            Task.detached(priority: .userInitiated) { [weak self] in
                try? AVAudioSession.sharedInstance().setActive(true)
                await self?.play()
            }
        }
    }

    // MARK: - Remote Command Center
    private func setupRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        cc.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        // The Siri Remote's play/pause button (and other remotes, headphones)
        // send this toggle rather than separate play and pause commands.
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success }
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
    /// Replaces the queue and starts playing. `shuffle: nil` keeps the current
    /// shuffle setting. An empty list is ignored, so whatever is playing keeps
    /// playing.
    func load(songs: [Song], startIndex: Int = 0, shuffle: Bool? = nil, context: PlayContext = .mix) {
        guard playQueue.load(songs, startIndex: startIndex, shuffle: shuffle, context: context) else { return }
        cancelAutoplay()
        consecutiveFailures = 0
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

        let ext = AudioCache.fileExtension(quality: quality, songSuffix: song.suffix, contentType: song.contentType)
        if let cached = AudioCache.cachedFileURL(for: song.id, serverID: srv.id, quality: quality, fileExtension: ext) {
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
                        self.applyPendingSeek(for: item)
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
        // Until the new item's first time tick, show the new track's start
        // rather than the previous track's position.
        currentTime = 0
        duration = currentSong?.duration.map(Double.init) ?? 0

        // A restored queue resumes where it left off, but only for the slot
        // it was saved on; any other track starts from the top.
        let startPosition = pendingStart.flatMap { $0.entryID == playQueue.current?.id ? $0.position : nil } ?? 0
        pendingStart = nil
        pendingSeek = nil

        guard let currentSong = playQueue.currentSong,
              let item = makePlayerItem(for: currentSong, server: srv) else { return }

        setItem(item, on: activeDeck)
        intendsToPlay = true
        if startPosition > 0 {
            // Seek once the item is ready, then play (see `applyPendingSeek`),
            // so nothing is heard from the start of the track first.
            pendingSeek = (ObjectIdentifier(item), startPosition)
            currentTime = startPosition
        } else {
            activeDeck.play()
        }
        beginListening()
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

        playQueue.clear()
        cancelAutoplay()
        playedSongIDs = []
        scrobbleTracker = nil
        pendingStart = nil
        pendingSeek = nil
        currentTime = 0
        duration = 0
        // Set directly: the paused deck's status update may arrive after
        // `activeDeck` has switched, and would then be ignored.
        isPlaying = false
        isBuffering = false
        intendsToPlay = false
        playbackError = nil
        consecutiveFailures = 0
        updateNowPlaying()
    }

    // MARK: - Time Tick and Transitions
    private func handleTimeTick(for deck: AVPlayer, time: Double) {
        recordListening(on: deck, time: time)

        // Only drive UI and transition logic from the active deck
        guard deck === activeDeck else { return }

        // Keep the saved position reasonably fresh while playing, so another
        // app picking up the queue starts close to where this one was.
        if isPlaying, CACurrentMediaTime() - lastPositionSave > Self.positionSaveInterval {
            lastPositionSave = CACurrentMediaTime()
            scheduleQueueSave(after: .zero)
        }

        self.currentTime = time
        if let dur = deck.currentItem?.duration, dur.isNumeric, dur.seconds > 0 {
            self.duration = dur.seconds

            checkTransitionPhase(currentTime: time, duration: dur.seconds)
            // Fetch the next batch well before the last song ends, so the
            // usual prewarm/crossfade carries straight on into it.
            if dur.seconds - time <= appCrossfadeDuration + Self.autoplayLeadTime { requestAutoplayIfNeeded() }
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

    private func startPrewarming() {
        guard transitionState == .idle else { return }
        guard let next = playQueue.next, let srv = server else { return }
        guard let item = makePlayerItem(for: next.song, server: srv) else { return }

        transitionState = .prewarming
        prewarmedEntryID = next.id

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
        prewarmedEntryID = nil
    }

    /// After a queue edit, drops the prewarmed track if it's no longer the one
    /// that plays next. The next time tick prewarms the correct one.
    private func revalidatePrewarm() {
        if transitionState == .prewarming, playQueue.next?.id != prewarmedEntryID {
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
        prewarmedEntryID = nil
    }

    private func startCrossfade() {
        guard transitionState == .prewarming else { return }
        guard let nextSong = playQueue.next?.song else { return }

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

        playQueue.moveToNext()
        playbackError = nil
        beginListening()
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
        prewarmedEntryID = nil

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
        intendsToPlay = true
        // Still waiting to jump to a restored position: playing now would
        // start from the top. `applyPendingSeek` plays once it's there.
        guard pendingSeek == nil else { return }
        activeDeck.play()
        updateNowPlaying()
    }
    func pause() {
        intendsToPlay = false
        activeDeck.pause()
        updateNowPlaying()
        scheduleQueueSave(after: .milliseconds(300))
    }
    /// Goes by intent, not just `isPlaying`: while a track is buffering the
    /// player isn't "playing" yet, and a press should still pause it.
    func togglePlayPause() { (intendsToPlay || isPlaying) ? pause() : play() }

    func skipNext() {
        guard !playQueue.isEmpty else { return }
        // Mid-crossfade, act on what the screen shows. Before the midpoint
        // that's still the outgoing track, so "next" is the one fading in:
        // finish the fade now. After it, the incoming track is already
        // current, so finish the fade and skip past it. (Presses used to be
        // ignored for the whole fade — up to 12 s.)
        if transitionState == .crossfading {
            let incomingAlreadyCurrent = hasUpdatedMetadataDuringFade
            settleTransition()
            guard incomingAlreadyCurrent else { return }
        }

        // No scrobble here: a play is recorded once enough of it has been
        // heard (see `recordListening`), not because it was skipped.
        if playQueue.moveToNext() {
            rebuildPlayerItems()
        } else if continuation != .stop {
            // Skipping past the last song moves on into autoplay.
            waitingForAutoplay = true
            requestAutoplayIfNeeded()
        }
    }

    func skipPrevious() {
        guard !playQueue.isEmpty else { return }
        if transitionState == .crossfading { settleTransition() }

        // The deck's own position: `currentTime` can still hold the outgoing
        // track's time just after a crossfade.
        if currentPosition > 3 {
            seek(to: 0)
        } else if playQueue.moveToPrevious() {
            rebuildPlayerItems()
        }
    }

    func seek(to seconds: Double) {
        guard transitionState != .crossfading else { return }
        // Before a restored track is ready, just change where it will start.
        if pendingSeek != nil {
            pendingSeek?.position = max(seconds, 0)
            currentTime = max(seconds, 0)
            updateNowPlaying()
            return
        }

        // If we are prewarming, cancel the prewarm because the track might not end soon anymore
        cancelPrewarm()

        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        activeDeck.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
        scheduleQueueSave()
    }

    func playFromQueue(index: Int) {
        guard playQueue.jump(to: index) else { return }
        consecutiveFailures = 0
        rebuildPlayerItems()
    }

    func addToQueue(_ song: Song) {
        addToQueue([song])
    }

    func addToQueue(_ songs: [Song]) {
        playQueue.append(songs)
        revalidatePrewarm()
    }

    func addToQueueNext(_ song: Song) {
        addToQueueNext([song])
    }

    func addToQueueNext(_ songs: [Song]) {
        // Mid-crossfade (before the midpoint) the incoming track is already
        // committed as "next", so the new song goes after it. If that incoming
        // track is a Repeat All wrap to the start, finish the fade first so
        // "next" is unambiguous.
        if transitionState == .crossfading && !hasUpdatedMetadataDuringFade
            && currentIndex + 1 >= playQueue.count {
            settleTransition()
        }
        let incomingPending = transitionState == .crossfading && !hasUpdatedMetadataDuringFade
        playQueue.insertNext(songs, skippingIncoming: incomingPending)
        revalidatePrewarm()
    }

    func removeFromQueue(at offsets: IndexSet) {
        if transitionState == .crossfading { settleTransition() }
        switch playQueue.remove(at: offsets) {
        case .emptied:
            clearQueue()
        case .removedCurrent:
            // Play whichever track slid into the removed one's place.
            rebuildPlayerItems()
        case .keptCurrent:
            revalidatePrewarm()
        }
    }

    func moveQueueItem(from source: IndexSet, to destination: Int) {
        if transitionState == .crossfading { settleTransition() }
        playQueue.move(fromOffsets: source, toOffset: destination)
        revalidatePrewarm()
    }

    // MARK: - Shuffle
    func toggleShuffle() {
        if transitionState == .crossfading { settleTransition() }
        playQueue.toggleShuffle()
        revalidatePrewarm()
    }

    // MARK: - Repeat
    func cycleRepeat() {
        playQueue.cycleRepeat()
        // Repeat One never transitions to another track; otherwise the mode
        // can change what comes after the last track.
        if repeatMode == .one { cancelPrewarm() } else { revalidatePrewarm() }
    }

    // MARK: - Saving and restoring the queue
    /// While set, queue changes aren't saved (restoring, or emptying the
    /// queue during a server switch).
    private var suppressQueueSaves = false
    private var queueSaveTask: Task<Void, Never>?
    private var lastPositionSave: CFTimeInterval = 0
    private static let positionSaveInterval: CFTimeInterval = 60
    /// Where a restored queue left off: used the first time that slot is played.
    private var pendingStart: (entryID: UUID, position: Double)?
    /// A seek to apply once the given item is ready, before it starts playing.
    private var pendingSeek: (item: ObjectIdentifier, position: Double)?

    /// Seconds into the current song, from the deck when a track is loaded.
    var currentPosition: Double {
        let deckTime = activeDeck.currentItem != nil ? activeDeck.currentTime().seconds : .nan
        return deckTime.isFinite && pendingSeek == nil ? deckTime : currentTime
    }

    /// Saves after a short pause, so a burst of edits makes one save.
    func scheduleQueueSave(after delay: Duration = .seconds(3)) {
        guard !suppressQueueSaves, let srv = server else { return }
        queueSaveTask?.cancel()
        queueSaveTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled, let self, self.server?.id == srv.id else { return }
            self.saveQueue(to: srv)
        }
    }

    /// Saves straight away — e.g. when the app goes to the background.
    func saveQueueNow() {
        guard let srv = server else { return }
        queueSaveTask?.cancel()
        saveQueue(to: srv)
    }

    /// Writes the local copy, then (if enabled) the server copy. An empty
    /// queue clears the server's, so other apps don't resume something the
    /// user cleared here.
    private func saveQueue(to srv: Server) {
        let position = currentPosition
        LocalQueueStore.save(QueueSnapshot(queue: playQueue, position: position, savedAt: Date()),
                             serverID: srv.id)
        guard PlaybackPreferences.syncQueueWithServer else { return }
        let ids = playQueue.songs.map(\.id)
        let index = playQueue.currentIndex
        Task {
            do {
                try await SubsonicClient.shared.savePlayQueue(songIDs: ids, currentIndex: index,
                                                              position: position, server: srv)
            } catch {
                Self.log.error("Couldn't save the play queue to the server: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Restores the active server's saved queue, if the user wants that and
    /// hasn't started something else meanwhile.
    func restoreSavedQueue() async {
        guard let srv = server, playQueue.isEmpty else { return }
        let behaviour = PlaybackPreferences.launchBehaviour
        guard behaviour != .startFresh else { return }

        let local = LocalQueueStore.load(serverID: srv.id)
        var remote: SubsonicClient.RemotePlayQueue?
        if PlaybackPreferences.syncQueueWithServer {
            do {
                remote = try await SubsonicClient.shared.getPlayQueue(server: srv)
            } catch {
                Self.log.error("Couldn't load the play queue from the server: \(error.localizedDescription, privacy: .public)")
            }
        }
        // The server may have been switched, or playback started, meanwhile.
        guard server?.id == srv.id, playQueue.isEmpty,
              let snapshot = QueueRestore.choose(local: local, remote: remote) else { return }
        restore(snapshot, startPlaying: behaviour == .resumePlaying)
    }

    /// Loads a saved queue without starting a stream; the first play picks
    /// up at the saved position (see `rebuildPlayerItems`).
    func restore(_ snapshot: QueueSnapshot, startPlaying: Bool) {
        suppressQueueSaves = true
        playQueue = snapshot.queue
        suppressQueueSaves = false
        guard let entry = playQueue.current else { return }

        let length = entry.song.duration.map(Double.init) ?? 0
        // A position at (or past) the very end would just finish the track.
        let position = length > 0 && snapshot.position >= length - 2 ? 0 : max(snapshot.position, 0)
        pendingStart = (entry.id, position)
        currentTime = position
        duration = length
        intendsToPlay = false
        playbackError = nil
        updateNowPlaying()
        if startPlaying { play() }
    }

    /// Applies a restored position once the item can seek, then starts it.
    private func applyPendingSeek(for item: AVPlayerItem) {
        let itemID = ObjectIdentifier(item)
        guard let pending = pendingSeek, pending.item == itemID else { return }
        let time = CMTime(seconds: pending.position, preferredTimescale: 600)
        activeDeck.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.pendingSeek?.item == itemID,
                      self.activeDeck.currentItem.map(ObjectIdentifier.init) == itemID else { return }
                self.pendingSeek = nil
                if self.intendsToPlay { self.activeDeck.play() }
                self.updateNowPlaying()
            }
        }
    }

    // MARK: - Autoplay
    /// Songs played this session, so autoplay doesn't bring them back.
    private var playedSongIDs: Set<String> = []
    private var autoplayTask: Task<Void, Never>?
    /// The slot autoplay last fetched for, so each ending fetches once.
    private var autoplayFetchedFor: UUID?
    /// The last song ended (or was skipped) before the batch arrived.
    private var waitingForAutoplay = false
    /// How long before the end of the last song the next batch is fetched.
    private static let autoplayLeadTime: Double = 30

    /// What the user wants after this kind of queue; never with Repeat on
    /// (repeat already decides what comes next).
    private var continuation: QueueContinuation {
        guard repeatMode == .off else { return .stop }
        return PlaybackPreferences.continuation(for: playQueue.context.group)
    }

    private func requestAutoplayIfNeeded() {
        guard playQueue.isAtEnd, continuation != .stop, autoplayTask == nil,
              let entry = playQueue.current, autoplayFetchedFor != entry.id, let srv = server else { return }
        autoplayFetchedFor = entry.id
        let choice = continuation
        let seed = Autoplay.Seed(entry.song)
        let played = playedSongIDs.union(playQueue.songs.map(\.id))
        autoplayTask = Task { [weak self] in
            let batch = await Autoplay(source: .server(srv)).nextBatch(for: choice, seed: seed, excluding: played)
            guard let self, !Task.isCancelled, self.server?.id == srv.id else { return }
            self.autoplayTask = nil
            self.autoplayArrived(batch)
        }
    }

    private func autoplayArrived(_ batch: [Song]) {
        let wasWaiting = waitingForAutoplay
        waitingForAutoplay = false
        guard !batch.isEmpty else {
            // Nothing to continue with: stop as if autoplay were off.
            if wasWaiting {
                intendsToPlay = false
                updateNowPlaying()
            }
            return
        }
        playQueue.appendAutoplay(batch)
        if wasWaiting {
            playQueue.moveToNext()
            rebuildPlayerItems()
        } else {
            revalidatePrewarm()
        }
    }

    private func cancelAutoplay() {
        autoplayTask?.cancel()
        autoplayTask = nil
        autoplayFetchedFor = nil
        waitingForAutoplay = false
    }

    // MARK: - Scrobbling
    /// Tracks the current play towards the "played" threshold.
    private var scrobbleTracker: ScrobbleTracker?

    /// A new play of the current slot started: tell the server it's playing
    /// now, and start counting listening time.
    private func beginListening() {
        guard let entry = playQueue.current else {
            scrobbleTracker = nil
            return
        }
        playedSongIDs.insert(entry.song.id)
        scrobbleTracker = ScrobbleTracker(entryID: entry.id, songID: entry.song.id,
                                          duration: entry.song.duration.map(Double.init))
        let srv = server
        Task { try? await SubsonicClient.shared.scrobble(id: entry.song.id, submission: false, server: srv) }
    }

    /// The deck playing the current slot: the active one, except in the
    /// second half of a crossfade, when the queue has already moved on to the
    /// incoming track on the standby deck.
    private var listeningDeck: AVPlayer {
        transitionState == .crossfading && hasUpdatedMetadataDuringFade ? standbyDeck : activeDeck
    }

    private func recordListening(on deck: AVPlayer, time: Double) {
        guard deck === listeningDeck, var tracker = scrobbleTracker else { return }
        if let itemDuration = deck.currentItem?.duration, itemDuration.isNumeric {
            tracker.updateDuration(itemDuration.seconds)
        }
        let crossedThreshold = tracker.record(position: time)
        scrobbleTracker = tracker
        guard crossedThreshold else { return }
        let srv = server
        Task {
            try? await SubsonicClient.shared.scrobble(id: tracker.songID, submission: true,
                                                      time: tracker.startedAt, server: srv)
        }
    }

    // MARK: - Item finished / failed
    private func handleItemDidFinish(_ item: AVPlayerItem) {
        guard item === activeDeck.currentItem else { return }

        if repeatMode == .one {
            seek(to: 0)
            activeDeck.play()
            beginListening()   // each loop is a play of its own
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
                advanceAfterTrackEnded()
            }
        case .crossfading:
            break
        case .idle:
            // e.g. a track too short to reach the prewarm window
            advanceAfterTrackEnded()
        }
    }

    /// A track played to its end without a prepared transition.
    private func advanceAfterTrackEnded() {
        if playQueue.nextIndex != nil {
            skipNext()
        } else {
            reachedEndOfQueue()
        }
    }

    /// The last track finished and nothing follows: playback is over, so a
    /// play/pause press should start again rather than "pause".
    private func reachedEndOfQueue() {
        if continuation != .stop {
            // The batch is normally here already; if not (a short track, a
            // slow server), start it as soon as it arrives.
            waitingForAutoplay = true
            requestAutoplayIfNeeded()
            return
        }
        intendsToPlay = false
        updateNowPlaying()
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

        if consecutiveFailures < Self.maxConsecutiveFailures, playQueue.hasDifferentNext {
            playQueue.moveToNext()
            rebuildPlayerItems()
            playbackError = "Skipped “\(title)” because it couldn’t be played."
        } else {
            cancelPrewarm()
            activeDeck.pause()
            isPlaying = false
            isBuffering = false
            intendsToPlay = false
            playbackError = "Couldn’t play “\(title)”. Check your connection to the server."
            updateNowPlaying()
        }
    }

    // MARK: - Now Playing Info
    /// Artwork for the system's Now Playing display, keyed by cover-art id so
    /// it's loaded once per album rather than once per update.
    private var nowPlayingArtwork: (coverArt: String, artwork: MPMediaItemArtwork)?
    private var artworkLoadingID: String?
    private var artworkTask: Task<Void, Never>?
    /// Same size Now Playing's own cover uses, so both share one cached image.
    private static let nowPlayingArtworkSize = 600

    func updateNowPlaying() {
        guard let song = currentSong else {
            artworkTask?.cancel()
            artworkLoadingID = nil
            nowPlayingArtwork = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        // The deck's clock where possible (`currentTime` lags by up to a
        // tick); a restored queue waiting for play only has `currentTime`.
        let elapsed = currentPosition
        let total = duration > 0 ? duration : song.duration.map(Double.init) ?? 0

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist ?? "",
            MPMediaItemPropertyAlbumTitle: song.album ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyPlaybackDuration: total
        ]
        if let track = song.track { info[MPMediaItemPropertyAlbumTrackNumber] = track }
        if let art = nowPlayingArtwork, art.coverArt == song.coverArt {
            info[MPMediaItemPropertyArtwork] = art.artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadNowPlayingArtworkIfNeeded(for: song)
    }

    /// Fetches the current song's cover (usually already cached by the
    /// on-screen artwork), then republishes Now Playing with it.
    private func loadNowPlayingArtworkIfNeeded(for song: Song) {
        guard let coverArt = song.coverArt else {
            nowPlayingArtwork = nil
            return
        }
        guard nowPlayingArtwork?.coverArt != coverArt, artworkLoadingID != coverArt,
              let srv = server,
              let url = SubsonicClient.shared.coverArtURL(id: coverArt, size: Self.nowPlayingArtworkSize, server: srv)
        else { return }

        artworkTask?.cancel()
        artworkLoadingID = coverArt
        artworkTask = Task { [weak self] in
            let image = await ImageCache.shared.image(for: coverArt, size: Self.nowPlayingArtworkSize,
                                                      serverID: srv.id, url: url)
            guard let self, !Task.isCancelled else { return }
            self.artworkLoadingID = nil
            guard let image, self.currentSong?.coverArt == coverArt else { return }
            self.nowPlayingArtwork = (coverArt, Self.makeArtwork(image))
            self.updateNowPlaying()
        }
    }

    /// Built outside the main actor on purpose: the system calls the request
    /// handler on its own queue, and a handler inheriting main-actor isolation
    /// would trap there.
    nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
