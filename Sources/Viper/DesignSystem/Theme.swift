import AppKit
import SwiftUI
import ViperCore

/// Viper's palette. Colour lives in the light behind the glass; surfaces and type stay quiet and neutral.
enum Palette {
    private(set) static var theme: ThemeChoice = .space
    static var isWebsite: Bool { theme == .website }

    static func activate(_ theme: ThemeChoice) { self.theme = theme }

    static var paper: Color { Color(hex: isWebsite ? 0x2D2D2F : 0x07070B) }
    static var surface: Color { Color(hex: isWebsite ? 0x1F1F21 : 0x121219) }
    static var elevated: Color { Color(hex: isWebsite ? 0x28282A : 0x1B1B24) }
    static var ink: Color { Color(hex: isWebsite ? 0xEFEBE3 : 0xF4F4F7) }
    static var muted: Color { Color(hex: isWebsite ? 0x8E8B85 : 0x9A9AAB) }
    static var faint: Color { Color(hex: isWebsite ? 0x6A6761 : 0x62626F) }
    static var line: Color { ink.opacity(isWebsite ? 0.10 : 0.08) }
    static var onAccent: Color { Color(hex: isWebsite ? 0x1D1D1F : 0x0B0B12) }
    static var cream: Color { Color(hex: 0xEBE6DA) }

    // Accents, used for small signals (dots, arcs, tints) rather than fills.
    static var mint: Color { Color(hex: isWebsite ? 0xA7C7A1 : 0x6EE7B7) }
    static var lavender: Color { Color(hex: isWebsite ? 0xEC7B4C : 0x9B8CFF) }
    static var yellow: Color { Color(hex: isWebsite ? 0xD8B56B : 0xFFB547) }
    static var peach: Color { Color(hex: isWebsite ? 0xEC7B4C : 0xFF7A6B) }
    static var blue: Color { Color(hex: isWebsite ? 0x8CA6BF : 0x6CB8FF) }
    static var pink: Color { Color(hex: isWebsite ? 0xC68BAA : 0xF58BD0) }
    static var lime: Color { Color(hex: isWebsite ? 0xAABF79 : 0xB9DF74) }
    static var slate: Color { Color(hex: isWebsite ? 0x8E8B85 : 0x9097AA) }
    static var orange: Color { Color(hex: isWebsite ? 0xEC7B4C : 0xFF8F3F) }
    static var teal: Color { Color(hex: isWebsite ? 0x7CAFA8 : 0x5ED6CB) }

    // Deep, saturated light sources for the aurora behind the glass.
    static var violet: Color { Color(hex: isWebsite ? 0xEC7B4C : 0x6A4DFF) }
    static var indigo: Color { Color(hex: isWebsite ? 0xA8522E : 0x2B2FB8) }
    static var ember: Color { Color(hex: isWebsite ? 0xEC7B4C : 0xFF8A2B) }
    static var rose: Color { Color(hex: isWebsite ? 0xD66646 : 0xFF4F7A) }
    static var ocean: Color { Color(hex: isWebsite ? 0x8CA6BF : 0x2F7BFF) }
    static var lagoon: Color { Color(hex: isWebsite ? 0x7CAFA8 : 0x19B5A6) }

    static var titleGradient: LinearGradient { LinearGradient(colors: [ink, ink.opacity(0.84)], startPoint: .top, endPoint: .bottom) }
    /// Warm-to-violet light used for arcs and meters, like light passing through tinted glass.
    static var spectrum: [Color] { isWebsite ? [orange, orange] : [Color(hex: 0xFFC46B), Color(hex: 0xFF7A6B), Color(hex: 0x9B8CFF)] }

    /// Colours for data series (chart segments, map tiles, legends). Every entry is distinct within a theme, so a
    /// segment can always be matched to its legend. The Website theme uses the warm, desaturated inks of the site.
    static var series: [Color] {
        isWebsite
            ? [Color(hex: 0xEC7B4C), Color(hex: 0xA7C7A1), Color(hex: 0xDDD7C9), Color(hex: 0x8CA6BF),
               Color(hex: 0xD8B56B), Color(hex: 0xC68BAA), Color(hex: 0x7CAFA8), Color(hex: 0xA0706A)]
            : [lavender, mint, peach, blue, yellow, pink, lime, teal]
    }
    /// The series colour for "everything else".
    static var seriesRest: Color { isWebsite ? Color(hex: 0x6A6761) : slate }
    /// The single accent that loaders, meters, and gauges use in the Website theme.
    static var signal: Color { isWebsite ? orange : lavender }

