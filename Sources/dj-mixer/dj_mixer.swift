import SwiftUI
import AVFoundation

// MARK: - App Entry
@main struct DJMixerApp: App {
    @State private var engine = AudioEngine()
    
    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    engine.start()
                    NSApplication.shared.setActivationPolicy(.regular)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let w = NSApplication.shared.windows.first {
                            w.makeKeyAndOrderFront(nil)
                            w.level = .floating
                        }
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
        }
    }
}

// MARK: - Audio Engine (4-channel)
@Observable class AudioEngine {
    let avEngine = AVAudioEngine()
    var channels: [Channel] = (0..<4).map { Channel(id: $0) }
    var crossfader: Float = 0.5
    var crossfaderCurve: Float = 0.5
    var masterVolume: Float = 0.85
    var boothVolume: Float = 0.5
    var masterMixer = AVAudioMixerNode()
    var fx: BeatFXProcessor?
    
    // Beat FX state
    var fxType: FXType = .delay
    var fxParam: Float = 0.5
    var fxBeat: FXBeat = .quarter
    var fxOn = false
    var fxChannels: [Bool] = [false, false, false, false]
    
    // Peak meters
    var channelPeaks: [Float] = [0, 0, 0, 0]
    var masterPeak: Float = 0
    
    init() {
        avEngine.attach(masterMixer)
        avEngine.connect(masterMixer, to: avEngine.outputNode, format: nil)
        for ch in channels { ch.attach(to: avEngine, master: masterMixer) }
        for ch in channels { ch.onUpdate = { [weak self] in self?.updateMix() } }
    }
    
    func start() {
        do { try avEngine.start() } catch { print("engine fail: \(error)") }
        startMeterTimer()
    }
    
    func updateMix() {
        for ch in channels { ch.applyMix(crossfader: crossfader, curve: crossfaderCurve) }
        masterMixer.volume = masterVolume
    }
    
    func startMeterTimer() {
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let s = self else { return }
            for (i, ch) in s.channels.enumerated() {
                s.channelPeaks[i] = ch.meter()
            }
            var avg: Float = 0
            for p in s.channelPeaks { avg = max(avg, p) }
            s.masterPeak = avg
        }
    }
}

enum FXType: String, CaseIterable { case delay, echo, reverb, flanger, phaser, filter, crush, space }
enum FXBeat: String, CaseIterable { case whole = "1/1", half = "1/2", quarter = "1/4", eighth = "1/8", sixteenth = "1/16" }

@Observable class BeatFXProcessor {
    let engine: AVAudioEngine
    let reverb = AVAudioUnitReverb()
    let delay = AVAudioUnitDelay()
    let distortion = AVAudioUnitDistortion()
    var currentType: FXType = .delay
    
    init(engine: AVAudioEngine) {
        self.engine = engine
        engine.attach(reverb)
        engine.attach(delay)
        engine.attach(distortion)
        reverb.loadFactoryPreset(.cathedral)
        delay.feedback = 30
        delay.lowPassCutoff = 15000
        delay.wetDryMix = 0
        distortion.loadFactoryPreset(.drumsLoFi)
        bypassAll()
    }
    
    var onUpdate: (() -> Void)?
    
    func bypassAll() {
        reverb.wetDryMix = 0
        delay.wetDryMix = 0
        distortion.wetDryMix = 0
    }
    
