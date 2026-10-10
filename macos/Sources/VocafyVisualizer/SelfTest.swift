import Foundation

/// `--selftest`: checks the spectrum against known tones without opening a window or touching
/// any audio device, so it runs on CI.
enum SelfTest {
    static func run() -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ label: String) {
            print("\(ok ? "ok  " : "FAIL") \(label)")
            if !ok { failures += 1 }
        }

        check(peakBar(of: 440) == bar(containing: 440), "440 Hz lands in its own bar")
        check(peakBar(of: 5_000) == bar(containing: 5_000), "5 kHz lands in its own bar")

        let silent = Spectrum()
        check(silent.bars().allSatisfy { $0 == 0 }, "silence draws no bars")

        return failures == 0 ? 0 : 1
    }

    private static func peakBar(of hz: Float) -> Int {
        let spectrum = Spectrum()
        spectrum.sampleRate = 48_000
        let samples = (0..<Spectrum.fftSize).map { 0.5 * sin(2 * Float.pi * hz * Float($0) / 48_000) }
        samples.withUnsafeBufferPointer { spectrum.push($0, channels: 1) }
        // Lets the time smoothing settle.
        var bars: [UInt8] = []
        for _ in 0..<30 { bars = spectrum.bars() }
        return bars.indices.max { bars[$0] < bars[$1] }!
    }

    private static func bar(containing hz: Float) -> Int {
        (0..<Spectrum.barCount).first { Spectrum.edge($0) <= hz && hz < Spectrum.edge($0 + 1) }!
    }
}
