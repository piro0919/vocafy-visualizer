import SwiftUI

@MainActor
final class BarModel: ObservableObject {
    @Published var bars = [UInt8](repeating: 0, count: Spectrum.barCount)
}

/// Vocafy's teal bars on Vocafy's dark ground (#39c5bb on #12181b).
struct SpectrumView: View {
    @ObservedObject var model: BarModel

    private static let bar = Color(red: 0x39 / 255, green: 0xc5 / 255, blue: 0xbb / 255)
    private static let ground = Color(red: 0x12 / 255, green: 0x18 / 255, blue: 0x1b / 255)

    var body: some View {
        Canvas { context, size in
            let count = CGFloat(model.bars.count)
            let gap = max(2, size.width / count * 0.18)
            let width = (size.width - gap * (count - 1)) / count
            for (i, value) in model.bars.enumerated() {
                let height = max(3, CGFloat(value) / 255 * size.height)
                let rect = CGRect(x: CGFloat(i) * (width + gap), y: size.height - height, width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: min(width / 2, 6)), with: .color(Self.bar))
            }
        }
        .padding(16)
        .background(Self.ground)
    }
}
