import SwiftUI

/// Visual layers only; selection geometry and input stay in WheelModel.
struct WheelView: View {
    let model: WheelModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var outerRadius: CGFloat { model.layout.outerRadius }
    private var innerRadius: CGFloat { model.layout.innerRadius }
    private var iconRadius: CGFloat { model.layout.iconRadius }
    private var palette: WheelPalette { WheelPalette(isDark: colorScheme == .dark) }
    private var accent: Color { palette.accent }
    private var isQuickSwitchPreview: Bool { model.selectedItem == nil && model.quickSwitchItem != nil }
    private var hubIdentity: HubIdentity {
        let item = model.selectedItem ?? model.quickSwitchItem
        return HubIdentity(item: item?.id,
                           window: item.flatMap { model.chosenWindow(of: $0)?.id },
                           isQuickSwitch: isQuickSwitchPreview)
    }

    private var selectionAnimation: Animation? {
        if reduceMotion { return .easeOut(duration: 0.09) }
        return .spring(response: 0.18, dampingFraction: 0.88)
    }

    var body: some View {
        wheelContent
    }

    private var wheelContent: some View {
        ZStack {
            sectors
                .animation(selectionAnimation, value: model.selectedIndex)
                .animation(.easeOut(duration: 0.07), value: model.selectionReach)
            hub
            icons.animation(selectionAnimation, value: model.selectedIndex)
            actionRail
                .animation(.easeOut(duration: reduceMotion ? 0.08 : 0.12), value: model.selectedIndex)
                .animation(.easeOut(duration: 0.07), value: model.selectionReach)
        }
        .frame(width: model.layout.diameter, height: model.layout.diameter)
        .backgroundPreferenceValue(WheelCaptionBounds.self) { anchors in
            GeometryReader { geometry in
                WheelInstrumentSurface(palette: palette, captionRects: anchors.map { geometry[$0] })
            }
        }
    }

    /// A soft selection field that gains contrast and green light as the pointer travels outward.
    private var sectors: some View {
        let count = model.items.count
        let fill = palette.selectionFill(reach: model.selectionReach)
        let wash = palette.selectionAccent(reach: model.selectionReach)
        let rimWidth = 1.25 + 5.75 * model.selectionReach
        return ZStack {
            ForEach(0..<count, id: \.self) { index in
                let isSelected = index == model.selectedIndex
                SectorShape(index: index, count: count,
                            innerRadius: innerRadius + 5, outerRadius: outerRadius - 4)
                    .fill(RadialGradient(
                        colors: [fill.opacity(0.3), fill],
                        center: .center, startRadius: innerRadius, endRadius: outerRadius
                    ))
                    .overlay {
                        SectorShape(index: index, count: count,
                                    innerRadius: innerRadius + 5, outerRadius: outerRadius - 4)
                            .fill(RadialGradient(colors: [.clear, wash],
                                                 center: .center, startRadius: iconRadius - 12,
                                                 endRadius: outerRadius))
                    }
                    .blur(radius: 10)
                    .clipShape(Circle().inset(by: 6))
                    .opacity(isSelected ? 1 : 0)
                    .animation(.easeOut(duration: reduceMotion ? 0.06 : (isSelected ? 0.045 : 0.15)),
                               value: isSelected)

                SelectionRim(index: index, count: count, radius: outerRadius - 3)
                    .stroke(accent.opacity(palette.isDark ? 0.32 : 0.16),
                            style: StrokeStyle(lineWidth: 5 + 4 * model.selectionReach, lineCap: .round))
                    .blur(radius: 5)
                    .opacity(isSelected ? 1 : 0)
                    .animation(.easeOut(duration: reduceMotion ? 0.06 : (isSelected ? 0.045 : 0.15)),
                               value: isSelected)

                SelectionRim(index: index, count: count, radius: outerRadius - 1)
                    .stroke(accent.opacity(0.98), style: StrokeStyle(lineWidth: rimWidth, lineCap: .round))
                    .shadow(color: accent.opacity(0.28), radius: 3)
                    .opacity(isSelected && !model.showsActionRail(for: model.items[index]) ? 1 : 0)
            }
        }
    }

