import SwiftUI

// MARK: - Marquee Text

struct MarqueeText: View {
    let text: String
    let maxWidth: CGFloat

    @State private var animate = false
    @State private var naturalWidth: CGFloat = 0

    private var overflow: CGFloat { max(0, naturalWidth - maxWidth) }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            // Measure actual SwiftUI-rendered width; re-measure if the text changes.
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { naturalWidth = geo.size.width }
                        .onChange(of: text) { naturalWidth = geo.size.width }
                }
            )
            .offset(x: animate ? -overflow : 0)
            .frame(
                width: overflow > 1 ? maxWidth : naturalWidth > 0 ? naturalWidth : nil,
                alignment: .leading
            )
            .clipped()
            .task(id: text) {
                // Reset and wait one tick for the onChange measurement to settle
                animate = false
                try? await Task.sleep(for: .milliseconds(50))
                guard overflow > 1, !Task.isCancelled else { return }
                let duration = max(2.0, Double(overflow) / 20)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.linear(duration: duration)) { animate = true }
                    try? await Task.sleep(for: .seconds(duration + 2))
                    withAnimation(.linear(duration: duration)) { animate = false }
                    try? await Task.sleep(for: .seconds(duration))
                }
            }
    }
}

// MARK: - Next Broadcast Marquee

struct NextBroadcastMarquee: View {
    let broadcast: Broadcast
    let isHovered: Bool
    let maxWidth: CGFloat

    @State private var animate = false
    @State private var naturalWidth: CGFloat = 0

    private var overflow: CGFloat { max(0, naturalWidth - maxWidth) }

    private var displayText: String {
        isHovered
            ? "\(broadcast.title) · \(broadcast.formattedTime(broadcast.startDate))–\(broadcast.formattedTime(broadcast.endDate))"
            : broadcast.title
    }

    var body: some View {
        Text(displayText)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: displayText)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { naturalWidth = geo.size.width }
                        .onChange(of: displayText) { _, _ in naturalWidth = geo.size.width }
                }
            )
            .offset(x: animate ? -overflow : 0)
            .frame(
                width: overflow > 1 ? maxWidth : naturalWidth > 0 ? naturalWidth : nil,
                alignment: .leading
            )
            .clipped()
            .task(id: "\(isHovered)-\(displayText)") {
                if !isHovered {
                    withAnimation(.easeOut(duration: 0.3)) { animate = false }
                    return
                }
                animate = false
                try? await Task.sleep(for: .milliseconds(100))
                guard overflow > 1, !Task.isCancelled else { return }
                let duration = max(2.0, Double(overflow) / 20)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.linear(duration: duration)) { animate = true }
                    try? await Task.sleep(for: .seconds(duration + 1.5))
                    withAnimation(.linear(duration: duration)) { animate = false }
                    try? await Task.sleep(for: .seconds(duration))
                }
            }
    }
}
