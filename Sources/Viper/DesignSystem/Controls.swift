import AppKit
import SwiftUI

/// Shared frosted field surface for inputs.
private struct FieldSurface: View {
    var focused = false
    var hovering = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Palette.isWebsite ? 10 : 12, style: .continuous)
        if Palette.isWebsite {
            shape.fill(focused || hovering ? Palette.elevated : Palette.surface)
                .overlay { shape.strokeBorder(focused ? Palette.orange.opacity(0.8) : Palette.line, lineWidth: 1) }
        } else {
            shape.fill(Color.black.opacity(focused ? 0.22 : 0.16))
                .overlay { shape.fill(Color.white.opacity(focused ? 0.05 : (hovering ? 0.04 : 0.025))) }
                .overlay {
                    shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(focused ? 0.34 : (hovering ? 0.16 : 0.1)), Color.white.opacity(focused ? 0.14 : 0.05)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .shadow(color: Color.white.opacity(focused ? 0.06 : 0), radius: focused ? 12 : 0)
        }
    }
}

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium))
                .foregroundStyle(focused ? Palette.ink : Palette.muted)
            TextField(placeholder, text: $text).textFieldStyle(.plain).focused($focused)
                .font(.system(size: 13)).accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted).help("Clear search").accessibilityLabel("Clear search")
                    .transition(.scale.combined(with: .opacity))
            }
        }.padding(.horizontal, 13).padding(.vertical, 10)
            .background(FieldSurface(focused: focused, hovering: hovering))
            .animation(reduceMotion ? nil : Motion.hover, value: focused)
            .animation(reduceMotion ? nil : Motion.snappy, value: text.isEmpty)
            .onHover { hovering = $0 }
    }
}

struct ViperCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        CheckboxBody(configuration: configuration)
    }

    private struct CheckboxBody: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false
        var body: some View {
            let on = configuration.isOn
            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
            Button { configuration.isOn.toggle() } label: {
                HStack(spacing: 9) {
                    ZStack {
                        if Palette.isWebsite {
                            shape.fill(on ? Palette.cream : Color.clear)
                            shape.strokeBorder(on ? Palette.cream : Palette.ink.opacity(hovering ? 0.3 : 0.18), lineWidth: 1)
                        } else {
                            shape.fill(Color.black.opacity(0.2))
                            shape.strokeBorder(LinearGradient(colors: [Color.black.opacity(0.3), Color.white.opacity(hovering ? 0.3 : 0.18)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                            shape.fill(LinearGradient(colors: [Color.white, Color(hex: 0xDCDAE6)], startPoint: .top, endPoint: .bottom))
                                .opacity(on ? 1 : 0)
                        }
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Palette.onAccent)
                            .scaleEffect(on ? 1 : 0.3).opacity(on ? 1 : 0)
                    }
                    .frame(width: 18, height: 18)
                    .shadow(color: .white.opacity(Palette.isWebsite ? 0 : (on ? 0.18 : 0)), radius: on && !Palette.isWebsite ? 6 : 0)
                    configuration.label.font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(on ? 1 : 0.82))
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(enabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : Motion.snappy, value: on)
            .animation(reduceMotion ? nil : Motion.hover, value: hovering)
            .modifier(FocusHalo(kind: .rounded(8)))
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(on ? "On" : "Off")
        }
    }
}

struct ViperSelect<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(String, Value)]
    @State private var expanded = false
    @State private var hovering = false
    var body: some View {
        Button { expanded.toggle() } label: {
            HStack {
                Text(options.first(where: { $0.1 == selection })?.0 ?? title).lineLimit(1)
                Spacer(minLength: 10)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.muted)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 11)
                .background(FieldSurface(focused: expanded, hovering: hovering))
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .animation(Motion.snappy, value: expanded)
                .animation(Motion.hover, value: hovering)
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .modifier(FocusHalo(kind: .rounded(12)))
            .accessibilityLabel(title).accessibilityValue(options.first(where: { $0.1 == selection })?.0 ?? "")
            .accessibilityAddTraits(.isButton)
            .popover(isPresented: $expanded, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(options.indices, id: \.self) { index in
                        SelectOption(title: options[index].0, selected: options[index].1 == selection) {
                            selection = options[index].1
                            expanded = false
                        }
                    }
                }.padding(6).background(Palette.elevated).foregroundStyle(Palette.ink)
            }
    }
}