    /// A slim rail replaces the selected rim. The close action sits off the radial path.
    @ViewBuilder
    private var actionRail: some View {
        if let index = model.selectedIndex, model.showsActionRail(for: model.items[index]) {
            let count = model.items.count
            let center = model.layout.closeButtonCenter(index: index, count: count)
            let railAngle = model.layout.actionRailAngle(index: index, count: count)
            let direction = model.layout.actionRailDirection(index: index, count: count)
            ZStack {
                ActionRailArc(angle: railAngle, radius: model.layout.actionRailRadius,
                              start: -WheelLayout.actionRailHalfAngle, end: WheelLayout.actionRailHalfAngle)
                    .stroke(palette.border, style: StrokeStyle(lineWidth: 13.5, lineCap: .round))
                ActionRailArc(angle: railAngle, radius: model.layout.actionRailRadius,
                              start: -WheelLayout.actionRailHalfAngle, end: WheelLayout.actionRailHalfAngle)
                    .stroke(palette.actionRailSurface, style: StrokeStyle(lineWidth: 12.25, lineCap: .round))
                if model.isActionRailBusy(for: model.items[index]) {
                    QuittingRailProgress(angle: railAngle, radius: model.layout.actionRailRadius)
                } else {
                    ActionRailArc(angle: railAngle, radius: model.layout.actionRailRadius,
                                  start: direction > 0 ? -0.065 : 0.005,
                                  end: direction > 0 ? -0.005 : 0.065)
                        .stroke(accent, style: StrokeStyle(lineWidth: 1.3 + 4.2 * model.selectionReach, lineCap: .round))
                    CloseButton(size: WheelLayout.closeButtonSize, isHovered: model.isCloseButtonHovered)
                        .offset(x: center.x, y: center.y)
                }
            }
            .id(index)
            .transition(.opacity)
        }
    }

    // MARK: - Window preview