    func apply(type: FXType, param: Float, beat: FXBeat) {
        let beatMs: [FXBeat: Double] = [.whole: 2000, .half: 1000, .quarter: 500, .eighth: 250, .sixteenth: 125]
        currentType = type
        switch type {
        case .delay, .echo:
            delay.delayTime = beatMs[beat] ?? 500
            delay.feedback = Float(param) * 80
            delay.wetDryMix = Float(param) * 50
            reverb.wetDryMix = 0
            distortion.wetDryMix = 0
        case .reverb:
            reverb.wetDryMix = Float(param) * 60
            delay.wetDryMix = 0; distortion.wetDryMix = 0
        case .flanger:
            distortion.wetDryMix = 0; reverb.wetDryMix = 0; delay.wetDryMix = 0
            delay.delayTime = 3.0; delay.feedback = Float(param) * 40; delay.wetDryMix = Float(param) * 50
        case .phaser:
            distortion.wetDryMix = 0; reverb.wetDryMix = 0; delay.wetDryMix = 0
            distortion.loadFactoryPreset(.drumsLoFi)
            distortion.wetDryMix = Float(param) * 50
        case .filter:
            delay.lowPassCutoff = Float(param) * 20000 + 100
            delay.wetDryMix = 100; reverb.wetDryMix = 0; distortion.wetDryMix = 0
        case .crush:
            distortion.loadFactoryPreset(.drumsLoFi)
            distortion.wetDryMix = Float(param) * 60
            reverb.wetDryMix = 0; delay.wetDryMix = 0
        case .space:
            reverb.loadFactoryPreset(.largeHall)
            reverb.wetDryMix = Float(param) * 70
            delay.wetDryMix = 0; distortion.wetDryMix = 0
        }
    }
}

// MARK: - Channel (deck)
@Observable class Channel: Identifiable {
    let id: Int
    var player = AVAudioPlayerNode()
    var eq: AVAudioUnitEQ
    var trimMixer = AVAudioMixerNode()
    var channelMixer = AVAudioMixerNode()
    var cueMixer = AVAudioMixerNode()
    
    var trim: Float = 0.85 { didSet { onUpdate?() } }
    var hiKnob: Float = 0.5 { didSet { updateEQ(); onUpdate?() } }
    var midKnob: Float = 0.5 { didSet { updateEQ(); onUpdate?() } }
    var lowKnob: Float = 0.5 { didSet { updateEQ(); onUpdate?() } }
    var fader: Float = 1.0 { didSet { onUpdate?() } }
    var cueOn = false
    var fxSend: Float = 0
    var colorFXType: Int = 0
    var colorFXOn = false
    
    // crossfader assignment: -1 = off, 0 = A, 1 = B
    var xfaderAssign: Int = 0
    
    var isPlaying = false { didSet { isPlaying ? startPlay() : stopPlay() } }
    var currentFile: AVAudioFile? { didSet { 
        if currentFile == nil { scopeURL?.stopAccessingSecurityScopedResource(); scopeURL = nil }
        player.stop(); isPlaying = false; pausedAt = 0 
    } }
    var pausedAt: TimeInterval = 0
    var duration: TimeInterval = 0
    var currentTime: TimeInterval = 0
    var cuePoint: TimeInterval = 0
    var cueSet = false
    var waveform: [Float] = []
    var fileName: String = ""
    var onUpdate: (() -> Void)?
    private var amp: Float = 0
    private var scopeURL: URL?
    
    var displayName: String {
        fileName.isEmpty ? "CH \(id + 1)" : fileName
    }
    
    init(id: Int) {
        self.id = id
        eq = AVAudioUnitEQ(numberOfBands: 3)
        let cfgs: [(AVAudioUnitEQFilterType, Float, Float)] = [(.highShelf, 7000, 0.5), (.parametric, 1200, 0.7), (.lowShelf, 200, 0.5)]
        for (i, (t, f, b)) in cfgs.enumerated() {
            eq.bands[i].filterType = t; eq.bands[i].frequency = f
            eq.bands[i].bandwidth = b; eq.bands[i].gain = 0; eq.bands[i].bypass = false
        }
    }
    
    func attach(to engine: AVAudioEngine, master: AVAudioMixerNode) {
        engine.attach(player); engine.attach(eq); engine.attach(trimMixer); engine.attach(channelMixer); engine.attach(cueMixer)
        engine.connect(player, to: eq, format: nil)
        engine.connect(eq, to: trimMixer, format: nil)
        engine.connect(trimMixer, to: channelMixer, format: nil)
        engine.connect(channelMixer, to: master, format: nil)
        engine.connect(cueMixer, to: master, format: nil)
    }
    