    static func category(_ value: StorageCategory) -> Color {
        switch value {
        case .applications: return series[0]
        case .documents: return series[1]
        case .images: return series[2]
        case .video: return series[3]
        case .audio: return series[4]
        case .archives: return series[5]
        case .development: return series[6]
        case .other: return seriesRest
        }
    }

    static func catalog(_ value: CatalogCategory) -> Color {
        switch value {
        case .developer: return series[6]
        case .ai: return series[0]
        case .audio: return series[4]
        case .video: return series[3]
        case .gaming: return isWebsite ? Color(hex: 0xD66646) : peach
        case .browsers: return series[1]
        case .design: return series[5]
        case .utilities: return seriesRest
        case .productivity: return isWebsite ? Color(hex: 0xDDD7C9) : orange
        case .communication: return series[7]
        }
    }
}

extension Page {
    /// Three light sources the aurora morphs to when this page opens.
    var aura: [Color] {
        switch self {
        case .overview: return [Palette.violet, Palette.ember, Palette.indigo]
        case .storage: return [Palette.ocean, Palette.violet, Palette.lagoon]
        case .uninstaller: return [Palette.violet, Palette.rose, Palette.indigo]
        case .leftovers: return [Palette.ember, Palette.rose, Palette.violet]
        case .memory: return [Palette.teal, Palette.blue, Palette.violet]
        case .updates: return [Palette.lagoon, Palette.ocean, Palette.violet]
        case .privacy: return [Palette.rose, Palette.violet, Palette.ember]
        case .discover: return [Palette.violet, Palette.ocean, Color(hex: 0xE0529C)]
        case .settings: return [Color(hex: 0x4A4F6B), Palette.violet, Palette.indigo]
        }
    }
    var glow: (Color, Color) { (aura[0], aura[1]) }
    fileprivate var auraLayout: [(x: CGFloat, y: CGFloat, scale: CGFloat)] {
        switch self {
        case .overview, .discover: return [(0.86, 0.02, 1.0), (0.18, 0.92, 0.85), (0.42, 0.30, 0.6)]
        case .storage, .updates: return [(0.12, 0.05, 0.95), (0.92, 0.70, 0.9), (0.60, 0.20, 0.55)]
        case .uninstaller, .privacy: return [(0.80, 0.10, 1.0), (0.05, 0.60, 0.8), (0.55, 0.95, 0.6)]
        case .leftovers, .settings: return [(0.95, 0.35, 0.95), (0.20, 0.05, 0.8), (0.45, 0.90, 0.6)]
        case .memory: return [(0.15, 0.08, 0.95), (0.90, 0.80, 0.9), (0.55, 0.45, 0.6)]
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

extension Font {
    /// Title for a section inside a card. Every card header uses this size so sections read as one system.
    static let cardTitle = Font.system(size: 17, weight: .semibold)
}

enum Motion {
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.8)
    static let smooth = Animation.spring(response: 0.55, dampingFraction: 0.88)
    static let hover = Animation.easeOut(duration: 0.2)
}

// MARK: - Grain

/// A tiny tileable noise texture, generated once, that gives glass its frosted tooth.
enum Grain {
    static let image: NSImage = {
        let side = 160
        var state: UInt32 = 0x9E3779B9
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in 0..<(side * side) {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            let value = UInt8(truncatingIfNeeded: state >> 24)
            pixels[index * 4] = value
            pixels[index * 4 + 1] = value
            pixels[index * 4 + 2] = value
            pixels[index * 4 + 3] = 255
        }
        // The image owns a copy of the bytes, so no pointer outlives this closure.
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return NSImage() }
        // Half-size in points so each grain is a single Retina pixel.
        return NSImage(cgImage: cgImage, size: NSSize(width: side / 2, height: side / 2))
    }()
}

struct GrainLayer: View {
    var opacity: Double = 0.05
    var body: some View {
        Image(nsImage: Grain.image).resizable(resizingMode: .tile)
            .opacity(opacity)
            .blendMode(.overlay)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Glass

/// Frosted, grainy glass. Every layer is sized to the surface, so it never changes layout or spills over neighbours.
struct GlassBackground: View {
    var tint: Color?
    var radius: CGFloat = 20
    var selected = false
    var bordered = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Palette.isWebsite ? min(radius, 14) : radius, style: .continuous)
        if Palette.isWebsite {
            shape.fill(selected ? Palette.elevated : Palette.surface)
                .overlay {
                    if bordered { shape.strokeBorder(selected ? Palette.orange.opacity(0.6) : Palette.line, lineWidth: 1) }
                }
        } else {
            shape.fill(Color(hex: 0x14141C).opacity(0.46))
                .overlay {
                    // Milky frost that catches more light at the top.
                    shape.fill(LinearGradient(colors: [Color.white.opacity(0.075), Color.white.opacity(0.02), Color.white.opacity(0.035)],
                                              startPoint: .top, endPoint: .bottom))
                }
                .overlay {
                    if let tint {
                        shape.fill(RadialGradient(colors: [tint.opacity(selected ? 0.30 : 0.16), tint.opacity(0.04), .clear],
                                                  center: .topLeading, startRadius: 0, endRadius: 520))
                    }
                }
                .overlay { GrainLayer(opacity: 0.09).clipShape(shape) }
                .overlay(alignment: .top) {
                    // A thin specular line where light catches the top edge of the pane.
                    if bordered {
                        LinearGradient(colors: [.clear, Color.white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(height: 1).padding(.horizontal, radius)
                    }
                }
                .overlay {
                    if bordered {
                        shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(selected ? 0.34 : 0.20), Color.white.opacity(0.05),
                                                                   Color.white.opacity(0.02), (tint ?? .white).opacity(tint == nil ? 0.06 : 0.22)],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    }
                }
                // Flattened into one texture: scrolling moves a cached image instead of re-blending grain and gradients every frame.
                .drawingGroup()
                // A hairline ledge below the pane gives depth without a blurred shadow (and without darkening the light behind the glass).
                .background { if bordered { shape.stroke(Color.black.opacity(0.45), lineWidth: 1).offset(y: 1.5) } }
        }
    }
}

extension View {
    /// Coloured light placed behind a glass surface. It glows through the frost and spills softly past the edges.
    /// Rendered in a background, so it never affects layout.
    @ViewBuilder func glassAura(_ primary: Color, _ secondary: Color, intensity: Double = 1) -> some View {
        if Palette.isWebsite {
            self
        } else {
            background {
                GeometryReader { geometry in
                    let size = geometry.size
                    let span = max(size.height, min(size.width, 520))
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [primary.opacity(0.9 * intensity), primary.opacity(0.32 * intensity), .clear],
                                                 center: .center, startRadius: 0, endRadius: span * 0.6))
                            .frame(width: span * 1.2, height: span * 1.2)
                            .position(x: size.width * 0.86, y: size.height * 0.08)
                        Circle()
                            .fill(RadialGradient(colors: [secondary.opacity(0.8 * intensity), secondary.opacity(0.24 * intensity), .clear],
                                                 center: .center, startRadius: 0, endRadius: span * 0.48))
                            .frame(width: span * 0.96, height: span * 0.96)
                            .position(x: size.width * 0.12, y: size.height * 0.96)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Buttons

enum ButtonTone {
    case primary, secondary, accent, danger, warning

    var tint: Color? {
        switch self {
        case .primary, .secondary: return nil
        case .accent: return Palette.lavender
        case .danger: return Palette.peach
        case .warning: return Palette.yellow
        }
    }
    var foreground: Color {
        if Palette.isWebsite && self != .primary { return Palette.ink }
        switch self {
        case .primary: return Palette.onAccent
        case .secondary: return Palette.ink
        case .accent: return Color(hex: 0xD9D2FF)
        case .danger: return Color(hex: 0xFFB2A8)
        case .warning: return Color(hex: 0xFFD89A)
        }
    }
}

struct GlowButtonStyle: ButtonStyle {
    var tone: ButtonTone = .primary
    var compact = false

    init(_ tone: ButtonTone = .primary, compact: Bool = false) {
        self.tone = tone
        self.compact = compact
    }

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, tone: tone, compact: compact)
    }

    private struct GlassButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let tone: ButtonTone
        let compact: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            let radius: CGFloat = Palette.isWebsite ? 9 : 100
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            let lit = hovering && enabled
            // Disabled buttons of every tone share one quiet glass look, so an unavailable primary never reads as a grey slab.
            let lookTone = enabled ? tone : .secondary
            configuration.label
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .labelStyle(TightLabelStyle())
                // Button labels never wrap; surrounding text truncates instead.
                .lineLimit(1).fixedSize()
                .padding(.horizontal, compact ? 13 : 18).padding(.vertical, compact ? 7 : 10)
                .foregroundStyle(enabled ? tone.foreground : Palette.muted)
                .background { surface(shape, tone: lookTone, lit: lit) }
                .shadow(color: .black.opacity(!Palette.isWebsite && lookTone == .primary ? 0.3 : 0), radius: !Palette.isWebsite && lookTone == .primary ? 6 : 0, y: !Palette.isWebsite && lookTone == .primary ? 3 : 0)
                .scaleEffect(configuration.isPressed && enabled ? 0.97 : 1)
                .offset(y: lit && !reduceMotion && !Palette.isWebsite ? -1 : 0)
                .opacity(enabled ? 1 : 0.6)
                .animation(reduceMotion ? nil : Motion.snappy, value: configuration.isPressed)
                .animation(reduceMotion ? nil : Motion.hover, value: hovering)
                .contentShape(shape)
                .onHover { hovering = $0 }
                .modifier(FocusHalo(kind: .rounded(radius)))
        }

