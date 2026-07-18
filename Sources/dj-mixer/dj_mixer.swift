import SwiftUI
import AVFoundation

// MARK: - App Entry
@main struct DJMixerApp: App {
    @State private var engine = AudioEngine()
    
    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine)
                .frame(minWidth: 1200, minHeight: 700)
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
    var fx: BeatFXProcessor
    
    // Beat FX state
    var fxType: FXType = .delay { didSet { updateMix() } }
    var fxParam: Float = 0.5 { didSet { updateMix() } }
    var fxBeat: FXBeat = .quarter
    var fxOn = false { didSet { updateMix() } }
    var fxChannels: [Bool] = [false, false, false, false]
    
    // Peak meters
    var channelPeaks: [Float] = [0, 0, 0, 0]
    var masterPeak: Float = 0
    var masterBPM: Double = 120
    var bpmOverride: Float = 0  // 0 = use detected BPM
    
    // Library
    var library = LibraryManager.default.load()
    
    init() {
        fx = BeatFXProcessor(engine: avEngine)
        avEngine.attach(masterMixer)
        avEngine.connect(masterMixer, to: fx.inputMixer, format: nil)
        avEngine.connect(fx.outputMixer, to: avEngine.outputNode, format: nil)
        for ch in channels { ch.attach(to: avEngine, master: masterMixer) }
        for ch in channels { ch.onUpdate = { [weak self] in self?.updateMix() } }
        for ch in channels {
            ch.onLoad = { [weak self] rec in
                guard let s = self else { return }
                var newLib = s.library
                if !newLib.tracks.contains(where: { $0.localPath == rec.localPath }) {
                    newLib.tracks.insert(rec, at: 0)
                }
                s.library = newLib
                LibraryManager.default.save(newLib)
            }
        }
    }
    
    func saveLibrary() {
        LibraryManager.default.save(library)
    }
    
    func start() {
        do { try avEngine.start() } catch { print("engine fail: \(error)") }
        startMeterTimer()
    }
    
    func updateMix() {
        for ch in channels { ch.applyMix(crossfader: crossfader, curve: crossfaderCurve) }
        masterMixer.volume = masterVolume
        // Average BPM from loaded channels
        let loaded = channels.filter { $0.currentFile != nil }
        masterBPM = loaded.isEmpty ? 120 : Double(loaded.reduce(0) { $0 + $1.bpm }) / Double(loaded.count)
        fx.on = fxOn
        let activeBPM = bpmOverride > 0 ? Double(bpmOverride) : masterBPM
        fx.apply(type: fxType, param: fxParam, beat: fxBeat, bpm: activeBPM)
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
    let inputMixer = AVAudioMixerNode()
    let outputMixer = AVAudioMixerNode()
    let delay = AVAudioUnitDelay()
    let reverb = AVAudioUnitReverb()
    let distortion = AVAudioUnitDistortion()
    var on: Bool = false
    
    init(engine: AVAudioEngine) {
        self.engine = engine
        engine.attach(inputMixer); engine.attach(outputMixer)
        engine.attach(delay); engine.attach(reverb); engine.attach(distortion)
        // Inline series: input → delay → reverb → distortion → output
        engine.connect(inputMixer, to: delay, format: nil)
        engine.connect(delay, to: reverb, format: nil)
        engine.connect(reverb, to: distortion, format: nil)
        engine.connect(distortion, to: outputMixer, format: nil)
        delay.wetDryMix = 0; delay.lowPassCutoff = 15000
        reverb.wetDryMix = 0; reverb.loadFactoryPreset(.cathedral)
        distortion.wetDryMix = 0; distortion.loadFactoryPreset(.drumsLoFi)
    }
    
    func apply(type: FXType, param: Float, beat: FXBeat, bpm: Double) {
        let beatDiv: Double = [.whole: 4, .half: 2, .quarter: 1, .eighth: 0.5, .sixteenth: 0.25][beat] ?? 1
        // Delay time in seconds from BPM
        let delaySec = bpm > 0 ? 60.0 / bpm * beatDiv : 1.0
        let wet = on ? param : 0
        delay.wetDryMix = 0; reverb.wetDryMix = 0; distortion.wetDryMix = 0
        switch type {
        case .delay, .echo:
            delay.delayTime = delaySec
            delay.feedback = Float(param) * 80
            delay.wetDryMix = Float(wet) * 50
        case .reverb: reverb.wetDryMix = Float(wet) * 60
        case .flanger:
            delay.delayTime = 0.003; delay.feedback = Float(param) * 60
            delay.wetDryMix = Float(wet) * 50
        case .phaser: distortion.loadFactoryPreset(.drumsLoFi); distortion.wetDryMix = Float(wet) * 50
        case .filter: delay.lowPassCutoff = Float(param) * 20000 + 100; delay.wetDryMix = Float(wet) * 100
        case .crush: distortion.loadFactoryPreset(.drumsLoFi); distortion.wetDryMix = Float(wet) * 60
        case .space: reverb.loadFactoryPreset(.largeHall); reverb.wetDryMix = Float(wet) * 70
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
        player.stop(); isPlaying = false; pausedAt = 0 
    } }
    var pausedAt: TimeInterval = 0
    var duration: TimeInterval = 0
    var bpm: Double = 120
    var currentTime: TimeInterval = 0
    var cuePoint: TimeInterval = 0
    var cueSet = false
    var waveform: [Float] = []
    var fileName: String = ""
    var onUpdate: (() -> Void)?
    var onLoad: ((TrackRecord) -> Void)?
    
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
        xfaderAssign = -1  // THRU by default, assign via per-channel switch
    }
    
    func attach(to engine: AVAudioEngine, master: AVAudioMixerNode) {
        engine.attach(player); engine.attach(eq); engine.attach(trimMixer); engine.attach(channelMixer); engine.attach(cueMixer)
        engine.connect(player, to: eq, format: nil)
        engine.connect(eq, to: trimMixer, format: nil)
        engine.connect(trimMixer, to: channelMixer, format: nil)
        engine.connect(channelMixer, to: master, format: nil)
        engine.connect(cueMixer, to: master, format: nil)
        // Level metering via tap on the channel mixer
        channelMixer.installTap(onBus: 0, bufferSize: 256, format: nil) { [weak self] buf, _ in
            guard let s = self, let d = buf.floatChannelData?[0] else { return }
            var pk: Float = 0
            for i in 0..<Int(buf.frameLength) { pk = max(pk, abs(d[i])) }
            s.meterVal = min(pk * 2, 1)
        }
    }
    
    private var meterVal: Float = 0
    
    func meter() -> Float { meterVal }
    
    func applyMix(crossfader: Float, curve _: Float) {
        let c = fader
        var xfGain: Float = 1
        if xfaderAssign == -1 { xfGain = 1 }
        else if xfaderAssign == 0 { xfGain = (1 - crossfader) * 2 }
        else { xfGain = crossfader * 2 }
        channelMixer.volume = trim * c * xfGain
        cueMixer.volume = cueOn ? 0.8 : 0
    }
    func load(url: URL) {
        let startScoped = url.startAccessingSecurityScopedResource()
        defer { if startScoped { url.stopAccessingSecurityScopedResource() } }
        var loadURL = url
        if let rec = LibraryManager.default.ingest(url: url) {
            loadURL = URL(fileURLWithPath: rec.localPath)
            onLoad?(rec)
        }
        do {
            let file = try AVAudioFile(forReading: loadURL)
            currentFile = file; fileName = loadURL.lastPathComponent
            duration = TimeInterval(file.length) / file.fileFormat.sampleRate
            pausedAt = 0
            // Compute waveform + BPM in a single file pass
            computeAll(file: file, loadURL: loadURL)
        } catch { print("CH\(id) load: \(error)") }
    }
    
    func loadFromLibrary(track: TrackRecord) {
        guard let url = track.url else { return }
        do {
            let file = try AVAudioFile(forReading: url)
            currentFile = file; fileName = track.name
            duration = track.duration; pausedAt = 0
            computeAll(file: file, loadURL: url)
        } catch { print("CH\(id) lib: \(error)") }
    }
    
    func computeAll(file: AVAudioFile, loadURL: URL) {
        let sr = file.fileFormat.sampleRate
        let total = file.length
        let targetWF = 400
        let hop = Int64(sr / 100)  // 100 Hz for BPM envelope
        let chunk = min(Int64(65536), total)
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunk)) else { return }
        
        waveform = []
        bpm = 120
        var envelope = [Float]()
        var pos: Int64 = 0
        
        while pos < total {
            buf.frameLength = 0; file.framePosition = pos
            do { try file.read(into: buf) } catch { break }
            guard buf.frameLength > 0, let d = buf.floatChannelData?[0] else { break }
            let frames = Int(buf.frameLength)
            
            // Waveform peaks
            let here = max(1, targetWF * frames / Int(total))
            for i in 0..<here {
                let s = i * frames / here; let e = (i + 1) * frames / here
                var peak: Float = 0
                for j in s..<min(e, frames) { peak = max(peak, abs(d[j])) }
                waveform.append(peak)
            }
            
            // BPM envelope (every 10ms = 100Hz)
            if total > hop * 200 {  // need at least 2s of audio
                let subChunks = frames / Int(hop)
                for i in 0..<subChunks {
                    let s = i * Int(hop); let e = min(s + Int(hop), frames)
                    var eSum: Float = 0
                    for j in s..<e { eSum += abs(d[j]) }
                    envelope.append(eSum / Float(e - s))
                }
            }
            
            pos += Int64(buf.frameLength)
        }
        file.framePosition = 0
        
        // Autocorrelation for BPM
        guard envelope.count > 200 else { return }
        let minLag = 10  // 100Hz / 180BPM = ~33 samples → safe lower bound
        let maxLag = min(envelope.count / 2, 100)  // 100Hz / 60BPM = 100 samples
        var bestLag = minLag; var bestCorr: Float = 0
        for lag in minLag...maxLag {
            var corr: Float = 0
            for i in 0..<(envelope.count - lag) { corr += envelope[i] * envelope[i + lag] }
            if corr > bestCorr { bestCorr = corr; bestLag = lag }
        }
        if bestCorr > 0 {
            var detected = 60.0 / (Double(bestLag) / 100.0)
            // Check if double tempo (sub-harmonic correction)
            let halfLag = bestLag / 2
            if halfLag >= minLag {
                var halfCorr: Float = 0
                for i in 0..<(envelope.count - halfLag) { halfCorr += envelope[i] * envelope[i + halfLag] }
                if halfCorr > bestCorr * 0.8 { detected *= 2 }
            }
            // Clamp to reasonable range
            bpm = max(60, min(200, detected))
        }
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
    @State private var showLibrary = false
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("DJM-TOUR1").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(white: 0.7))
                Spacer()
                Button("LIBRARY (\(engine.library.tracks.count))") { showLibrary.toggle() }
                    .buttonStyle(.bordered).tint(.gray).font(.system(size: 9)).controlSize(.small)
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
        .sheet(isPresented: $showLibrary) {
            LibraryView(engine: engine)
        }
    }
}

