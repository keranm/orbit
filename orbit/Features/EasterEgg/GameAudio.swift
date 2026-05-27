import AVFoundation

final class GameAudio {
    static let shared = GameAudio()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let sampleRate: Double = 44100

    private init() {
        engine.attach(playerNode)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.35
        try? engine.start()
    }

    // MARK: - Sound effects

    func laser() {
        schedule(tone(from: 900, to: 440, duration: 0.055, shape: .sine, amplitude: 0.28))
    }

    func explosion() {
        schedule(noise(duration: 0.18, amplitude: 0.35, decay: true))
    }

    func playerHit() {
        schedule(tone(from: 260, to: 100, duration: 0.22, shape: .square, amplitude: 0.3))
    }

    func bossHit() {
        schedule(tone(from: 180, to: 120, duration: 0.14, shape: .square, amplitude: 0.25))
    }

    func march(high: Bool) {
        let freq: Float = high ? 200 : 130
        schedule(tone(from: freq, to: freq, duration: 0.038, shape: .square, amplitude: 0.18))
    }

    func victory() {
        let melody: [(Float, Double)] = [(523, 0.10), (659, 0.10), (784, 0.10), (1047, 0.22)]
        var delay: Double = 0
        for (freq, dur) in melody {
            let buf = tone(from: freq, to: freq, duration: Float(dur), shape: .sine, amplitude: 0.3)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.schedule(buf) }
            delay += dur
        }
    }

    func gameOver() {
        let melody: [(Float, Double)] = [(523, 0.14), (440, 0.14), (349, 0.14), (294, 0.38)]
        var delay: Double = 0
        for (freq, dur) in melody {
            let buf = tone(from: freq, to: freq, duration: Float(dur), shape: .sine, amplitude: 0.3)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.schedule(buf) }
            delay += dur
        }
    }

    func lightning() {
        // Low rumble charge → sharp crack
        let charge = tone(from: 80, to: 200, duration: 0.18, shape: .square, amplitude: 0.22)
        let crack   = tone(from: 900, to: 300, duration: 0.10, shape: .sine,   amplitude: 0.4)
        schedule(charge)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in self?.schedule(crack) }
    }

    func bossIntro() {
        let melody: [(Float, Double)] = [(200, 0.12), (160, 0.12), (130, 0.12), (100, 0.28)]
        var delay: Double = 0
        for (freq, dur) in melody {
            let buf = tone(from: freq, to: freq, duration: Float(dur), shape: .square, amplitude: 0.28)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.schedule(buf) }
            delay += dur
        }
    }

    // MARK: - Private

    private func schedule(_ buffer: AVAudioPCMBuffer?) {
        guard let buffer else { return }
        if !engine.isRunning { try? engine.start() }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        if !playerNode.isPlaying { playerNode.play() }
    }

    private enum Waveform { case sine, square }

    private func tone(from startFreq: Float, to endFreq: Float, duration: Float,
                      shape: Waveform, amplitude: Float) -> AVAudioPCMBuffer? {
        let sr = Float(sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sr * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        var phase: Float = 0
        for i in 0..<Int(frameCount) {
            let t = Float(i) / Float(frameCount)
            let freq = startFreq + (endFreq - startFreq) * t
            let twoPiF = 2 * Float.pi * freq / sr
            let raw: Float = shape == .sine ? sin(phase) : (phase < Float.pi ? 1 : -1)
            let env: Float = t < 0.06 ? t / 0.06 : (t > 0.75 ? (1 - t) / 0.25 : 1)
            data[i] = raw * env * amplitude
            phase += twoPiF
            if phase > 2 * Float.pi { phase -= 2 * Float.pi }
        }
        return buffer
    }

    private func noise(duration: Float, amplitude: Float, decay: Bool) -> AVAudioPCMBuffer? {
        let sr = Float(sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sr * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        for i in 0..<Int(frameCount) {
            let env: Float = decay ? 1 - Float(i) / Float(frameCount) : 1
            data[i] = Float.random(in: -1...1) * env * amplitude
        }
        return buffer
    }
}