        @ViewBuilder private func surface(_ shape: RoundedRectangle, tone: ButtonTone, lit: Bool) -> some View {
            if Palette.isWebsite {
                switch tone {
                case .primary:
                    shape.fill(lit ? Color.white : Palette.cream)
                case .secondary:
                    shape.fill(lit ? Palette.elevated : Color.clear)
                        .overlay { shape.strokeBorder(Palette.ink.opacity(lit ? 0.30 : 0.18), lineWidth: 1) }
                case .accent, .danger, .warning:
                    let tint = tone.tint ?? Palette.orange
                    shape.fill(tint.opacity(lit ? 0.22 : 0.12))
                        .overlay { shape.strokeBorder(tint.opacity(lit ? 0.75 : 0.5), lineWidth: 1) }
                }
            } else {
                switch tone {
                case .primary:
                    // Porcelain: bright frosted white, like a lit pane of glass.
                    shape.fill(LinearGradient(colors: [Color.white, Color(hex: lit ? 0xEFEDF6 : 0xE3E1EC)], startPoint: .top, endPoint: .bottom))
                        .overlay { shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5) }
                case .secondary:
                    shape.fill(Color.white.opacity(lit ? 0.12 : 0.07))
                        .overlay {
                            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(lit ? 0.32 : 0.2), Color.white.opacity(0.04)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        }
                case .accent, .danger, .warning:
                    let tint = tone.tint ?? .white
                    shape.fill(LinearGradient(colors: [tint.opacity(lit ? 0.3 : 0.2), tint.opacity(lit ? 0.16 : 0.1)], startPoint: .top, endPoint: .bottom))
                        .overlay {
                            shape.strokeBorder(LinearGradient(colors: [tint.opacity(lit ? 0.7 : 0.5), tint.opacity(0.12)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        }
                }
            }
        }
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 11, weight: .semibold))
            configuration.title
        }
    }
}

