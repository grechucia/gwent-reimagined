import AVFoundation

final class Audio: NSObject, AVAudioPlayerDelegate {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var music: AVAudioPlayer?
    private var tracks: [URL] = []
    private var lastTrack = -1
    private let dir: URL
    var muted = false
    var musicOn = true { didSet { musicOn ? playMusic() : music?.stop() } }

    init(gameDir: URL) {
        dir = gameDir
        super.init()
        let mixer = engine.mainMixerNode
        let fmt = mixer.outputFormat(forBus: 0)
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: mixer, format: fmt)
            players.append(p)
        }
        try? engine.start()
        tracks = ((try? FileManager.default.contentsOfDirectory(at: dir.appendingPathComponent("audio"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "mp3" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func buffer(_ name: String) -> AVAudioPCMBuffer? {
        if let b = buffers[name] { return b }
        let url = dir.appendingPathComponent("sfx/\(name).mp3")
        guard let f = try? AVAudioFile(forReading: url),
              let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)) else { return nil }
        try? f.read(into: b)
        let outFmt = engine.mainMixerNode.outputFormat(forBus: 0)
        if b.format == outFmt { buffers[name] = b; return b }
        guard let conv = AVAudioConverter(from: b.format, to: outFmt) else { return nil }
        let cap = AVAudioFrameCount(Double(b.frameLength) * outFmt.sampleRate / b.format.sampleRate) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return b
        }
        buffers[name] = out
        return out
    }
    func preload(_ names: [String]) { DispatchQueue.global(qos: .utility).async { for n in names { _ = self.buffer(n) } } }

    func play(_ name: String, volume: Float = 0.9) {
        guard !muted, let b = buffer(name) else { return }
        if !engine.isRunning { try? engine.start() }
        let p = players[next]; next = (next + 1) % players.count
        p.stop()
        p.volume = volume
        p.scheduleBuffer(b, at: nil, options: [])
        p.play()
    }

    private(set) var menuMode = true
    func setMenuMode(_ m: Bool) {
        guard m != menuMode else { return }
        menuMode = m; music?.stop(); music = nil; playMusic()
    }
    func playMusic() {
        guard musicOn, !muted, !tracks.isEmpty else { return }
        if menuMode {
            if music?.isPlaying == true { return }
            guard let t = tracks.first(where: { $0.lastPathComponent == "track11.mp3" }) ?? tracks.first else { return }
            music = try? AVAudioPlayer(contentsOf: t)
            music?.numberOfLoops = -1
            music?.volume = 0.35
            music?.play()
            return
        }
        var i = Int.random(in: 0..<tracks.count)
        if tracks.count > 1 { while i == lastTrack { i = Int.random(in: 0..<tracks.count) } }
        lastTrack = i
        music = try? AVAudioPlayer(contentsOf: tracks[i])
        music?.delegate = self
        music?.volume = 0.35
        music?.play()
    }
    func skipTrack() { guard !menuMode else { return }; music?.stop(); playMusic() }
    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully: Bool) { if !menuMode { playMusic() } }
}
