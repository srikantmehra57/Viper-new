import SwiftUI
import ViperCore

/// A slim progress bar on recessed glass. A soft sheen travels along the fill while work is active,
/// so a package manager that goes quiet still visibly reads as working.
/// In the Website theme it's a flat, square-ended bar whose fill carries moving drafting hatches instead.
struct ActivityBar: View {
    let fraction: Double
    var active = true
    var height: CGFloat = 8
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = max(height, geometry.size.width * min(1, max(0, fraction)))
            if Palette.isWebsite {
                ZStack(alignment: .leading) {
                    FlatTrack(radius: 2)
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Palette.signal)
                        .overlay {
                            if active && !reduceMotion { MovingHatch().clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous)) }
                        }
                        .frame(width: width)
                        .animation(.spring(response: 0.8, dampingFraction: 0.9), value: fraction)
                }
            } else {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.3))
                        .overlay { Capsule().strokeBorder(LinearGradient(colors: [Color.black.opacity(0.3), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
                    Capsule().fill(LinearGradient(colors: Palette.spectrum, startPoint: .leading, endPoint: .trailing))
                        .overlay { Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)) }
                        .overlay {
                            if active && !reduceMotion {
                                LinearGradient(colors: [.clear, Palette.ink.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 70)
                                    .offset(x: sweep ? width : -70)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .clipShape(Capsule())
                            }
                        }
                        .frame(width: width)
                        .animation(.spring(response: 0.8, dampingFraction: 0.9), value: fraction)
                }
            }
        }
        .frame(height: height)
        .onAppear {
            guard active, !reduceMotion, !Palette.isWebsite else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { sweep = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

/// Diagonal hatching that drifts along a Website-theme progress fill, like a drafting pattern in motion.
private struct MovingHatch: View {
    private static let spacing: CGFloat = 7
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let phase = CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.7) / 0.7) * Self.spacing
            Canvas { canvas, size in
                var path = Path()
                var x = -size.height + phase - Self.spacing
                while x < size.width + Self.spacing {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += Self.spacing
                }
                canvas.stroke(path, with: .color(Palette.onAccent.opacity(0.28)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Live feedback for one install or update: which step it is on, a progress bar, what the package manager
/// is doing, how much has downloaded, and how long it has been running.
struct OperationProgressView: View {
    let progress: OperationProgress
    let startedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(OperationProgress.Phase.allCases, id: \.self) { phase in
                    PhaseStep(phase: phase, current: progress.phase)
                    if phase != .verifying {
                        Rectangle().fill(phase < progress.phase ? Palette.ink.opacity(0.5) : Palette.line)
                            .frame(height: 1).frame(maxWidth: 28).padding(.horizontal, 6)
                    }
                }
                Spacer(minLength: 8)
                if let percent = progress.downloadFraction, progress.phase == .downloading {
                    Text("\(Int((percent * 100).rounded()))%").font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            ActivityBar(fraction: progress.overallFraction)
            HStack(spacing: 10) {
                Text(progress.detail.isEmpty ? progress.phase.title + "…" : progress.detail)
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                    .contentTransition(.opacity)
                Spacer(minLength: 8)
                if let received = progress.downloadedBytes, progress.phase == .downloading {
                    Text(bytes(received) + " received")
                        .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(Palette.ink.opacity(0.8))
                        .contentTransition(.numericText())
                }
                if let startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(Self.elapsed(from: startedAt, to: context.date))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.faint)
                    }
                }
            }
        }
        .padding(14)
        .background {
            let shape = RoundedRectangle(cornerRadius: Palette.isWebsite ? 10 : 14, style: .continuous)
            if Palette.isWebsite {
                shape.fill(Palette.surface).overlay { shape.strokeBorder(Palette.line, lineWidth: 1) }
            } else {
                shape.fill(Color.black.opacity(0.2))
                    .overlay { shape.strokeBorder(LinearGradient(colors: [Color.black.opacity(0.25), Color.white.opacity(0.07)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
            }
        }
        .animation(Motion.smooth, value: progress)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .combine)
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct PhaseStep: View {
    let phase: OperationProgress.Phase
    let current: OperationProgress.Phase
    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let done = phase < current
        let active = phase == current
        HStack(spacing: 6) {
            ZStack {
                if Palette.isWebsite {
                    // Square steps with the site's orange for the live one, blinking rather than glowing.
                    let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    shape.strokeBorder(Palette.ink.opacity(done || active ? 0 : 0.25), lineWidth: 1)
                    if done {
                        shape.fill(Palette.cream)
                        Image(systemName: "checkmark").font(.system(size: 6.5, weight: .heavy)).foregroundStyle(Palette.onAccent)
                    } else if active {
                        shape.strokeBorder(Palette.signal.opacity(0.6), lineWidth: 1)
                        RoundedRectangle(cornerRadius: 1, style: .continuous).fill(Palette.signal).padding(3.5)
                            .blink(!reduceMotion)
                    }
                } else {
                    Circle().strokeBorder(Palette.ink.opacity(done || active ? 0 : 0.2), lineWidth: 1)
                    if done {
                        Circle().fill(Palette.ink)
                        Image(systemName: "checkmark").font(.system(size: 6.5, weight: .heavy)).foregroundStyle(Palette.onAccent)
                    } else if active {
                        Circle().fill(Palette.yellow.opacity(0.25))
                        Circle().fill(Palette.yellow).padding(3)
                            .shadow(color: Palette.yellow, radius: lit ? 5 : 1)
                            .opacity(lit ? 1 : 0.55)
                    }
                }
            }
            .frame(width: 13, height: 13)
            Text(phase.title).font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Palette.ink : (done ? Palette.ink.opacity(0.7) : Palette.faint))
        }
        .onAppear { startPulse() }
        .onChange(of: current) { startPulse() }
    }

    private func startPulse() {
        guard phase == current, !reduceMotion, !Palette.isWebsite else { lit = phase == current; return }
        lit = false
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { lit = true }
    }
}

/// Shown for items waiting their turn in a queue.
struct QueueWaitingLine: View {
    let position: Int
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock").font(.system(size: 11))
            Text(position <= 1 ? "Up next · starts when the current one finishes" : "Waiting · \(position) in line")
            Spacer()
        }
        .font(.system(size: 11.5)).foregroundStyle(Palette.muted)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Palette.isWebsite ? 9 : 12, style: .continuous).fill(Palette.isWebsite ? Palette.elevated : Color.white.opacity(0.035)))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Overall progress for a queue: finished items plus the active item's estimated completion.
struct QueueSummaryBar: View {
    let finished: Int
    let total: Int
    let current: OperationProgress?
    let title: String

    var body: some View {
        let fraction = total == 0 ? 0 : (Double(finished) + (current?.overallFraction ?? 0)) / Double(total)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(finished) of \(total) done").font(.system(size: 11)).monospacedDigit().foregroundStyle(Palette.muted)
                    .contentTransition(.numericText())
            }
            ActivityBar(fraction: fraction, height: 6)
        }
    }
}