    func applyMix(crossfader: Float, curve _: Float) {
        let c = fader  // 0-1 channel fader
        // crossfader apply
        var xfGain: Float = 1
        if xfaderAssign == -1 { xfGain = 1 }
        else if xfaderAssign == 0 { xfGain = (1 - crossfader) * 2 }
        else { xfGain = crossfader * 2 }
        channelMixer.volume = trim * c * xfGain
        cueMixer.volume = cueOn ? 0.8 : 0
    }
    
    func meter() -> Float {
        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return 0 }
        // Simple peak simulation based on amplitude
        amp = amp * 0.9 + (isPlaying ? 0.1 * Float.random(in: 0...0.3) : 0)
        return min(amp, 1)
    }
    
    func load(url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        scopeURL?.stopAccessingSecurityScopedResource()
        scopeURL = url
        do {
            let file = try AVAudioFile(forReading: url)
            currentFile = file; fileName = url.lastPathComponent
            duration = TimeInterval(file.length) / file.fileFormat.sampleRate
            computeWaveform(file: file); pausedAt = 0
        } catch { print("CH\(id) load: \(error)") }
    }
    
    func computeWaveform(file: AVAudioFile) {
        let total = file.length; let target = 400
        let chunk = min(Int64(65536), total)
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk)) else { return }
        waveform = []; var pos: Int64 = 0
        while pos < total {
            buf.frameLength = 0; file.framePosition = pos
            do { try file.read(into: buf) } catch { break }
            guard buf.frameLength > 0, let d = buf.floatChannelData?[0] else { break }
            let frames = Int(buf.frameLength)
            let here = max(1, target * frames / Int(total))
            for i in 0..<here {
                let s = i * frames / here; let e = (i + 1) * frames / here
                var peak: Float = 0
                for j in s..<min(e, frames) { peak = max(peak, abs(d[j])) }
                waveform.append(peak)
            }
            pos += Int64(buf.frameLength)
        }
        file.framePosition = 0
    }
    
    func startPlay() {
        guard let file = currentFile else { isPlaying = false; return }
        player.stop()
        let startFrame = AVAudioFramePosition(pausedAt * file.fileFormat.sampleRate)
        let framesToPlay = AVAudioFrameCount(file.length - startFrame)
        if startFrame > 0 {
            player.scheduleSegment(file, startingFrame: startFrame, frameCount: framesToPlay, at: nil)
        } else {
            player.scheduleFile(file, at: nil, completionHandler: nil)
        }
        player.play()
    }
    
    func stopPlay() {
        player.stop()
        if let f = currentFile, let t = player.lastRenderTime?.sampleTime {
            pausedAt = TimeInterval(t) / f.fileFormat.sampleRate
        } else { pausedAt = 0 }
    }
    
    func updateEQ() {
        // Pioneer DJM: +6dB boost to -∞ kill (value 0-1 maps to +6 to -∞)
        func eqGain(_ v: Float) -> Float {
            if v >= 0.5 { return (v - 0.5) * 12 }    // +0 to +6 dB
            else if v > 0.48 { return 0 }
            else { return -20 + (v / 0.48) * 20 }    // kill slope
        }
        eq.bands[2].gain = eqGain(lowKnob)
        eq.bands[1].gain = eqGain(midKnob)
        eq.bands[0].gain = eqGain(hiKnob)
    }
    
    func seek(to t: TimeInterval) {
        guard currentFile != nil else { return }
        pausedAt = max(0, min(t, duration))
        if isPlaying {
            player.stop()
            let f = currentFile!
            let sf = AVAudioFramePosition(pausedAt * f.fileFormat.sampleRate)
            let fp = AVAudioFrameCount(f.length - sf)
            if sf > 0 { player.scheduleSegment(f, startingFrame: sf, frameCount: fp, at: nil) }
            else { player.scheduleFile(f, at: nil, completionHandler: nil) }
            player.play()
        }
    }
    
    func toggleCue() {
        guard currentFile != nil else { return }
        if !isPlaying && cueSet { seek(to: cuePoint); isPlaying = true; cueSet = false }
        else { cuePoint = isPlaying ? currentTime : pausedAt; cueSet = true }
    }
}