/// Visible keyboard focus for custom controls. The system ring is not drawn for these button styles.
struct FocusHalo: ViewModifier {
    enum Kind { case capsule, circle, rounded(CGFloat) }
    var kind: Kind
    @Environment(\.isFocused) private var focused

    func body(content: Content) -> some View {
        content.overlay {
            if focused {
                ring.padding(-3).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var ring: some View {
        let color = Palette.isWebsite ? Palette.orange : Color.white
        switch kind {
        case .capsule:
            Capsule(style: .continuous).strokeBorder(color, lineWidth: 2)
        case .circle:
            Circle().strokeBorder(color, lineWidth: 2)
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(color, lineWidth: 2)
        }
    }
}

/// Small borderless icon button that lights up on hover.
struct IconButtonStyle: ButtonStyle {
    var tint: Color = .white
    func makeBody(configuration: Configuration) -> some View { IconButtonBody(configuration: configuration, tint: tint) }
    private struct IconButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let tint: Color
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            let radius: CGFloat = Palette.isWebsite ? 8 : 100
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            configuration.label
                .foregroundStyle(hovering && enabled ? tint : Palette.muted)
                .frame(width: 28, height: 28)
                .background(shape.fill(Palette.isWebsite ? Palette.elevated.opacity(hovering && enabled ? 1 : 0) : Color.white.opacity(hovering && enabled ? 0.09 : 0)))
                .overlay(shape.strokeBorder(Palette.isWebsite ? Palette.line.opacity(hovering && enabled ? 1 : 0) : Color.white.opacity(hovering && enabled ? 0.12 : 0), lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.88 : 1)
                .opacity(enabled ? 1 : 0.35)
                .contentShape(shape)
                .onHover { hovering = $0 }
                .animation(Motion.snappy, value: configuration.isPressed)
                .animation(Motion.hover, value: hovering)
                .modifier(FocusHalo(kind: .rounded(radius)))
        }
    }
}

/// Text-only action (Select all, Clear, Manage sources).
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { LinkButtonBody(configuration: configuration) }
    private struct LinkButtonBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(enabled ? (hovering ? 1 : 0.68) : 0.3))
                .underline(hovering && enabled, color: Palette.ink.opacity(0.4))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { hovering = $0 }
                .animation(Motion.hover, value: hovering)
                .modifier(FocusHalo(kind: .rounded(6)))
        }
    }
}