struct ChannelStripView: View {
    @Bindable var channel: Channel
    let index: Int
    @Bindable var engine: AudioEngine
    @State private var showFile = false
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 6) {
            // Channel header
            HStack {
                Text("CH \(index+1)").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(white: 0.7))
                Spacer()
                Button("Load") { showFile = true }
                    .buttonStyle(.bordered).tint(.gray).font(.system(size: 10)).controlSize(.small)
            }.padding(.horizontal, 10).padding(.top, 6)
            
            // Waveform
            WaveformMini(waveform: channel.waveform,
                progress: channel.duration > 0 ? channel.currentTime / channel.duration : 0,
                cueSet: channel.cueSet,
                cueProgress: channel.duration > 0 ? channel.cuePoint / channel.duration : 0,
                onTap: { p in channel.seek(to: p * channel.duration) })
                .frame(height: 44)
                .cornerRadius(5)
                .padding(.horizontal, 10)
            
            // Transport
            HStack(spacing: 6) {
                Button(channel.isPlaying ? "⏹" : "▶") { channel.isPlaying.toggle() }
                    .buttonStyle(.borderedProminent).tint(channel.isPlaying ? .green : .gray).font(.system(size: 12)).controlSize(.small)
                Button("CUE") { channel.toggleCue() }
                    .buttonStyle(.bordered).tint(channel.cueSet ? .green : .gray).font(.system(size: 10)).controlSize(.small)
                Spacer()
                if !channel.fileName.isEmpty {
                    Button("✕") {
                        channel.currentFile = nil
                        channel.fileName = ""
                        channel.waveform = []
                        channel.duration = 0
                        channel.currentTime = 0
                        channel.cueSet = false
                    }
                    .buttonStyle(.borderless).font(.system(size: 10)).foregroundStyle(.red)
                }
                Text(channel.fileName).font(.system(size: 9)).foregroundStyle(Color(white: 0.4)).lineLimit(1)
            }.padding(.horizontal, 10)
            
            Divider().background(Color(white: 0.15)).padding(.horizontal, 8)
            
            // EQ row
            HStack(spacing: 16) {
                Spacer()
                EQKnob(label: "HI", value: $channel.hiKnob)
                EQKnob(label: "MID", value: $channel.midKnob)
                EQKnob(label: "LOW", value: $channel.lowKnob)
                Spacer()
            }
            
            Divider().background(Color(white: 0.15)).padding(.horizontal, 8)
            
            // Fader + meter
            HStack(spacing: 10) {
                LevelMeter(level: engine.channelPeaks[index])
                    .frame(width: 8, height: 80)
                VStack(spacing: 2) {
                    Text("\(Int(channel.fader * 100))").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(white: 0.6))
                    Slider(value: $channel.fader, in: 0...1)
                        .tint(.blue)
                }
            }
            .padding(.horizontal, 12)
            
            // Track info
            Text(channel.fileName.isEmpty ? " " : channel.fileName)
                .font(.system(size: 8)).foregroundStyle(Color(white: 0.35))
                .lineLimit(1).padding(.horizontal, 10)
        }
        .frame(minWidth: 260)
        .padding(.vertical, 6)
        .background(Color(white: index % 2 == 0 ? 0.12 : 0.1))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.18), lineWidth: 1))
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
            Circle().stroke(Color(white: 0.25), lineWidth: 4)
            Circle().trim(from: 0, to: CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)))
                .stroke(Color.blue, lineWidth: 4).rotationEffect(.degrees(-90))
            Circle().fill(Color(white: 0.18)).frame(width: 20, height: 20)
        }
        .gesture(DragGesture().onChanged { g in
            let delta = Float(g.translation.height) * -0.005
            value = max(range.lowerBound, min(range.upperBound, value + delta))
        })
    }
}

