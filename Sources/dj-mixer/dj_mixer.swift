import SwiftUI
import AVFoundation

@main struct DJMixerApp: App {
    @State private var engine = AudioEngine()
    
    var body: some Scene {
        WindowGroup {
            ContentView(engine: $engine)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear {
                    engine.start()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - Audio Engine

@Observable class AudioEngine {
    let avEngine = AVAudioEngine()
    var decks: [Deck] = [Deck(id: "A"), Deck(id: "B")]
    var crossfader: Float = 0.5
    var masterMixer: AVAudioMixerNode
    
    init() {
        masterMixer = AVAudioMixerNode()
        avEngine.attach(masterMixer)
        avEngine.connect(masterMixer, to: avEngine.outputNode, format: nil)
        for deck in decks { deck.attach(to: avEngine, master: masterMixer) }
        for deck in decks { deck.onUpdate = { [weak self] in self?.updateMix() } }
    }
    
    func start() {
        do { try avEngine.start() } catch { print("engine start fail: \(error)") }
    }
    
    func updateMix() {
        guard decks.count == 2 else { return }
        let a = decks[0], b = decks[1]
        a.mixer.volume = a.volume * (1 - crossfader) * 2
        b.mixer.volume = b.volume * crossfader * 2
    }
}

@Observable class Deck: Identifiable {
    let id: String
    var player = AVAudioPlayerNode()
    var eq: AVAudioUnitEQ
    var mixer = AVAudioMixerNode()
    var volume: Float = 1.0 { didSet { onUpdate?() } }
    var hiBand: Float = 0.5 { didSet { updateEQ(); onUpdate?() } }
    var midBand: Float = 0.5 { didSet { updateEQ(); onUpdate?() } }
    var loBand: Float = 0.5 { didSet { updateEQ(); onUpdate?() } }
    var isPlaying = false { didSet { isPlaying ? startPlay() : stopPlay() } }
    var currentFile: AVAudioFile? { didSet { player.stop(); isPlaying = false; pausedAt = 0 } }
    var pausedAt: TimeInterval = 0
    var duration: TimeInterval = 0
    var waveform: [Float] = []
    var fileName: String = ""
    var onUpdate: (() -> Void)?
    
    init(id: String) {
        self.id = id
        eq = AVAudioUnitEQ(numberOfBands: 3)
        let configs: [(type: AVAudioUnitEQFilterType, freq: Float, bw: Float)] = [
            (.lowShelf, 200, 0.5),
            (.parametric, 1200, 0.7),
            (.highShelf, 7000, 0.5)
        ]
        for (i, c) in configs.enumerated() {
            eq.bands[i].filterType = c.type
            eq.bands[i].frequency = c.freq
            eq.bands[i].bandwidth = c.bw
            eq.bands[i].gain = 0
            eq.bands[i].bypass = false
        }
    }
    
    func attach(to engine: AVAudioEngine, master: AVAudioMixerNode) {
        engine.attach(player)
        engine.attach(eq)
        engine.attach(mixer)
        engine.connect(player, to: eq, format: nil)
        engine.connect(eq, to: mixer, format: nil)
        engine.connect(mixer, to: master, format: nil)
    }
    
    func load(url: URL) {
        do {
            let file = try AVAudioFile(forReading: url)
            currentFile = file
            fileName = url.lastPathComponent
            duration = TimeInterval(file.length) / file.fileFormat.sampleRate
            computeWaveform(file: file)
            pausedAt = 0
        } catch { print("load fail: \(error)") }
    }
    
    func computeWaveform(file: AVAudioFile) {
        guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return }
        do {
            try file.read(into: buf)
        } catch { return }
        guard let data = buf.floatChannelData?[0] else { return }
        let totalFrames = Int(buf.frameLength)
        let targetSamples = 500
        waveform = (0..<targetSamples).map { i -> Float in
            let start = i * totalFrames / targetSamples
            let end = (i + 1) * totalFrames / targetSamples
            var peak: Float = 0
            for j in start..<min(end, totalFrames) {
                peak = max(peak, abs(data[j]))
            }
            return peak
        }
        file.framePosition = 0
    }
    
    func startPlay() {
        guard let file = currentFile else { isPlaying = false; return }
        player.stop()
        player.scheduleFile(file, at: nil, completionHandler: nil)
        let startFrame = AVAudioFramePosition(pausedAt * file.fileFormat.sampleRate)
        if startFrame > 0 {
            player.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(file.length - startFrame), at: nil)
        }
        player.play()
    }
    
    func stopPlay() {
        player.stop()
        if let file = currentFile, let lastTime = player.lastRenderTime?.sampleTime {
            pausedAt = TimeInterval(lastTime) / file.fileFormat.sampleRate
        } else {
            pausedAt = 0
        }
    }
    
    func updateEQ() {
        eq.bands[0].gain = (loBand - 0.5) * 12
        eq.bands[1].gain = (midBand - 0.5) * 12
        eq.bands[2].gain = (hiBand - 0.5) * 12
    }
    
    func updateEngine() {
        // called via engine.updateMix
    }
}



// MARK: - Views

struct ContentView: View {
    @Binding var engine: AudioEngine
    
    var body: some View {
        HStack(spacing: 0) {
            DeckView(deck: engine.decks[0], color: .accentColor)
            CrossfaderView(crossfader: $engine.crossfader, onDrag: { engine.updateMix() })
            DeckView(deck: engine.decks[1], color: .orange)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
    }
}

struct DeckView: View {
    @Bindable var deck: Deck
    let color: Color
    @State private var showFilePicker = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Deck \(deck.id)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(deck.fileName).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            
            WaveformView(waveform: deck.waveform, progress: deck.isPlaying ? 0.3 : 0)
                .frame(height: 72)
                .cornerRadius(6)
            
            HStack(spacing: 4) {
                Button(deck.isPlaying ? "❚❚" : "▶") { deck.isPlaying.toggle() }
                    .buttonStyle(.borderedProminent)
                    .tint(deck.isPlaying ? color : .gray)
                Button("Cue") {}
                    .buttonStyle(.borderless)
                    .font(.caption)
                Button("⟳") {}
                    .buttonStyle(.borderless)
                    .font(.caption)
                Button("Load") { showFilePicker = true }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            
            VStack(spacing: 2) {
                FaderView(label: "Vol", value: $deck.volume, range: 0...1, color: color)
                FaderView(label: "Hi", value: $deck.hiBand, range: 0...1, color: .purple)
                FaderView(label: "Mid", value: $deck.midBand, range: 0...1, color: .purple)
                FaderView(label: "Lo", value: $deck.loBand, range: 0...1, color: .purple)
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { deck.load(url: url) }
        }
    }
}

struct WaveformView: View {
    let waveform: [Float]
    let progress: Double
    
    var body: some View {
        GeometryReader { geo in
            if waveform.isEmpty {
                Text("Load a track").font(.caption).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Canvas { ctx, size in
                    let barW = size.width / CGFloat(waveform.count)
                    for (i, peak) in waveform.enumerated() {
                        let barH = CGFloat(peak) * size.height * 0.9
                        let rect = CGRect(x: CGFloat(i) * barW, y: (size.height - barH) / 2, width: max(barW - 0.5, 1), height: max(barH, 1))
                        ctx.fill(Path(roundedRect: rect, cornerSize: CGSize(width: 0.5, height: 0.5)), with: .color(peak > 0.3 ? .orange : .purple))
                    }
                    // progress line
                    let px = size.width * progress
                    ctx.stroke(Path(CGPath(rect: CGRect(x: px, y: 0, width: 1, height: size.height), transform: nil)), with: .color(.white))
                }
            }
        }
    }
}

struct FaderView: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).frame(width: 20)
            Slider(value: $value, in: range)
                .tint(label == "Vol" ? color : .purple)
                .controlSize(.mini)
        }
    }
}

struct CrossfaderView: View {
    @Binding var crossfader: Float
    let onDrag: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            Text("A").font(.caption2).foregroundStyle(crossfader < 0.5 ? .orange : .secondary)
            Slider(value: $crossfader, in: 0...1)
                .onChange(of: crossfader) { _, _ in onDrag() }
                .controlSize(.small)
                .rotationEffect(.degrees(-90))
                .frame(width: 160)
            Text("B").font(.caption2).foregroundStyle(crossfader > 0.5 ? .orange : .secondary)
        }
        .frame(width: 40)
        .padding(.vertical, 8)
    }
}