// MARK: - Surfaces

/// Tracks the pointer separately so only the light layer re-renders while the mouse moves.
private final class PointerTracker: ObservableObject {
    @Published var location: CGPoint?
}

/// A soft sheen that follows the pointer across glass, and brightens the rim nearest to it.
private struct SheenLayer: View {
    @ObservedObject var tracker: PointerTracker
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            if let point = tracker.location {
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.07), .clear], center: .center, startRadius: 0, endRadius: 240))
                    .frame(width: 480, height: 480).position(point)
                shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                    .mask(Circle().fill(RadialGradient(colors: [.white, .clear], center: .center, startRadius: 0, endRadius: 160))
                        .frame(width: 320, height: 320).position(point))
            }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

/// Entrance for surfaces: a short rise and fade the first time a view appears.
struct RiseIn: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true } else { withAnimation(Motion.smooth.delay(delay)) { shown = true } }
            }
    }
}

extension View {
    func riseIn(delay: Double = 0) -> some View { modifier(RiseIn(delay: delay)) }

    /// A small frosted tile behind an icon, lit from below by its colour.
    @ViewBuilder func glowTile(_ color: Color, radius: CGFloat = 10, glow: Bool = true) -> some View {
        if Palette.isWebsite {
            self.foregroundStyle(Palette.ink)
                .background {
                    let shape = RoundedRectangle(cornerRadius: min(radius, 10), style: .continuous)
                    shape.fill(Color.clear)
                        .overlay { shape.strokeBorder(Palette.ink.opacity(glow ? 0.28 : 0.18), lineWidth: 1) }
                }
        } else {
            self.foregroundStyle(Color.white.opacity(0.94))
                .background {
                    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                    shape.fill(Color.white.opacity(0.06))
                        .overlay {
                            shape.fill(RadialGradient(colors: [color.opacity(glow ? 0.55 : 0.38), color.opacity(0.08), .clear],
                                                      center: .bottom, startRadius: 0, endRadius: radius * 5))
                        }
                        .overlay {
                            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0.04), color.opacity(0.35)],
                                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        }
                }
                .shadow(color: color.opacity(glow ? 0.22 : 0), radius: glow ? 14 : 0, y: glow ? 4 : 0)
        }
    }

    /// A frosted notice with a hint of colour.
    func noticeBackground(_ color: Color, radius: CGFloat = 14) -> some View {
        self.background {
            let shape = RoundedRectangle(cornerRadius: Palette.isWebsite ? min(radius, 10) : radius, style: .continuous)
            if Palette.isWebsite {
                shape.fill(Palette.surface)
                    .overlay { shape.strokeBorder(color.opacity(0.45), lineWidth: 1) }
            } else {
                shape.fill(Color.white.opacity(0.04))
                    .overlay { shape.fill(RadialGradient(colors: [color.opacity(0.16), .clear], center: .leading, startRadius: 0, endRadius: 420)) }
                    .overlay { shape.strokeBorder(LinearGradient(colors: [color.opacity(0.35), Color.white.opacity(0.06)], startPoint: .leading, endPoint: .trailing), lineWidth: 1) }
            }
        }
    }

    /// Recessed glass well for lists inside a card.
    func glassPanel(radius: CGFloat = 16) -> some View {
        self.background {
            let shape = RoundedRectangle(cornerRadius: Palette.isWebsite ? min(radius, 12) : radius, style: .continuous)
            if Palette.isWebsite {
                shape.fill(Palette.surface).overlay { shape.strokeBorder(Palette.line, lineWidth: 1) }
            } else {
                shape.fill(Color.black.opacity(0.18))
                    .overlay { shape.strokeBorder(LinearGradient(colors: [Color.black.opacity(0.25), Color.white.opacity(0.07)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Palette.isWebsite ? min(radius, 12) : radius, style: .continuous))
    }

    /// Hover and selection wash for list rows.
    func rowHighlight(hovering: Bool, selected: Bool = false, tint: Color = .white) -> some View {
        self.background {
            let shape = RoundedRectangle(cornerRadius: Palette.isWebsite ? 8 : 12, style: .continuous)
            if Palette.isWebsite {
                shape.fill(Palette.elevated.opacity(selected ? 1 : (hovering ? 0.7 : 0)))
                    .overlay { shape.strokeBorder(Palette.line.opacity(selected || hovering ? 1 : 0), lineWidth: 1) }
                    .animation(Motion.hover, value: hovering)
                    .animation(Motion.snappy, value: selected)
            } else {
                shape.fill(Color.white.opacity(selected ? 0.07 : (hovering ? 0.045 : 0)))
                    .overlay { shape.strokeBorder(Color.white.opacity(selected ? 0.14 : (hovering ? 0.07 : 0)), lineWidth: 1) }
                    .animation(Motion.hover, value: hovering)
                    .animation(Motion.snappy, value: selected)
            }
        }
    }
}

private struct WebsiteCornerMarks: View {
    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 12
            let length: CGFloat = 10
            var path = Path()
            path.move(to: CGPoint(x: inset, y: inset + length)); path.addLine(to: CGPoint(x: inset, y: inset)); path.addLine(to: CGPoint(x: inset + length, y: inset))
            path.move(to: CGPoint(x: size.width - inset - length, y: inset)); path.addLine(to: CGPoint(x: size.width - inset, y: inset)); path.addLine(to: CGPoint(x: size.width - inset, y: inset + length))
            path.move(to: CGPoint(x: inset, y: size.height - inset - length)); path.addLine(to: CGPoint(x: inset, y: size.height - inset)); path.addLine(to: CGPoint(x: inset + length, y: size.height - inset))
            path.move(to: CGPoint(x: size.width - inset - length, y: size.height - inset)); path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset)); path.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset - length))
            context.stroke(path, with: .color(Palette.ink.opacity(0.55)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct Card<Content: View>: View {
    var color: Color?
    var interactive = true
    @ViewBuilder var content: Content
    @StateObject private var tracker = PointerTracker()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(color: Color? = nil, interactive: Bool = true, @ViewBuilder content: () -> Content) {
        self.color = color
        self.interactive = interactive
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassBackground(tint: color))
            .overlay {
                if Palette.isWebsite { WebsiteCornerMarks() }
                else { SheenLayer(tracker: tracker, radius: 20) }
            }
            .onContinuousHover { phase in
                guard interactive, !reduceMotion, !Palette.isWebsite else { return }
                switch phase {
                case .active(let point): tracker.location = point
                case .ended: withAnimation(Motion.hover) { tracker.location = nil }
                }
            }
            .riseIn()
    }
}

struct Tag: View {
    let text: String
    var color: Color = Palette.slate
    var pulse = false
    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Palette.isWebsite ? 6 : 100, style: .continuous)
        HStack(spacing: 6) {
            if color != Palette.slate || pulse {
                if Palette.isWebsite {
                    // The site's square mark, blinking like a cursor while something is live.
                    Swatch(color: color, size: 5).blink(pulse && !reduceMotion)
                } else {
                    Circle().fill(color).frame(width: 5, height: 5)
                        .shadow(color: color.opacity(0.9), radius: lit ? 5 : 2)
                        .opacity(pulse ? (lit ? 1 : 0.35) : 1)
                        .onAppear {
                            guard pulse, !reduceMotion else { lit = true; return }
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { lit = true }
                        }
                }
            }
            Text(text).font(.system(size: 9.5, weight: .semibold)).tracking(0.9)
        }
        .foregroundStyle(Palette.ink.opacity(0.82))
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(shape.fill(Palette.isWebsite ? Color.clear : Color.white.opacity(0.06)))
        .overlay(shape.strokeBorder(Palette.isWebsite ? Palette.line : Color.white.opacity(0.1), lineWidth: 1))
        .fixedSize()
    }
}

