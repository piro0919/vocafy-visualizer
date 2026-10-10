import Accelerate
import Foundation

/// Turns the tapped samples into bar heights, the way Web Audio's AnalyserNode does: a
/// Blackman-windowed FFT, smoothed over time, read in decibels and scaled to 0–255.
final class Spectrum: @unchecked Sendable {
    static let barCount = 32
    static let fftSize = 2048

    // Where the bars sit on the frequency axis, spread evenly on a log scale.
    private static let lowHz: Float = 60
    private static let highHz: Float = 16_000
    // The default AnalyserNode range (-100 to -30 dB) pins loud, mastered songs to the top.
    private static let minDecibels: Float = -80
    private static let maxDecibels: Float = -10
    private static let smoothing: Float = 0.75

    // Written by the audio thread, read by the main thread.
    private let lock = NSLock()
    private var ring = [Float](repeating: 0, count: fftSize)
    private var position = 0
    private var rate: Float = 48_000

    private var smoothed = [Float](repeating: 0, count: fftSize / 2)
    private let fft = vDSP.FFT(
        log2n: vDSP_Length(log2(Float(fftSize))), radix: .radix2, ofType: DSPSplitComplex.self)!
    private let window = vDSP.window(
        ofType: Float.self, usingSequence: .blackman, count: fftSize, isHalfWindow: false)

    var sampleRate: Float {
        get { lock.withLock { rate } }
        set { lock.withLock { rate = newValue } }
    }

    /// Takes interleaved samples and keeps their mono mix.
    func push(_ samples: UnsafeBufferPointer<Float>, channels: Int) {
        guard channels > 0 else { return }
        lock.withLock {
            var i = 0
            while i + channels <= samples.count {
                var sum: Float = 0
                for c in 0..<channels { sum += samples[i + c] }
                ring[position] = sum / Float(channels)
                position = (position + 1) % Self.fftSize
                i += channels
            }
        }
    }

    /// Forgets what was heard, so the bars start from the floor after a gap.
    func reset() {
        lock.withLock {
            for i in ring.indices { ring[i] = 0 }
            position = 0
        }
        for i in smoothed.indices { smoothed[i] = 0 }
    }

    /// The current bar heights, 0–255. Called from the main thread only.
    func bars() -> [UInt8] {
        let (ordered, sampleRate) = lock.withLock { (Array(ring[position...] + ring[..<position]), rate) }
        let windowed = vDSP.multiply(ordered, window)
        let half = Self.fftSize / 2

        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realBuffer in
            imag.withUnsafeMutableBufferPointer { imagBuffer in
                var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imagBuffer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                fft.forward(input: split, output: &split)
                vDSP.absolute(split, result: &magnitudes)
            }
        }
        // vDSP's real forward FFT comes out scaled by 2; dividing by N brings it to the same
        // footing as AnalyserNode's.
        vDSP.multiply(1 / Float(Self.fftSize), magnitudes, result: &magnitudes)
        for k in 0..<half {
            smoothed[k] = Self.smoothing * smoothed[k] + (1 - Self.smoothing) * magnitudes[k]
        }

        let hzPerBin = sampleRate / Float(Self.fftSize)
        return (0..<Self.barCount).map { bar in
            let from = max(1, Int((Self.edge(bar) / hzPerBin).rounded()))
            let to = max(from + 1, Int((Self.edge(bar + 1) / hzPerBin).rounded()))
            var peak: Float = 0
            for k in from..<min(to, half) { peak = max(peak, smoothed[k]) }
            let decibels = 20 * log10(max(peak, 1e-9))
            let scaled = (decibels - Self.minDecibels) / (Self.maxDecibels - Self.minDecibels) * 255
            return UInt8(max(0, min(255, scaled)))
        }
    }

    /// The lower edge of a bar, in Hz.
    static func edge(_ bar: Int) -> Float {
        lowHz * pow(highHz / lowHz, Float(bar) / Float(barCount))
    }
}
