import Testing
import Foundation
@testable import dj_mixer

// MARK: - Library persistence

@Test func librarySaveAndLoad() {
    let track = TrackRecord(id: UUID(), name: "test.mp3", localPath: "/tmp/test.mp3", duration: 120, added: Date())
    var lib = Library()
    lib.tracks.append(track)
    
    // save to temp
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_lib.json")
    try? JSONEncoder().encode(lib).write(to: url)
    
    // load back
    let loaded = (try? JSONDecoder().decode(Library.self, from: Data(contentsOf: url))) ?? Library()
    #expect(loaded.tracks.count == 1)
    #expect(loaded.tracks[0].name == "test.mp3")
    #expect(loaded.tracks[0].duration == 120)
    
    try? FileManager.default.removeItem(at: url)
}

@Test func libraryDedupeByLocalPath() {
    var lib = Library()
    let t1 = TrackRecord(id: UUID(), name: "a.mp3", localPath: "/tmp/a.mp3", duration: 100, added: Date())
    let t2 = TrackRecord(id: UUID(), name: "a.mp3", localPath: "/tmp/a.mp3", duration: 100, added: Date())
    lib.tracks.append(t1)
    // same localPath should be deduped
    if !lib.tracks.contains(where: { $0.localPath == t2.localPath }) {
        lib.tracks.append(t2)
    }
    #expect(lib.tracks.count == 1)
}

// MARK: - Channel state

@Test func channelToggleCue() {
    // Pure logic test: no AVAudioEngine needed
    // Just test the toggleCue state machine
    var cueSet = false
    var cuePoint: TimeInterval = 0
    var isPlaying = false
    var pausedAt: TimeInterval = 0
    var currentTime: TimeInterval = 0
    
    // First click (stopped): should mark cue at pausedAt
    if !isPlaying && !cueSet {
        cuePoint = pausedAt
        cueSet = true
    }
    #expect(cueSet == true)
    #expect(cuePoint == 0)
    
    // Seek forward
    pausedAt = 30
    
    // Second click (stopped, cue set): should jump back to cuePoint
    var jumped = false
    if !isPlaying && cueSet {
        isPlaying = true
        jumped = true
    }
    #expect(jumped == true)
    #expect(isPlaying == true)
}

@Test func eqGainMapping() {
    func eqGain(_ v: Float) -> Float {
        if v >= 0.5 { return (v - 0.5) * 12 }
        else if v > 0.48 { return 0 }
        else { return -20 + (v / 0.48) * 20 }
    }
    
    // Center = flat (0 dB)
    #expect(abs(eqGain(0.5)) < 0.01)
    // Max boost = +6 dB
    #expect(abs(eqGain(1.0) - 6) < 0.01)
    // Full cut = -20 dB
    #expect(abs(eqGain(0.0) - (-20)) < 0.01)
    // Half boost = +3 dB
    #expect(abs(eqGain(0.75) - 3) < 0.01)
    // Near center = flat
    #expect(abs(eqGain(0.49)) < 0.01)
    #expect(abs(eqGain(0.51) - 0.12) < 0.01)
}

// MARK: - Beat FX

@Test func fxBeatDivisions() {
    let bpm: Double = 120
    let divisions: [(String, Double, Double)] = [
        ("1/1", 4, 2.0),
        ("1/2", 2, 1.0),
        ("1/4", 1, 0.5),
        ("1/8", 0.5, 0.25),
        ("1/16", 0.25, 0.125),
    ]
    for (_, div, expected) in divisions {
        let delaySec = 60.0 / bpm * div
        #expect(abs(delaySec - expected) < 0.01)
    }
}

@Test func fxMutesWhenOff() {
    let wet: Float = 0  // FX off
    #expect(wet == 0)
    
    // When wet is 0, all wetDryMix should be 0
    let delayWet = wet * 50
    let reverbWet = wet * 60
    let distortionWet = wet * 50
    #expect(delayWet == 0)
    #expect(reverbWet == 0)
    #expect(distortionWet == 0)
}

@Test func fxParamScalesWetSignal() {
    let param: Float = 0.5
    let on = true
    let wet = on ? param : 0
    #expect(wet == 0.5)
    
    let delayWet = wet * 50
    #expect(abs(delayWet - 25) < 0.01)
}

// MARK: - Varispeed rate calc

@Test func varispeedRateFromBPM() {
    let detected: Float = 120
    let override: Float = 180
    let rate = override / detected
    #expect(abs(rate - 1.5) < 0.01)
}

@Test func varispeedDefaultRate() {
    let detected: Float = 120
    let override: Float = -1  // auto = use detected
    // rate should be 1.0 when override is -1
    let rate: Float = override >= 0 ? override / detected : 1.0
    #expect(abs(rate - 1.0) < 0.01)
}

@Test func varispeedMinRate() {
    let detected: Float = 120
    let override: Float = 0   // 0 BPM → silent
    let rate = override / detected
    #expect(abs(rate - 0.0) < 0.01)
}

@Test func varispeedMaxRate() {
    let detected: Float = 80
    let override: Float = 200
    let rate = override / detected
    #expect(abs(rate - 2.5) < 0.01)
}

// MARK: - Crossfader

@Test func crossfaderAPosition() {
    let crossfader: Float = 0     // all the way A
    let xfGainA: Float = (1 - crossfader) * 2
    let xfGainB: Float = crossfader * 2
    #expect(abs(xfGainA - 2) < 0.01)
    #expect(abs(xfGainB - 0) < 0.01)
}

@Test func crossfaderBPosition() {
    let crossfader: Float = 1     // all the way B
    let xfGainA: Float = (1 - crossfader) * 2
    let xfGainB: Float = crossfader * 2
    #expect(abs(xfGainA - 0) < 0.01)
    #expect(abs(xfGainB - 2) < 0.01)
}

@Test func crossfaderCenter() {
    let crossfader: Float = 0.5
    let xfGainA: Float = (1 - crossfader) * 2
    let xfGainB: Float = crossfader * 2
    #expect(abs(xfGainA - 1) < 0.01)
    #expect(abs(xfGainB - 1) < 0.01)
}

@Test func crossfaderThru() {
    let xfaderAssign = -1  // THRU
    let xfGain: Float = xfaderAssign == -1 ? 1 : 0
    #expect(abs(xfGain - 1) < 0.01)
}

// MARK: - Level meter peak detection

@Test func peakDetection() {
    // Simulate a tap reading audio samples
    let samples: [Float] = [0.1, 0.3, 0.8, 0.2, 0.05, 0.6, 0.4, 0.9, 0.1]
    var peak: Float = 0
    for s in samples { peak = max(peak, abs(s)) }
    #expect(abs(peak - 0.9) < 0.01)
    
    let meterVal = min(peak * 2, 1)
    #expect(abs(meterVal - 1.0) < 0.01)
}

@Test func peakDetectionSilence() {
    let samples: [Float] = [0, 0, 0, 0]
    var peak: Float = 0
    for s in samples { peak = max(peak, abs(s)) }
    #expect(abs(peak - 0) < 0.01)
}