struct PageHeading<Actions: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var actions: Actions

    init(_ title: String, subtitle: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 14) {
                Text(title).font(.system(size: Palette.isWebsite ? 29 : 28, weight: Palette.isWebsite ? .semibold : .medium)).tracking(Palette.isWebsite ? -0.9 : -0.6)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                actions
            }
            if let subtitle {
                Text(subtitle).font(Palette.isWebsite ? .system(size: 13, design: .serif) : .system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(2)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .riseIn()
    }
}

extension PageHeading where Actions == EmptyView {
    init(_ title: String, subtitle: String? = nil) { self.init(title, subtitle: subtitle) { EmptyView() } }
}

struct InfoLine: View {
    let text: String
    var icon = "info.circle"
    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon).foregroundStyle(Palette.ink.opacity(0.45))
        }
        .font(Palette.isWebsite ? .system(size: 12.5, design: .serif) : .system(size: 12)).foregroundStyle(Palette.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct EmptyPanel: View {
    var framed = true
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.isWebsite ? Palette.orange : Palette.ink.opacity(0.9))
                .frame(width: 76, height: 76)
                .background {
                    if Palette.isWebsite {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.clear)
                            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1) }
                    } else {
                        Circle().fill(Color.white.opacity(0.06))
                            .overlay { GrainLayer(opacity: 0.1).clipShape(Circle()) }
                            .overlay { Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
                    }
                }
                .background {
                    if !Palette.isWebsite {
                        // A soft two-tone halo behind the frosted disc.
                        ZStack {
                            Circle().fill(RadialGradient(colors: [Palette.violet.opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 110))
                                .frame(width: 220, height: 220).offset(x: 22, y: -14)
                            Circle().fill(RadialGradient(colors: [Palette.ember.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 90))
                                .frame(width: 180, height: 180).offset(x: -26, y: 20)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .padding(.vertical, 10)
            Text(title).font(.system(size: 19, weight: Palette.isWebsite ? .semibold : .medium)).foregroundStyle(Palette.ink)
            Text(detail).font(Palette.isWebsite ? .system(size: 13.5, design: .serif) : .system(size: 13)).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 430)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
        .background { if framed { GlassBackground(radius: 20) } }
        .overlay { if framed && Palette.isWebsite { WebsiteCornerMarks() } }
        .riseIn()
    }
}

// MARK: - Data marks

/// A legend or status marker. Space: a small dot that glows in its colour. Website: a flat square, like the site's orange mark.
struct Swatch: View {
    let color: Color
    var size: CGFloat = 7
    var glow: CGFloat = 0
    var glowOpacity: Double = 1

    var body: some View {
        if Palette.isWebsite {
            RoundedRectangle(cornerRadius: max(1, size * 0.2), style: .continuous).fill(color).frame(width: size, height: size)
        } else {
            Circle().fill(color).frame(width: size, height: size).shadow(color: color.opacity(glowOpacity), radius: glow)
        }
    }
}

/// A hard on/off blink, like a text cursor. The Website theme uses it where Space uses a soft glow pulse.
private struct Blink: ViewModifier {
    var active: Bool
    var period: Double = 0.55
    func body(content: Content) -> some View {
        if active {
            TimelineView(.periodic(from: .now, by: period)) { context in
                content.opacity(Int(context.date.timeIntervalSinceReferenceDate / period) % 2 == 0 ? 1 : 0.2)
            }
        } else {
            content
        }
    }
}

extension View {
    func blink(_ active: Bool = true) -> some View { modifier(Blink(active: active)) }
}

/// Website-theme track for bars and meters: a flat recessed rule with a hairline edge.
struct FlatTrack: View {
    var radius: CGFloat = 3
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(Palette.ink.opacity(0.08)).overlay { shape.strokeBorder(Palette.line, lineWidth: 1) }
    }
}

/// Website-theme ruler marks at each quarter, cut into a bar so it reads like a drafting scale.
private struct QuarterTicks: View {
    var body: some View {
        GeometryReader { geometry in
            ForEach(1..<4, id: \.self) { index in
                Rectangle().fill(Palette.surface).frame(width: 1.5)
                    .position(x: geometry.size.width * CGFloat(index) / 4, y: geometry.size.height / 2)
                    .frame(height: geometry.size.height)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A slim meter: a recessed track with a softly lit, warm-to-violet fill that grows in when it appears.
/// In the Website theme it's a flat, square-ended scale with quarter ticks and a single solid ink.
struct GlowMeter: View {
    let fraction: Double
    var colors: [Color] = Palette.spectrum
    var height: CGFloat = 10
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let width = max(height, geometry.size.width * min(1, max(0, fraction)) * (shown ? 1 : 0))
            if Palette.isWebsite {
                ZStack(alignment: .leading) {
                    FlatTrack(radius: 2)
                    RoundedRectangle(cornerRadius: 2, style: .continuous).fill(colors.last ?? Palette.signal)
                        .frame(width: width)
                        .opacity(shown ? 1 : 0)
                    QuarterTicks()
                }
            } else {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.3))
                        .overlay { Capsule().strokeBorder(LinearGradient(colors: [Color.black.opacity(0.3), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .overlay { Capsule().fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)) }
                        .frame(width: width)
                        .shadow(color: (colors.last ?? .white).opacity(0.35), radius: 8)
                        .opacity(shown ? 1 : 0)
                }
            }
        }
        .frame(height: height)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.spring(response: 1.1, dampingFraction: 0.86).delay(0.15)) { shown = true } }
        }
    }
}