private struct SelectOption: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
            }.font(.system(size: 12, weight: selected ? .semibold : .regular)).padding(.horizontal, 10).padding(.vertical, 8).frame(minWidth: 190)
                .foregroundStyle(Palette.isWebsite && selected ? Palette.onAccent : Palette.ink)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Palette.isWebsite ? (selected ? Palette.cream : Palette.elevated.opacity(hovering ? 1 : 0)) : Color.white.opacity(selected ? 0.1 : (hovering ? 0.06 : 0))))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let radius: CGFloat = Palette.isWebsite ? 8 : 100
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Palette.onAccent : (hovering ? Palette.ink : Palette.ink.opacity(0.66)))
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background {
                    ZStack {
                        shape.fill(Palette.isWebsite ? (selected ? Palette.cream : Palette.elevated.opacity(hovering ? 1 : 0)) : Color.white.opacity(hovering ? 0.08 : 0.04))
                        shape.strokeBorder(Palette.isWebsite ? Palette.line.opacity(selected ? 0 : 1) : Color.white.opacity(hovering ? 0.16 : 0.08), lineWidth: 1)
                        if !Palette.isWebsite {
                            shape.fill(LinearGradient(colors: [Color.white, Color(hex: 0xDCDAE6)], startPoint: .top, endPoint: .bottom))
                                .opacity(selected ? 1 : 0)
                        }
                    }
                }
                .shadow(color: .black.opacity(selected && !Palette.isWebsite ? 0.3 : 0), radius: selected && !Palette.isWebsite ? 6 : 0, y: selected && !Palette.isWebsite ? 3 : 0)
                .contentShape(shape)
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .modifier(FocusHalo(kind: .rounded(radius)))
            .animation(reduceMotion ? nil : Motion.snappy, value: selected)
            .animation(reduceMotion ? nil : Motion.hover, value: hovering)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wraps items onto new lines, keeping consistent spacing between items and rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1] = (last.indices + [index], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}

/// Expandable section whose whole header row is clickable. macOS's DisclosureGroup only responds to its small triangle.
struct Disclosure<Content: View>: View {
    let title: String
    private let external: Binding<Bool>?
    private let content: () -> Content
    @State private var expandedLocally = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, isExpanded: Binding<Bool>? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.external = isExpanded
        self.content = content
    }

    private var expanded: Bool { external?.wrappedValue ?? expandedLocally }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : Motion.snappy) {
                    if let external { external.wrappedValue.toggle() } else { expandedLocally.toggle() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(hovering || expanded ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Palette.muted))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(title).foregroundStyle(hovering ? Palette.ink : Palette.ink.opacity(0.85))
                    Spacer(minLength: 0)
                }.padding(.vertical, 5).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in
                guard inside != hovering else { return }
                hovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear { if hovering { hovering = false; NSCursor.pop() } }
            .modifier(FocusHalo(kind: .rounded(6)))
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityHint(expanded ? "Hides details" : "Shows details")
            if expanded {
                content().frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Frosted segmented control with a glass thumb that slides between options.
struct SegmentedTabs<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(options: [Value], title: KeyPath<Value, String>, selection: Binding<Value>) {
        self.options = options
        self.title = { $0[keyPath: title] }
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                let radius: CGFloat = Palette.isWebsite ? 8 : 100
                Button {
                    withAnimation(reduceMotion ? nil : Motion.snappy) { selection = option }
                } label: {
                    Text(title(option)).font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(selected ? (Palette.isWebsite ? Palette.onAccent : Palette.ink) : Palette.muted)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background {
                            if selected {
                                GlassThumb().matchedGeometryEffect(id: "tab", in: indicator)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                }
                .buttonStyle(.plain)
                .modifier(FocusHalo(kind: .rounded(radius)))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(SegmentTrack())
        .fixedSize()
    }
}

/// The recessed track behind segmented controls.
struct SegmentTrack: View {
    var radius: CGFloat? = nil
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? (Palette.isWebsite ? 11 : 100), style: .continuous)
        if Palette.isWebsite {
            shape.fill(Palette.surface).overlay { shape.strokeBorder(Palette.line, lineWidth: 1) }
        } else {
            shape.fill(Color.black.opacity(0.25))
                .overlay { shape.strokeBorder(LinearGradient(colors: [Color.black.opacity(0.3), Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
        }
    }
}

/// The raised glass thumb inside a segmented control.
struct GlassThumb: View {
    var radius: CGFloat? = nil
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? (Palette.isWebsite ? 8 : 100), style: .continuous)
        if Palette.isWebsite {
            shape.fill(Palette.cream)
        } else {
            shape.fill(Color.white.opacity(0.12))
                .overlay { shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1) }
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        }
    }
}