/// A radar-style pulse shown while a scan runs. In the Website theme it's the site's stepping-square loader instead.
struct ScanPulse: View {
    var color: Color = Palette.mint
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if Palette.isWebsite {
                StepLoader()
            } else {
                ZStack {
                    Circle().strokeBorder(color.opacity(0.18), lineWidth: 2)
                    Circle().trim(from: 0, to: 0.3)
                        .stroke(AngularGradient(colors: [color.opacity(0), color], center: .center), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(spin ? 360 : 0))
                    Circle().fill(color).frame(width: 5, height: 5).shadow(color: color, radius: 4)
                }
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true }
                }
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel("Working")
    }
}

/// Four squares in a 2×2 grid; the lit square steps clockwise in the site's orange, with a fading trail.
/// It uses one accent regardless of page, as the Website theme does everywhere. Reduce Motion holds it still.
private struct StepLoader: View {
    private static let order = [0, 1, 3, 2]
    private static let period = 0.16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            grid(step: 0)
        } else {
            TimelineView(.periodic(from: .now, by: Self.period)) { context in
                grid(step: Int(context.date.timeIntervalSinceReferenceDate / Self.period))
            }
        }
    }

    private func grid(step: Int) -> some View {
        let lit = Self.order[step % 4]
        let trail = Self.order[(step + 3) % 4]
        return VStack(spacing: 3) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<2, id: \.self) { column in
                        let index = row * 2 + column
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(index == lit ? Palette.signal : (index == trail && !reduceMotion ? Palette.signal.opacity(0.4) : Palette.ink.opacity(0.18)))
                            .frame(width: 7, height: 7)
                    }
                }
            }
        }
    }
}
