import SwiftUI

struct EqualizerView: View {
    @ObservedObject var player: Player

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Equalizer")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Spotify EQ", isOn: Binding(
                    get: { player.desiredEQEnabled },
                    set: { player.enableEQ($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.green)
            }
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    Text("Presets").foregroundStyle(.secondary)
                    Menu {
                        ForEach(EQPreset.all) { preset in
                            Button {
                                player.preset(preset)
                            } label: {
                                if player.selectedPreset == preset.name {
                                    Label(preset.name, systemImage: "checkmark")
                                } else {
                                    Text(preset.name)
                                }
                            }
                        }
                    } label: {
                        Text(player.selectedPreset)
                            .frame(minWidth: 90, alignment: .leading)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("Equalizer preset")
                    Spacer()
                }
                .font(.system(size: 12))
                EqualizerGraph(gains: player.gains) { band, gain in
                    player.setBand(band, gain: gain)
                }
                HStack {
                    Spacer()
                    Button {
                        player.preset(EQPreset.all[0])
                    } label: {
                        Text("Reset")
                    }
                    .buttonStyle(EqualizerResetButtonStyle())
                    .accessibilityHint("Reset all equalizer bands to zero decibels")
                }
            }
            .padding(16)
        }
    }
}

private struct EqualizerGraph: View {
    let gains: [Double]
    let onGainChange: (EQBand, Double) -> Void
    private let accent = Color(red: 0.12, green: 0.76, blue: 0.34)
    private let gainLimit = 9.0
    private let plotHeight: CGFloat = 150
    private let topInset: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let left: CGFloat = 36
            let right = max(left + 1, geometry.size.width - 14)
            let points = bandPoints(left: left, right: right)
            ZStack(alignment: .topLeading) {
                Path { path in
                    for point in points {
                        path.move(to: CGPoint(x: point.x, y: topInset))
                        path.addLine(to: CGPoint(x: point.x, y: topInset + plotHeight))
                    }
                    path.move(to: CGPoint(x: left - 8, y: topInset + plotHeight / 2))
                    path.addLine(to: CGPoint(x: right + 8, y: topInset + plotHeight / 2))
                }
                .stroke(.primary.opacity(0.1), lineWidth: 0.5)
                .accessibilityHidden(true)
                filledCurve(points)
                    .fill(LinearGradient(colors: [accent.opacity(0.55), accent.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .accessibilityHidden(true)
                curve(points)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .accessibilityHidden(true)
                Text("+9 dB")
                    .position(x: 14, y: topInset)
                Text("−9 dB")
                    .position(x: 14, y: topInset + plotHeight)
                ForEach(EQBand.allCases) { band in
                    let point = points[band.rawValue]
                    Text(frequencyLabel(band))
                        .position(x: point.x, y: topInset + plotHeight + 24)
                        .accessibilityHidden(true)
                    EqualizerBandControl(band: band, gain: gains[band.rawValue],
                                         gainLimit: gainLimit, plotHeight: plotHeight,
                                         topInset: topInset, accent: accent) { gain in
                        onGainChange(band, gain)
                    }
                    .position(x: point.x, y: topInset + plotHeight / 2)
                }
            }
            .coordinateSpace(name: "equalizerPlot")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .frame(height: topInset + plotHeight + 36)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Equalizer band gains")
    }

    private func bandPoints(left: CGFloat, right: CGFloat) -> [CGPoint] {
        let step = (right - left) / CGFloat(EQBand.allCases.count - 1)
        return EQBand.allCases.map { band in
            let x = left + step * CGFloat(band.rawValue)
            let fraction = (gainLimit - gains[band.rawValue]) / (gainLimit * 2)
            let y = topInset + CGFloat(fraction) * plotHeight
            return CGPoint(x: x, y: y)
        }
    }

    private func frequencyLabel(_ band: EQBand) -> String {
        band.frequency >= 1000 ? "\(Int(band.frequency / 1000)) kHz" : "\(Int(band.frequency)) Hz"
    }

    // This joins the band controls smoothly; it is not a measured frequency response.
    private func curve(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for segment in EqualizerCurve.segments(through: points) {
                path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
            }
        }
    }

    private func filledCurve(_ points: [CGPoint]) -> Path {
        var path = curve(points)
        guard let first = points.first, let last = points.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: topInset + plotHeight))
        path.addLine(to: CGPoint(x: first.x, y: topInset + plotHeight))
        path.closeSubpath()
        return path
    }
}

private struct EqualizerBandControl: View {
    let band: EQBand
    let gain: Double
    let gainLimit: Double
    let plotHeight: CGFloat
    let topInset: CGFloat
    let accent: Color
    let onChange: (Double) -> Void
    @FocusState private var focused: Bool

    private var nodeY: CGFloat {
        CGFloat((gainLimit - gain) / (gainLimit * 2)) * plotHeight
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            Circle()
                .fill(.white)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(accent.opacity(0.5), lineWidth: 0.5))
                .position(x: 18, y: nodeY)
        }
        .frame(width: 36, height: plotHeight)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("equalizerPlot"))
            .onChanged { value in
                focused = true
                let fraction = min(1, max(0, (value.location.y - topInset) / plotHeight))
                onChange(gainLimit - Double(fraction) * gainLimit * 2)
            })
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { adjust(by: 0.5); return .handled }
        .onKeyPress(.downArrow) { adjust(by: -0.5); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(band.label)
        .accessibilityValue(String(format: "%.1f decibels", gain))
        .accessibilityHint("Drag vertically or use the up and down arrow keys to adjust")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(by: 0.5)
            case .decrement: adjust(by: -0.5)
            @unknown default: break
            }
        }
        .help(band.label)
    }

    private func adjust(by amount: Double) {
        onChange(min(gainLimit, max(-gainLimit, gain + amount)))
    }
}

private struct EqualizerResetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 68, height: 28)
            .background(Capsule().fill(.primary.opacity(configuration.isPressed ? 0.08 : 0.025)))
            .overlay(Capsule().strokeBorder(.primary.opacity(0.22), lineWidth: 1))
            .clipShape(Capsule())
            .contentShape(Capsule())
    }
}