    private var hub: some View {
        ZStack {
            hubContent
                .id(hubIdentity)
                .transition(.opacity)
        }
        .frame(width: innerRadius * 2, height: innerRadius * 2)
        // Animate target changes, not asynchronous screenshot refreshes.
        .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.14), value: hubIdentity)
    }

    @ViewBuilder
    private var hubContent: some View {
        if let item = model.selectedItem ?? model.quickSwitchItem {
            CenteredWheelPreview {
                HubPicture(model: model, item: item, palette: palette)
            } header: {
                VStack(spacing: 0) {
                    if let launcher = item.launchedBy {
                        LauncherBadge(name: launcher)
                            .frame(maxWidth: model.layout.previewSize.width)
                    }
                    if isQuickSwitchPreview {
                        QuickSwitchBadge()
                    } else if let window = model.chosenWindow(of: item),
                              model.windowPosition(of: item) != nil || window.place != .here {
                        WindowCounterBadge(position: model.windowPosition(of: item), place: window.place.label,
                                           title: window.title)
                            .frame(width: model.layout.previewSize.width)
                    }
                }
                .anchorPreference(key: WheelCaptionBounds.self, value: .bounds) { [$0] }
            } footer: {
                VStack(spacing: 5) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .tracking(-0.15)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: innerRadius * 1.55)
                    VStack(spacing: 8) {
                        Rectangle()
                            .fill(palette.separator)
                            .frame(width: model.layout.previewSize.width * 0.55, height: 0.5)
                        if model.quittingPIDs.contains(item.pid) {
                            Label("Quitting…", systemImage: "power")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(accent)
                                .frame(height: 20)
                        } else {
                            releaseHint
                        }
                    }
                }
                .anchorPreference(key: WheelCaptionBounds.self, value: .bounds) { [$0] }
            }
        } else {
            VStack(spacing: 10) {
                CommandKeycap(size: CGSize(width: 48, height: 48), symbolSize: 25, isAccented: true)
                    .background {
                        Circle()
                            .fill(RadialGradient(colors: [accent.opacity(palette.isDark ? 0.1 : 0.06), .clear],
                                                 center: .center, startRadius: 8, endRadius: 48))
                            .frame(width: 96, height: 96)
                            .accessibilityHidden(true)
                    }
                VStack(spacing: 5) {
                    Text("Choose an app")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.ink.opacity(0.9))
                    Text("Move the pointer or press Tab")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.secondaryInk)
                }
                .anchorPreference(key: WheelCaptionBounds.self, value: .bounds) { [$0] }
            }
        }
    }

    private var releaseHint: some View {
        HStack(spacing: 5) {
            Text("Release")
            CommandKeycap(size: CGSize(width: 24, height: 20), symbolSize: 11.5)
            Text("to switch")
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(palette.secondaryInk)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Release Command to switch")
    }

    // MARK: - App ring

    private var icons: some View {
        let count = model.items.count
        let size = model.layout.iconSize(count: count)
        return ZStack {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                let isSelected = index == model.selectedIndex
                let isQuitting = model.quittingPIDs.contains(item.pid)
                let angle = WheelGeometry.angle(of: index, count: count)
                Image(nsImage: item.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(isSelected ? palette.previewShadow : palette.previewShadow / 2), radius: isSelected ? 4 : 2, y: 2)
                    .overlay(alignment: .topTrailing) {
                        if item.launchedBy != nil {
                            LauncherMark(size: max(12, min(17, size * 0.29)))
                                .offset(x: size * 0.035, y: -size * 0.035)
                        }
                    }
                    .modifier(QuittingAppAppearance(isQuitting: isQuitting))
                    .overlay(alignment: .bottom) {
                        if !isQuitting {
                            WindowPositionIndicator(number: item.windowNumber, count: model.windows[item.pid]?.count ?? 0,
                                                    maxWidth: size, tint: accent, isSelected: isSelected)
                                .padding(.top, 4)
                                .alignmentGuide(.bottom) { $0[.top] }
                        }
                    }
                    .animation(.easeOut(duration: 0.12), value: isQuitting)
                    .scaleEffect(isSelected && !reduceMotion ? 1.045 : 1)
                    .offset(x: iconRadius * cos(angle), y: iconRadius * sin(angle))
                    .accessibilityLabel([item.name, item.launchedBy.map { "started by \($0)" },
                                         isQuitting ? "quitting" : nil].compactMap { $0 }.joined(separator: ", "))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
    }
}

/// The hub's picture: a window preview, or the app icon until there is one. A view of its own so
/// a new picture (15 a second with Live Preview) redraws only this, not the whole wheel.
/// Fixed dimensions keep the title still while a screenshot is loading.
private struct HubPicture: View {
    let model: WheelModel
    let item: WheelItem
    let palette: WheelPalette

    var body: some View {
        let box = model.layout.previewSize
        ZStack {
            if let preview = model.preview(for: item) {
                Image(nsImage: preview)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                        ZStack {
                            shape.strokeBorder(.black.opacity(palette.isDark ? 0.3 : 0.16), lineWidth: 3)
                                .blur(radius: 1.5)
                                .clipShape(shape)
                            shape.strokeBorder(LinearGradient(
                                colors: [palette.accent.opacity(0.34), palette.ink.opacity(0.12),
                                         palette.accent.opacity(0.18)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ), lineWidth: 0.75)
                        }
                    }
                    .shadow(color: .black.opacity(palette.previewShadow), radius: 6, y: 3)
                    .padding(2)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(RadialGradient(colors: [palette.accent.opacity(0.1), .clear],
                                         center: .center, startRadius: 4, endRadius: box.width / 2))
                Image(nsImage: item.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 60, height: 60)
                    .modifier(QuittingAppAppearance(isQuitting: model.quittingPIDs.contains(item.pid)))
                    .shadow(color: .black.opacity(palette.previewShadow), radius: 6, y: 3)
            }
        }
        .frame(width: box.width, height: box.height)
        .accessibilityLabel("Window preview for \(item.name)")
    }
}

/// Resolve caption positions in the wheel's background without changing their layout.
private struct WheelCaptionBounds: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

/// An action embedded in the selected sector’s rail, outside the app icon.
/// Clicks never reach SwiftUI here (WheelWindow takes them all) — WheelModel hit-tests it.
private struct CloseButton: View {
    let size: CGFloat
    let isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = WheelPalette(isDark: colorScheme == .dark)
        let shape = Circle().inset(by: 2)
        Image(systemName: "xmark")
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(isHovered ? palette.accent : palette.ink.opacity(0.8))
            .frame(width: size, height: size)
            .background(shape.fill(isHovered ? palette.accent.opacity(0.18) : .clear))
            .animation(.easeOut(duration: 0.1), value: isHovered)
            .accessibilityLabel("Close window")
            .accessibilityHint("Closes the window shown in the preview")
    }
}