// MARK: - Views
struct ContentView: View {
    @Bindable var engine: AudioEngine
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("DJM-TOUR1").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(white: 0.7))
                Spacer()
                Text("ALPHATHETA").font(.system(size: 10)).foregroundStyle(Color(white: 0.4))
            }
            .padding(.horizontal, 12).padding(.top, 6)
            
            HStack(spacing: 0) {
                ForEach(Array(engine.channels.enumerated()), id: \.element.id) { i, ch in
                    ChannelStripView(channel: ch, index: i, engine: engine)
                    if i < 3 { Divider().frame(width: 1).background(Color(white: 0.15)) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            
            Divider().background(Color(white: 0.15))
            BottomSection(engine: engine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.1))
        .preferredColorScheme(.dark)
    }
}

struct ChannelStripView: View {
    @Bindable var channel: Channel
    let index: Int
    @Bindable var engine: AudioEngine
    @State private var showFile = false
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 5) {
            // Label + Load
            HStack {
                Text("CH \(index+1)").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(white: 0.65))
                Spacer()
                Button("📁") { showFile = true }
                    .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
            }.padding(.horizontal, 6).padding(.top, 6)
            
            // Waveform
            WaveformMini(waveform: channel.waveform,
                progress: channel.duration > 0 ? channel.currentTime / channel.duration : 0,
                cueSet: channel.cueSet,
                cueProgress: channel.duration > 0 ? channel.cuePoint / channel.duration : 0,
                onTap: { p in channel.seek(to: p * channel.duration) })
                .frame(height: 36).cornerRadius(4).padding(.horizontal, 6)
            
            // Transport
            HStack(spacing: 6) {
                Button(channel.isPlaying ? "⏹" : "▶") { channel.isPlaying.toggle() }
                    .buttonStyle(.borderedProminent).tint(channel.isPlaying ? .green : .gray).font(.system(size: 11))
                Button("CUE") { channel.toggleCue() }
                    .buttonStyle(.bordered).tint(channel.cueSet ? .green : .gray).font(.system(size: 9))
                Spacer()
                Text(channel.fileName).font(.system(size: 8)).foregroundStyle(Color(white: 0.4)).lineLimit(1)
            }.padding(.horizontal, 6)
            
            // TRIM + EQ
            HStack(spacing: 8) {
                VStack(spacing: 2) {
                    Text("TRIM").font(.system(size: 7)).foregroundStyle(Color(white: 0.5))
                    DialKnob(value: $channel.trim, range: 0...1.5).frame(width: 32, height: 32)
                }
                Spacer()
                EQKnob(label: "HI", value: $channel.hiKnob)
                EQKnob(label: "MID", value: $channel.midKnob)
                EQKnob(label: "LOW", value: $channel.lowKnob)
                Spacer()
                VStack(spacing: 2) {
                    Text("CFX").font(.system(size: 7)).foregroundStyle(Color(white: 0.5))
                    DialKnob(value: $channel.fxSend, range: 0...1).frame(width: 24, height: 24)
                }
            }.padding(.horizontal, 6)
            
            // Level meter + Master fader
            HStack(spacing: 6) {
                LevelMeter(level: engine.channelPeaks[index]).frame(width: 6, height: 50)
                VStack(spacing: 2) {
                    Text("\(Int(channel.fader * 100))").font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color(white: 0.6))
                    Slider(value: $channel.fader, in: 0...1)
                        .tint(.blue)
                }
                VStack(spacing: 4) {
                    Button("C") { channel.cueOn.toggle() }
                        .buttonStyle(.bordered).tint(channel.cueOn ? .blue : .gray).font(.system(size: 8))
                    Picker("", selection: $channel.xfaderAssign) {
                        Text("THRU").tag(-1)
                        Text("A").tag(0)
                        Text("B").tag(1)
                    }.pickerStyle(.segmented).scaleEffect(0.85).frame(width: 70)
                }.frame(width: 40)
            }.padding(.horizontal, 6)
        }
        .frame(minWidth: 220, maxWidth: 260)
        .padding(.vertical, 6)
        .background(Color(white: index % 2 == 0 ? 0.12 : 0.1))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.18), lineWidth: 1))
        .fileImporter(isPresented: $showFile, allowedContentTypes: [.audio]) { r in
            if case .success(let u) = r { channel.load(url: u) }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if channel.isPlaying, let nt = channel.player.lastRenderTime,
                   let pt = channel.player.playerTime(forNodeTime: nt) {
                    channel.currentTime = Double(pt.sampleTime) / pt.sampleRate
                }
            }
        }
        .onDisappear { timer?.invalidate() }
    }
}

