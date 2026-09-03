import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Live Indicator

/// Red "live" dot with a pulsing halo. `isActive` should track panel visibility so the
/// pulse only runs while the panel is on screen.
struct LiveIndicator: View {
    let isActive: Bool

    var body: some View {
        #if os(macOS)
        CoreAnimationLiveDot(isActive: isActive)
            .frame(width: 8, height: 8)
        #else
        SwiftUILiveDot(isActive: isActive)
        #endif
    }
}

#if os(macOS)
/// The endless pulse runs on the render server via `CABasicAnimation`, so it never wakes
/// SwiftUI's update loop. A plain `.repeatForever` SwiftUI animation here instead forces a
/// full panel + `glassEffect` display-list recommit every frame — ~20% CPU while the panel
/// is merely open.
private struct CoreAnimationLiveDot: NSViewRepresentable {
    let isActive: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        view.wantsLayer = true

        let halo = CALayer()
        halo.frame = view.bounds
        halo.cornerRadius = 4
        halo.backgroundColor = NSColor.systemRed.cgColor
        halo.opacity = 0

        let core = CALayer()
        core.frame = CGRect(x: 1.5, y: 1.5, width: 5, height: 5)
        core.cornerRadius = 2.5
        core.backgroundColor = NSColor.systemRed.cgColor

        view.layer?.addSublayer(halo)
        view.layer?.addSublayer(core)
        context.coordinator.halo = halo
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.setActive(isActive)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var halo: CALayer?

        func setActive(_ active: Bool) {
            guard let halo else { return }
            if active {
                guard halo.animation(forKey: "pulse") == nil else { return }
                let anim = CABasicAnimation(keyPath: "opacity")
                anim.fromValue = 0.35
                anim.toValue = 0.0
                anim.duration = 1.2
                anim.autoreverses = true
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                anim.isRemovedOnCompletion = false
                halo.add(anim, forKey: "pulse")
            } else {
                halo.removeAnimation(forKey: "pulse")
                halo.opacity = 0
            }
        }
    }
}
#else
private struct SwiftUILiveDot: View {
    let isActive: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(Color.red.opacity(pulse ? 0.0 : 0.35))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
                    .onDisappear { pulse = false }
            }
            Circle()
                .fill(Color.red)
                .frame(width: 5, height: 5)
        }
    }
}
#endif

// MARK: - Waveform Animation

/// Five-bar "equaliser" shown on the artwork while a stream is playing. `isActive` should
/// track panel visibility so the bars only animate while the panel is on screen.
struct WaveformView: View {
    var isActive: Bool = true

    var body: some View {
        #if os(macOS)
        CoreAnimationWaveform(isActive: isActive)
            .frame(width: WaveformMetrics.width, height: WaveformMetrics.maxBarHeight)
        #else
        SwiftUIWaveform(isActive: isActive)
        #endif
    }
}

private enum WaveformMetrics {
    static let barWidth: CGFloat = 2.5
    static let spacing: CGFloat = 2
    static let barCount = 5
    static let maxBarHeight: CGFloat = 14
    static let width = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing

    /// Two keyframes the bars ease between; every value is <= `maxBarHeight`.
    static let heights: [[CGFloat]] = [
        [4, 14, 8, 12, 5],
        [10, 6, 14, 4, 12]
    ]
}

#if os(macOS)
/// Like `CoreAnimationLiveDot`: the endless bar animation runs on the render server via
/// `CABasicAnimation`, so it never wakes SwiftUI's update loop and never forces a panel +
/// `glassEffect` display-list recommit. A `.repeatForever` SwiftUI animation here instead
/// costs ~30% CPU while the panel is open (~2% otherwise).
private struct CoreAnimationWaveform: NSViewRepresentable {
    let isActive: Bool

    func makeNSView(context: Context) -> NSView {
        let m = WaveformMetrics.self
        let view = NSView(frame: CGRect(x: 0, y: 0, width: m.width, height: m.maxBarHeight))
        view.wantsLayer = true

        for i in 0..<m.barCount {
            let bar = CALayer()
            // Anchor at the bottom edge so scaling `transform.scale.y` grows the bar upward.
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.bounds = CGRect(x: 0, y: 0, width: m.barWidth, height: m.maxBarHeight)
            bar.position = CGPoint(x: CGFloat(i) * (m.barWidth + m.spacing) + m.barWidth / 2, y: 0)
            bar.cornerRadius = m.barWidth / 2
            bar.backgroundColor = NSColor.white.cgColor
            // Resting state matches the animation's `fromValue`, so there's no snap on add/remove.
            bar.transform = CATransform3DMakeScale(1, m.heights[0][i] / m.maxBarHeight, 1)
            view.layer?.addSublayer(bar)
            context.coordinator.bars.append(bar)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.setActive(isActive)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var bars: [CALayer] = []

        func setActive(_ active: Bool) {
            let m = WaveformMetrics.self
            for (i, bar) in bars.enumerated() {
                if active {
                    guard bar.animation(forKey: "eq") == nil else { continue }
                    let anim = CABasicAnimation(keyPath: "transform.scale.y")
                    anim.fromValue = m.heights[0][i] / m.maxBarHeight
                    anim.toValue = m.heights[1][i] / m.maxBarHeight
                    anim.duration = 0.45
                    anim.autoreverses = true
                    anim.repeatCount = .infinity
                    anim.timeOffset = Double(i) * 0.09
                    anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    anim.isRemovedOnCompletion = false
                    bar.add(anim, forKey: "eq")
                } else {
                    bar.removeAnimation(forKey: "eq")
                }
            }
        }
    }
}
#else
private struct SwiftUIWaveform: View {
    let isActive: Bool
    @State private var phase = false

    var body: some View {
        HStack(spacing: WaveformMetrics.spacing) {
            ForEach(0..<WaveformMetrics.barCount, id: \.self) { i in
                Capsule()
                    .frame(
                        width: WaveformMetrics.barWidth,
                        height: phase ? WaveformMetrics.heights[1][i] : WaveformMetrics.heights[0][i]
                    )
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(i) * 0.09),
                        value: phase
                    )
            }
        }
        .onAppear { phase = isActive }
        .onChange(of: isActive) { phase = $0 }
    }
}
#endif