/// Website-theme dial face: fine minute ticks inside the ring, with longer, brighter ticks at each quarter.
private struct DialTicks: View {
    let inset: CGFloat
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2 - inset
            for index in 0..<48 {
                let major = index % 12 == 0
                let angle = Double(index) / 48 * 2 * .pi - .pi / 2
                let inner = outer - (major ? 7 : 3.5)
                var tick = Path()
                tick.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * inner, y: center.y + CGFloat(sin(angle)) * inner))
                tick.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * outer, y: center.y + CGFloat(sin(angle)) * outer))
                context.stroke(tick, with: .color(Palette.ink.opacity(major ? 0.6 : 0.22)), lineWidth: major ? 1.5 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A circular gauge: frosted dial with a lit arc, inspired by instrument faces.
/// In the Website theme it's a drafted instrument: a flat ring, square-ended solid arc, and a ticked face.
struct RingGauge<Center: View>: View {
    let fraction: Double
    var size: CGFloat = 168
    var lineWidth: CGFloat = 9
    var colors: [Color] = Palette.spectrum
    @ViewBuilder var center: Center
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let value = min(1, max(0, fraction)) * (shown ? 1 : 0)
        ZStack {
            if Palette.isWebsite {
                // Ticks need room to read; small gauges keep just the ring.
                if size >= 90 { DialTicks(inset: lineWidth / 2 + 5) }
                Circle().stroke(Palette.ink.opacity(0.1), lineWidth: lineWidth)
                Circle().strokeBorder(Palette.line, lineWidth: 1).padding(-lineWidth / 2)
                Circle().trim(from: 0, to: value)
                    .stroke(colors.last ?? Palette.signal, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.1), Color(hex: 0x101017).opacity(0.85)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: size * 0.6))
                    .overlay { GrainLayer(opacity: 0.1).clipShape(Circle()) }
                    .overlay { Circle().strokeBorder(LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
                    .padding(lineWidth + 6)
                Circle().stroke(Color.white.opacity(0.06), lineWidth: lineWidth)
                Circle().trim(from: 0, to: value)
                    .stroke(AngularGradient(colors: colors + [colors.first ?? .white], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: (colors.first ?? .white).opacity(0.45), radius: 10)
            }
            center
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.spring(response: 1.3, dampingFraction: 0.85).delay(0.2)) { shown = true } }
        }
    }
}

