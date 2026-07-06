import Foundation
import Testing
@testable import PalmierPro

@Suite("Beat detection")
struct BeatDetectorTests {

    private func pulseEnvelope(period: Double, duration: Double, hop: Double = 0.01) -> AudioEnvelope {
        let count = Int(duration / hop)
        var samples = [Float](repeating: 0.05, count: count)
        let periodHops = Int(period / hop)
        var i = periodHops
        while i < count {
            samples[i] = 1.0
            if i + 1 < count { samples[i + 1] = 0.6 }
            i += periodHops
        }
        return AudioEnvelope(hopSeconds: hop, samples: samples)
    }

    @Test func detectsTempoOfRegularPulseTrain() {
        let analysis = BeatDetector.detect(envelope: pulseEnvelope(period: 0.5, duration: 30))
        #expect(abs(analysis.bpm - 120) < 3)
        #expect(!analysis.beats.isEmpty)

        let gaps = zip(analysis.beats.dropFirst(), analysis.beats).map(-)
        for gap in gaps {
            #expect(abs(gap - 0.5) < 0.11)
        }
    }

    @Test func detectsSlowTempo() {
        let analysis = BeatDetector.detect(envelope: pulseEnvelope(period: 0.8, duration: 40))
        #expect(abs(analysis.bpm - 75) < 3)
    }

    @Test func silenceYieldsNoBeats() {
        let envelope = AudioEnvelope(hopSeconds: 0.01, samples: [Float](repeating: 0, count: 3000))
        let analysis = BeatDetector.detect(envelope: envelope)
        #expect(analysis.beats.isEmpty)
        #expect(analysis.bpm == 0)
    }

    @Test func tooShortAudioYieldsNoBeats() {
        let analysis = BeatDetector.detect(envelope: pulseEnvelope(period: 0.5, duration: 1))
        #expect(analysis.beats.isEmpty)
    }

    @Test func beatsMapThroughTrimAndSpeed() {
        let clip = Clip(mediaRef: "m", mediaType: .audio, startFrame: 100, durationFrames: 150, trimStartFrame: 60, speed: 2.0)
        #expect(clip.timelineFrame(sourceSeconds: 3.0, fps: 30) == 115)
        #expect(clip.timelineFrame(sourceSeconds: 1.0, fps: 30) == nil)
    }
}