// MARK: - Sub-Views
struct DialKnob: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    
    var body: some View {
        ZStack {
            Circle().stroke(Color(white: 0.25), lineWidth: 3)
            Circle().trim(from: 0, to: CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)))
                .stroke(Color.blue, lineWidth: 3).rotationEffect(.degrees(-90))
            Circle().fill(Color(white: 0.18)).frame(width: 16, height: 16)
        }
        .gesture(DragGesture().onChanged { g in
            let delta = Float(g.translation.height) * -0.006
            value = max(range.lowerBound, min(range.upperBound, value + delta))
        })
    }
}

struct EQKnob: View {
    let label: String
    @Binding var value: Float
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 7, weight: .medium)).foregroundStyle(Color(white: 0.5))
            ZStack {
                Circle().stroke(value > 0.48 && value < 0.52 ? Color(white: 0.3) : Color.blue, lineWidth: 2.5)
                Circle().trim(from: 0, to: CGFloat(abs(value - 0.5) * 2))
                    .stroke(value > 0.5 ? Color.orange : Color.red, lineWidth: 2.5)
                    .rotationEffect(.degrees(value > 0.5 ? -90 : 90))
                Circle().fill(Color(white: 0.14)).frame(width: 14, height: 14)
            }.frame(width: 28, height: 28)
            .gesture(DragGesture().onChanged { g in
                let delta = Float(g.translation.height) * -0.005
                value = max(0, min(1, value + delta))
            })
        }
    }
}

struct LevelMeter: View {
    let level: Float
    
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            VStack(spacing: 1) {
                Rectangle().fill(level > 0.85 ? Color.red : Color(white: 0.2)).frame(height: h * 0.2)
                Rectangle().fill(level > 0.7 ? Color.orange : Color(white: 0.2)).frame(height: h * 0.3)
                Rectangle().fill(level > 0.4 ? Color.yellow : Color(white: 0.2)).frame(height: h * 0.2)
                Rectangle().fill(level > 0.1 ? Color.green : Color(white: 0.2)).frame(height: h * 0.3)
            }
        }
    }
}

struct WaveformMini: View {
    let waveform: [Float]; let progress: Double
    let cueSet: Bool; let cueProgress: Double; let onTap: (Double) -> Void
    
    var body: some View {
        GeometryReader { geo in
            if waveform.isEmpty {
                Text("Load a track").font(.system(size: 8)).foregroundStyle(Color(white: 0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .topLeading) {
                    Color(white: 0.08)
                    Canvas { ctx, size in
                        let bw = size.width / CGFloat(waveform.count)
                        for (i, p) in waveform.enumerated() {
                            let bh = CGFloat(p) * size.height * 0.8
                            let r = CGRect(x: CGFloat(i) * bw, y: (size.height - bh) / 2, width: max(bw - 0.5, 1), height: max(bh, 1))
                            ctx.fill(Path(roundedRect: r, cornerSize: CGSize(width: 0.5, height: 0.5)), with: .color(Color.orange.opacity(0.7)))
                        }
                    }
                    if cueSet { Rectangle().fill(.green).frame(width: 2).offset(x: geo.size.width * cueProgress) }
                    Rectangle().fill(.white).frame(width: 1.5).offset(x: geo.size.width * progress)
                }
                .contentShape(Rectangle())
                .onTapGesture { loc in let w = geo.size.width; if w > 0 { onTap(loc.x / w) } }
            }
        }
    }
}

struct BottomSection: View {
    @Bindable var engine: AudioEngine
    