// MARK: - Backdrops

/// Aurora of deep light behind everything. It morphs only when the page changes, so an idle Viper stays idle.
struct AmbientBackground: View {
    let page: Page
    var body: some View {
        if Palette.isWebsite {
            Palette.paper.ignoresSafeArea().accessibilityHidden(true)
        } else {
            GeometryReader { geometry in
                let size = geometry.size
                let base = max(size.width, size.height)
                ZStack {
                    Palette.paper
                    ForEach(0..<3, id: \.self) { index in
                        let color = page.aura[index]
                        let spot = page.auraLayout[index]
                        let diameter = base * 0.95 * spot.scale
                        Circle()
                            .fill(RadialGradient(colors: [color.opacity(index == 2 ? 0.34 : 0.5), color.opacity(0.14), .clear],
                                                 center: .center, startRadius: 0, endRadius: diameter / 2))
                            .frame(width: diameter, height: diameter)
                            .position(x: size.width * spot.x, y: size.height * spot.y)
                    }
                    // Soft vignette keeps edges deep and text legible.
                    RadialGradient(colors: [.clear, Color.black.opacity(0.55)], center: .center, startRadius: base * 0.2, endRadius: base * 0.8)
                    GrainLayer(opacity: 0.07)
                }
            }
            .drawingGroup()
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }
}

/// Background for sheets: deep canvas with two soft light sources.
struct SheetBackground: View {
    var tint: Color = Palette.violet
    var body: some View {
        if Palette.isWebsite {
            Palette.paper.ignoresSafeArea()
        } else {
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    Palette.paper
                    Circle().fill(RadialGradient(colors: [tint.opacity(0.42), tint.opacity(0.1), .clear], center: .center, startRadius: 0, endRadius: 320))
                        .frame(width: 640, height: 640).position(x: size.width * 0.9, y: 0)
                    Circle().fill(RadialGradient(colors: [Palette.indigo.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 280))
                        .frame(width: 560, height: 560).position(x: 0, y: size.height)
                    GrainLayer(opacity: 0.07)
                }
            }
            .drawingGroup()
            .ignoresSafeArea()
        }
    }
}

struct GlowDivider: View {
    var vertical = false
    var body: some View {
        let gradient = Palette.isWebsite
            ? LinearGradient(colors: [Palette.line, Palette.line], startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [.clear, Color.white.opacity(0.1), .clear], startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing)
        if vertical { Rectangle().fill(gradient).frame(width: 1) } else { Rectangle().fill(gradient).frame(height: 1) }
    }
}

/// Small section label.
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(Palette.muted)
    }
}