/// A fresh presentation for quick-switch, app selection, and windows of the same app.
private struct HubIdentity: Hashable {
    let item: WheelItem.ID?
    let window: CGWindowID?
    let isQuickSwitch: Bool
}

/// The empty state echoes a display key; shortcut captions retain a quiet key outline.
private struct CommandKeycap: View {
    let size: CGSize
    let symbolSize: CGFloat
    var isAccented = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: size.height * (isAccented ? 0.16 : 0.24), style: .continuous)
        let palette = WheelPalette(isDark: isDark)
        let tint = isAccented ? palette.accent : palette.ink
        return Image(systemName: "command")
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(isAccented ? palette.accent.opacity(0.9) : palette.secondaryInk)
            .frame(width: size.width, height: size.height)
            .background(shape.fill(isAccented ? palette.actionRailSurface : tint.opacity(isDark ? 0.06 : 0.035)))
            .overlay(shape.strokeBorder(isAccented ? palette.accent.opacity(0.28) : palette.border, lineWidth: 0.65))
            .shadow(color: isAccented ? palette.accent.opacity(isDark ? 0.09 : 0.04) : .clear, radius: 12)
    }
}

/// Inset ring slice; this changes the highlight only, never the hit area.
private struct SectorShape: Shape {
    let index: Int
    let count: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let mid = WheelGeometry.angle(of: index, count: count)
        let gap = count > 1 ? min(0.025, WheelGeometry.sectorAngle(count: count) * 0.08) : 0
        let half = WheelGeometry.sectorAngle(count: count) / 2 - gap
        let start = Angle(radians: mid - half)
        let end = Angle(radians: mid + half)

        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

struct ActionRailArc: Shape {
    let angle: Double
    let radius: CGFloat
    let start: Double
    let end: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: .radians(angle + start), endAngle: .radians(angle + end), clockwise: false)
        return path
    }
}

private struct SelectionRim: Shape {
    let index: Int
    let count: Int
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let mid = WheelGeometry.angle(of: index, count: count)
        let half = min(WheelGeometry.sectorAngle(count: count) * 0.28, 0.24)
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: .radians(mid - half), endAngle: .radians(mid + half), clockwise: false)
        return path
    }
}

struct WheelView_Previews: PreviewProvider {
    static var previews: some View {
        let model = WheelModel(layout: .standard)
        model.reload(pointer: .zero, quickSwitchTo: nil, window: nil)
        model.step(backward: false)
        return ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            WheelView(model: model)
                .padding(24)
                .background(scheme == .dark ? Color(white: 0.18) : Color(white: 0.85))
                .environment(\.colorScheme, scheme)
                .previewDisplayName(scheme == .dark ? "Dark" : "Light")
        }
    }
}
