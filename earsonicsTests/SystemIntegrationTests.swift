import AVFoundation
import MediaPlayer
import Testing
import UIKit
@testable import earsonics

@Suite("Audio session interruptions")
struct InterruptionParsingTests {

    private func info(_ type: AVAudioSession.InterruptionType, options: AVAudioSession.InterruptionOptions? = nil) -> [AnyHashable: Any] {
        var dict: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: type.rawValue]
        if let options { dict[AVAudioSessionInterruptionOptionKey] = options.rawValue }
        return dict
    }

    @Test func beganIsRecognised() {
        #expect(AudioPlayerService.interruptionEvent(fromLegacy: info(.began)) == .began)
    }

    @Test func endedCarriesTheResumeRecommendation() {
        #expect(AudioPlayerService.interruptionEvent(fromLegacy: info(.ended, options: .shouldResume))
                == .ended(shouldResume: true))
        #expect(AudioPlayerService.interruptionEvent(fromLegacy: info(.ended, options: []))
                == .ended(shouldResume: false))
        // No options key at all: don't resume.
        #expect(AudioPlayerService.interruptionEvent(fromLegacy: info(.ended)) == .ended(shouldResume: false))
    }

    @Test func malformedNotificationsAreIgnored() {
        #expect(AudioPlayerService.interruptionEvent(fromLegacy: nil) == nil)
        #expect(AudioPlayerService.interruptionEvent(fromLegacy: [:]) == nil)
        #expect(AudioPlayerService.interruptionEvent(fromLegacy: [AVAudioSessionInterruptionTypeKey: UInt(99)]) == nil)
    }
}

/// Uses the shared player with an empty queue, so nothing actually plays.
/// Serialized: the tests share the player's state.
@MainActor
@Suite("Interruption resume decisions", .serialized)
struct InterruptionDecisionTests {
    let player = AudioPlayerService.shared

    @Test func resumesOnlyIfMusicWasPlayingAndTheSystemAgrees() {
        player.clearQueue()
        player.play()                       // user wants music
        #expect(player.intendsToPlay)
        player.handleInterruption(.began)
        #expect(player.resumesAfterInterruption)
        player.handleInterruption(.ended(shouldResume: false))
        #expect(!player.resumesAfterInterruption)
        #expect(!player.intendsToPlay)      // stays paused, and the UI says so
    }

    @Test func doesNotResumeWhatTheUserHadPaused() {
        player.clearQueue()
        player.pause()
        player.handleInterruption(.began)
        #expect(!player.resumesAfterInterruption)
        player.handleInterruption(.ended(shouldResume: true))
        #expect(!player.resumesAfterInterruption)
        #expect(!player.intendsToPlay)
    }

    @Test func anEndWithoutABeginningDoesNothing() {
        player.clearQueue()
        player.handleInterruption(.ended(shouldResume: true))
        #expect(!player.resumesAfterInterruption)
        #expect(!player.intendsToPlay)
    }
}

@Suite("Now Playing artwork")
struct NowPlayingArtworkTests {
    /// The system calls the artwork handler on its own queue. If the handler
    /// inherited main-actor isolation, calling it off the main thread would
    /// trap, failing this test.
    @Test func artworkHandlerCanBeCalledOffTheMainThread() async {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let artwork = AudioPlayerService.makeArtwork(image)
        #expect(artwork.bounds.size == CGSize(width: 8, height: 8))
        let size = await Task.detached {
            #expect(!Thread.isMainThread)
            return artwork.image(at: CGSize(width: 4, height: 4))?.size
        }.value
        #expect(size != nil)
    }
}
