//
//  GlassControls.swift
//  BallGesture
//
//  A switch and a slider drawn by the app. The system ones turn grey whenever their window
//  loses focus; these look the same whether or not the window is in front.
//

import SwiftUI

struct GlassSwitchStyle: ToggleStyle {
    var width: CGFloat = 32
    var height: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        GlassSwitch(isOn: configuration.$isOn, width: width, height: height)
    }
}

extension ToggleStyle where Self == GlassSwitchStyle {
    static var glassSwitch: GlassSwitchStyle { GlassSwitchStyle() }
    static var smallGlassSwitch: GlassSwitchStyle { GlassSwitchStyle(width: 26, height: 15) }
}

private struct GlassSwitch: View {
    @Binding var isOn: Bool
    let width: CGFloat
    let height: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let inset: CGFloat = 2
        let knob = height - inset * 2
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Palette.green : Color.white.opacity(0.14))
                .overlay(Capsule().strokeBorder(Color.white.opacity(isOn ? 0 : 0.16), lineWidth: 1))
            Circle()
                .fill(Palette.brightWhite)
                .frame(width: knob, height: knob)
                .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 1)
                .padding(inset)
        }
        .frame(width: width, height: height)
        .contentShape(Capsule())
        .onTapGesture {
            guard isEnabled else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(duration: 0.22, bounce: 0)) {
                isOn.toggle()
            }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?

    @Environment(\.isEnabled) private var isEnabled

    private static let knob: CGFloat = 14
    private static let track: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - Self.knob, 1)
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let knobX = travel * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: Self.track)
                Capsule()
                    .fill(Palette.green)
                    .frame(width: knobX + Self.knob / 2, height: Self.track)
                Circle()
                    .fill(Palette.brightWhite)
                    .frame(width: Self.knob, height: Self.knob)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 1)
                    .offset(x: knobX)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        set(fraction: (drag.location.x - Self.knob / 2) / travel)
                    }
            )
        }
        .frame(height: 18)
        .accessibilityElement()
        .accessibilityValue(String(format: "%.2f", value))
        .accessibilityAdjustableAction { direction in
            let amount = step ?? (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(value + amount, range.upperBound)
            case .decrement: value = max(value - amount, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func set(fraction: CGFloat) {
        let clamped = Double(min(max(fraction, 0), 1))
        var newValue = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
        if let step {
            newValue = (newValue / step).rounded() * step
            newValue = min(max(newValue, range.lowerBound), range.upperBound)
        }
        if newValue != value { value = newValue }
    }
}