struct EQKnob: View {
    let label: String
    @Binding var value: Float
    
    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 8, weight: .medium)).foregroundStyle(Color(white: 0.5))
            ZStack {
                Circle().stroke(value > 0.48 && value < 0.52 ? Color(white: 0.3) : Color.blue, lineWidth: 3)
                Circle().trim(from: 0, to: CGFloat(abs(value - 0.5) * 2))
                    .stroke(value > 0.5 ? Color.orange : Color.red, lineWidth: 3)
                    .rotationEffect(.degrees(value > 0.5 ? -90 : 90))
                Circle().fill(Color(white: 0.14)).frame(width: 18, height: 18)
            }.frame(width: 34, height: 34)
            .gesture(DragGesture().onChanged { g in
                let delta = Float(g.translation.height) * -0.004
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
            VStack(spacing: 2) {
                Rectangle().fill(level > 0.85 ? Color.red : Color(white: 0.2)).frame(height: h * 0.25)
                Rectangle().fill(level > 0.7 ? Color.orange : Color(white: 0.2)).frame(height: h * 0.25)
                Rectangle().fill(level > 0.4 ? Color.yellow : Color(white: 0.2)).frame(height: h * 0.25)
                Rectangle().fill(level > 0.1 ? Color.green : Color(white: 0.2)).frame(height: h * 0.25)
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

struct LibraryView: View {
    @Bindable var engine: AudioEngine
    @Environment(\.dismiss) var dismiss
    @State private var selectedPlaylist: String = "__all__"
    @State private var newPlaylistName = ""
    
    var displayedTracks: [TrackRecord] {
        if selectedPlaylist == "__all__" {
            return engine.library.tracks
        }
        guard let pl = engine.library.playlists.first(where: { $0.id.uuidString == selectedPlaylist }) else {
            return []
        }
        return pl.trackIds.compactMap { id in engine.library.tracks.first(where: { $0.id == id }) }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("LIBRARY").font(.headline).foregroundStyle(Color(white: 0.8))
                Text("(\(engine.library.tracks.count) tracks\(engine.library.playlists.count > 0 ? ", \(engine.library.playlists.count) playlists" : ""))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(.bordered).controlSize(.small)
            }.padding([.top, .horizontal])
            
            // Playlist bar
            HStack(spacing: 6) {
                Picker("", selection: $selectedPlaylist) {
                    Text("🎵 All Tracks").tag("__all__")
                    ForEach(engine.library.playlists) { pl in
                        Text("📁 \(pl.name) (\(pl.trackIds.count))").tag(pl.id.uuidString)
                    }
                }
                .pickerStyle(.menu).frame(width: 200)
                
                TextField("New playlist name", text: $newPlaylistName)
                    .textFieldStyle(.plain).font(.system(size: 11))
                    .padding(4).background(Color(white: 0.15)).cornerRadius(4)
                    .frame(width: 140)
                
                Button("+") {
                    let n = newPlaylistName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty {
                        var lib = engine.library
                        lib.playlists.append(PlaylistRecord(id: UUID(), name: n, trackIds: [], created: Date()))
                        engine.library = lib
                        LibraryManager.default.save(lib)
                        newPlaylistName = ""
                    }
                }
                .buttonStyle(.bordered).tint(.green).controlSize(.small).font(.system(size: 9))
                
                if selectedPlaylist != "__all__" {
                    Button("✕") {
                        var lib = engine.library
                        lib.playlists.removeAll(where: { $0.id.uuidString == selectedPlaylist })
                        engine.library = lib
                        LibraryManager.default.save(lib)
                        selectedPlaylist = "__all__"
                    }
                    .buttonStyle(.borderless).foregroundStyle(.red).font(.system(size: 10))
                }
                
                Spacer()
            }.padding(.horizontal)
            
            Divider().background(Color(white: 0.15)).padding(.horizontal, 8)
            
            // Track list
            if displayedTracks.isEmpty {
                Text(selectedPlaylist == "__all__" 
                    ? "No tracks. Load a track into any channel — it saves automatically."
                    : "Playlist is empty. Add tracks from All Tracks view.")
                    .font(.body).foregroundStyle(.secondary).padding()
                Spacer()
            } else {
                List(displayedTracks) { track in
                    HStack {
                        Text(track.name).font(.body).lineLimit(1)
                            .frame(minWidth: 200, alignment: .leading)
                        Spacer()
                        Text(formatTime(track.duration)).font(.caption)
                            .foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                        
                        // Load into channel
                        HStack(spacing: 2) {
                            ForEach(0..<4) { i in
                                Button("CH\(i+1)") {
                                    engine.channels[i].loadFromLibrary(track: track)
                                    dismiss()
                                }
                                .buttonStyle(.bordered).tint(.gray).font(.system(size: 8)).controlSize(.mini)
                            }
                        }.frame(width: 120)
                        
                        // Add to playlist (only in All Tracks view)
                        if selectedPlaylist == "__all__" && !engine.library.playlists.isEmpty {
                            Menu("+") {
                                ForEach(engine.library.playlists) { pl in
                                    Button(pl.name) {
                                        var lib = engine.library
                                        if !lib.playlists.first(where: { $0.id == pl.id })!.trackIds.contains(track.id) {
                                            lib.playlists[lib.playlists.firstIndex(where: { $0.id == pl.id })!].trackIds.append(track.id)
                                        }
                                        engine.library = lib
                                        LibraryManager.default.save(lib)
                                    }
                                }
                            }
                            .menuStyle(.borderlessButton).frame(width: 20)
                            .font(.system(size: 10))
                        }
                        
                        Button("✕") {
                            var lib = engine.library
                            if selectedPlaylist == "__all__" {
                                lib.tracks.removeAll(where: { $0.id == track.id })
                            } else {
                                if let idx = lib.playlists.firstIndex(where: { $0.id.uuidString == selectedPlaylist }) {
                                    lib.playlists[idx].trackIds.removeAll(where: { $0 == track.id })
                                }
                            }
                            engine.library = lib
                            LibraryManager.default.save(lib)
                        }
                        .buttonStyle(.borderless).font(.system(size: 10)).foregroundStyle(.red)
                    }
                }
            }
        }
        .frame(width: 1200, height: 500)
        .background(Color(white: 0.12))
        .preferredColorScheme(.dark)
    }
    
    func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60; let s = Int(t) % 60
        return "\(m):\(String(format: "%02d", s))"
    }
}

struct BottomSection: View {
    @Bindable var engine: AudioEngine
    
    var body: some View {
        HStack(spacing: 0) {
            BeatFXView(engine: engine).frame(width: 260)
            Divider().background(Color(white: 0.15))
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
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("BEAT FX").font(.system(size: 9, weight: .bold)).foregroundStyle(.blue)
                    Text("\(Int(engine.masterBPM)) BPM").font(.system(size: 8)).foregroundStyle(.secondary)
                    Button(engine.fxOn ? "ON" : "OFF") { engine.fxOn.toggle() }
                        .buttonStyle(.bordered).tint(engine.fxOn ? .green : .gray).font(.system(size: 8)).controlSize(.mini)
                }
                HStack(spacing: 4) {
                    Picker("", selection: $engine.fxType) {
                        ForEach(FXType.allCases, id: \.self) { t in Text(t.rawValue.uppercased()).font(.system(size: 8)).tag(t) }
                    }.pickerStyle(.menu).frame(width: 70)
                    DialKnob(value: $engine.fxParam, range: 0...1).frame(width: 22, height: 22)
                    Picker("", selection: $engine.fxBeat) {
                        ForEach(FXBeat.allCases, id: \.self) { b in Text(b.rawValue).font(.system(size: 8)).tag(b) }
                    }.pickerStyle(.menu).frame(width: 55)
                    Text("BPM").font(.system(size: 7)).foregroundStyle(.secondary)
                    TextField("BPM", value: $engine.bpmOverride, format: .number)
                        .textFieldStyle(.plain).font(.system(size: 9)).multilineTextAlignment(.center)
                        .frame(width: 40).padding(2).background(Color(white: 0.15)).cornerRadius(3)
                        .onChange(of: engine.bpmOverride) { _, _ in engine.updateMix() }
                    if engine.bpmOverride > 0 {
                        Button("✕") { engine.bpmOverride = 0 }
                            .buttonStyle(.borderless).font(.system(size: 7)).foregroundStyle(.red)
                    }
                }
            }
        }.padding(4)
    }
}

struct CrossfaderView: View {
    @Bindable var engine: AudioEngine
    
    var body: some View {
        HStack(spacing: 16) {
            Text("A").font(.system(size: 13, weight: .bold)).foregroundStyle(engine.crossfader < 0.3 ? .orange : .secondary)
            Slider(value: $engine.crossfader, in: 0...1)
                .onChange(of: engine.crossfader) { _, _ in engine.updateMix() }
            Text("B").font(.system(size: 13, weight: .bold)).foregroundStyle(engine.crossfader > 0.7 ? .orange : .secondary)
            Text("CURVE").font(.system(size: 10)).foregroundStyle(.secondary)
            Slider(value: $engine.crossfaderCurve, in: 0...1).frame(width: 80)
                .onChange(of: engine.crossfaderCurve) { _, _ in engine.updateMix() }
        }.padding(.horizontal, 16)
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
