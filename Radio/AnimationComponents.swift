import SwiftUI

// MARK: - Live Indicator

struct LiveIndicator: View {
    let isActive: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(Color.red.opacity(pulse ? 0.0 : 0.35))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            }
            Circle()
                .fill(Color.red)
                .frame(width: 5, height: 5)
        }
        .onAppear { pulse = isActive }
    }
}

// MARK: - Waveform Animation

struct WaveformView: View {
    @State private var phase = false

    private let heights: [[CGFloat]] = [
        [4, 14, 8, 12, 5],
        [10, 6, 14, 4, 12]
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .frame(width: 2.5, height: phase ? heights[1][i] : heights[0][i])
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(i) * 0.09),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }
}
