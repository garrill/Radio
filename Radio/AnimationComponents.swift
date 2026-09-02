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