    var body: some View {
        HStack(spacing: 0) {
            CrossfaderView(engine: engine).frame(maxWidth: .infinity)
            Divider().background(Color(white: 0.15))
            MasterSection(engine: engine).frame(width: 180)
        }
        .frame(height: 60).padding(4)
        .background(Color(white: 0.08))
    }
}

struct BeatFXView: View {
    @Bindable var engine: AudioEngine
    
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("BEAT FX").font(.system(size: 9, weight: .bold)).foregroundStyle(.blue)
                    Button(engine.fxOn ? "ON" : "OFF") { engine.fxOn.toggle(); engine.updateMix() }
                        .buttonStyle(.bordered).tint(engine.fxOn ? .green : .gray).font(.system(size: 8))
                }
                HStack(spacing: 6) {
                    VStack(spacing: 1) {
                        Text("TYPE").font(.system(size: 7)).foregroundStyle(.secondary)
                        Picker("", selection: $engine.fxType) {
                            ForEach(FXType.allCases, id: \.self) { t in Text(t.rawValue.uppercased()).font(.system(size: 9)).tag(t) }
                        }.pickerStyle(.menu).frame(width: 70)
                    }
                    VStack(spacing: 1) {
                        Text("PARAM").font(.system(size: 7)).foregroundStyle(.secondary)
                        DialKnob(value: $engine.fxParam, range: 0...1).frame(width: 26, height: 26)
                            .onChange(of: engine.fxParam) { _, _ in engine.updateMix() }
                    }
                    VStack(spacing: 1) {
                        Text("BEAT").font(.system(size: 7)).foregroundStyle(.secondary)
                        Picker("", selection: $engine.fxBeat) {
                            ForEach(FXBeat.allCases, id: \.self) { b in Text(b.rawValue).font(.system(size: 9)).tag(b) }
                        }.pickerStyle(.menu).frame(width: 60)
                    }
                }
            }
            VStack(spacing: 4) {
                ForEach(0..<4) { i in
                    Button("CH\(i+1)") { engine.fxChannels[i].toggle() }
                        .buttonStyle(.bordered).tint(engine.fxChannels[i] ? .blue : .gray).font(.system(size: 8))
                }
            }
        }.padding(6)
    }
}

struct CrossfaderView: View {
    @Bindable var engine: AudioEngine
    
    var body: some View {
        HStack(spacing: 12) {
            Text("A").font(.system(size: 10, weight: .bold)).foregroundStyle(engine.crossfader < 0.3 ? .orange : .secondary)
            Slider(value: $engine.crossfader, in: 0...1)
                .onChange(of: engine.crossfader) { _, _ in engine.updateMix() }
            Text("B").font(.system(size: 10, weight: .bold)).foregroundStyle(engine.crossfader > 0.7 ? .orange : .secondary)
            Text("CURVE").font(.system(size: 8)).foregroundStyle(.secondary)
            Slider(value: $engine.crossfaderCurve, in: 0...1).frame(width: 60)
                .onChange(of: engine.crossfaderCurve) { _, _ in engine.updateMix() }
        }.padding(.horizontal, 12)
    }
}

struct MasterSection: View {
    @Bindable var engine: AudioEngine
    
    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 4) {
                Text("MASTER").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(white: 0.6))
                LevelMeter(level: engine.masterPeak).frame(width: 6, height: 30)
            }
            VStack(spacing: 4) {
                DialKnob(value: $engine.masterVolume, range: 0...1).frame(width: 24, height: 24)
                    .onChange(of: engine.masterVolume) { _, _ in engine.updateMix() }
                Text("VOL").font(.system(size: 7)).foregroundStyle(.secondary)
            }
            VStack(spacing: 4) {
                DialKnob(value: $engine.boothVolume, range: 0...1).frame(width: 24, height: 24)
                    .onChange(of: engine.boothVolume) { _, _ in engine.updateMix() }
                Text("BOOTH").font(.system(size: 7)).foregroundStyle(.secondary)
            }
            Button("●") {}.buttonStyle(.borderless).font(.system(size: 10)).foregroundStyle(.red)
        }.padding(6)
    }
}
