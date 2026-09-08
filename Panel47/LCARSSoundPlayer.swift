import AVFoundation

/// Plays a short, procedurally synthesized two-tone blip for UI feedback —
/// not a sample of anything, just a couple of sine sweeps with an envelope.
final class LCARSSoundPlayer {
    static let shared = LCARSSoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer?

    private init() {
        buffer = Self.makeBlipBuffer()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer?.format)
        try? engine.start()
    }

    func playBlip() {
        guard let buffer else { return }
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        if !player.isPlaying { player.play() }
    }

    private static func makeBlipBuffer() -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let duration = 0.09
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        let data = buffer.floatChannelData![0]
        let firstTone = 1400.0
        let secondTone = 1900.0

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let envelope = sin(.pi * t / duration) // fades in, then out
            let frequency = t < duration / 2 ? firstTone : secondTone
            data[i] = Float(sin(2 * .pi * frequency * t) * envelope * 0.2)
        }

        return buffer
    }
}
