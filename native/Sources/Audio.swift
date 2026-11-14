// Music and sound effects: menu theme, random in-game tracks, and low-latency sound effect playback.
import AVFoundation

/// Plays the music (AVAudioPlayer) and sound effects (AVAudioEngine with a small pool of player nodes).
final class Audio: NSObject, AVAudioPlayerDelegate {
    let engine = AVAudioEngine()
    var players: [AVAudioPlayerNode] = []
    var next = 0
    var buffers: [String: AVAudioPCMBuffer] = [:]
    var music: AVAudioPlayer?
    var tracks: [URL] = []
    var lastTrack = -1
    let dir: URL
    var muted = false
    var musicOn = true { didSet { musicOn ? playMusic() : music?.stop() } }

    init(gameDir: URL) {
        dir = gameDir
        super.init()
        let mixer = engine.mainMixerNode
        let fmt = mixer.outputFormat(forBus: 0)
        for _ in 0..<10 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: mixer, format: fmt)
            players.append(node)
        }
        try? engine.start()
        tracks = ((try? FileManager.default.contentsOfDirectory(at: dir.appendingPathComponent("audio"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "mp3" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Loads and caches a sound effect as a PCM buffer.
    func buffer(_ name: String) -> AVAudioPCMBuffer? {
        if let cached = buffers[name] { return cached }
        let url = dir.appendingPathComponent("sfx/\(name).mp3")
        guard let file = try? AVAudioFile(forReading: url),
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        try? file.read(into: pcmBuffer)
        let outFmt = engine.mainMixerNode.outputFormat(forBus: 0)
        if pcmBuffer.format == outFmt { buffers[name] = pcmBuffer; return pcmBuffer }
        guard let conv = AVAudioConverter(from: pcmBuffer.format, to: outFmt) else { return nil }
        let cap = AVAudioFrameCount(Double(pcmBuffer.frameLength) * outFmt.sampleRate / pcmBuffer.format.sampleRate) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return pcmBuffer
        }
        buffers[name] = out
        return out
    }
    /// Loads the given sound effects in advance.
    func preload(_ names: [String]) { DispatchQueue.global(qos: .utility).async { for name in names { _ = self.buffer(name) } } }

    /// Plays a sound effect by name.
    func play(_ name: String, volume: Float = 0.9) {
        guard !muted, let pcmBuffer = buffer(name) else { return }
        if !engine.isRunning { try? engine.start() }
        let node = players[next]; next = (next + 1) % players.count
        node.stop()
        node.volume = volume
        node.scheduleBuffer(pcmBuffer, at: nil, options: [])
        node.play()
    }

    private(set) var menuMode = true
    /// Switches between the menu theme (true) and random in-game music (false).
    func setMenuMode(_ menu: Bool) {
        guard menu != menuMode else { return }
        menuMode = menu; music?.stop(); music = nil; playMusic()
    }
    /// Starts the music for the current mode.
    func playMusic() {
        guard musicOn, !muted, !tracks.isEmpty else { return }
        if menuMode {
            if music?.isPlaying == true { return }
            guard let menuTrack = tracks.first(where: { $0.lastPathComponent == "track11.mp3" }) ?? tracks.first else { return }
            music = try? AVAudioPlayer(contentsOf: menuTrack)
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
    /// Skips to another music track.
    func skipTrack() { guard !menuMode else { return }; music?.stop(); playMusic() }
    /// Starts the next track when one finishes.
    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully: Bool) { if !menuMode { playMusic() } }
}
