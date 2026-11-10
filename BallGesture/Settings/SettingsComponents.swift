//
//  SettingsComponents.swift
//  BallGesture
//
//  The building blocks of the settings pages: groups of rows, the key recorder and the dropdown.
//

import AppKit
import SwiftUI

// MARK: - Page and groups

struct SettingsPageScaffold<Content: View>: View {
    let page: SettingsPage
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(page.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Palette.brightWhite)
                content
            }
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }
}

/// Rows on one rounded plate, with an optional heading above and a note below.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.dimWhite)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.dimWhite)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

/// A label on the left and its control on the right.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.dimWhite)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 42)
    }
}

struct ToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.white)
                Spacer()
                Text(format(value))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Palette.dimWhite)
            }
            Group {
                if let step {
                    Slider(value: $value, in: range, step: step)
                } else {
                    Slider(value: $value, in: range)
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    static func multiplier(_ value: Double) -> String {
        String(format: "%.1f×", value)
    }
}

/// A button drawn as text alone; colour, not a fill, tells a main action from the rest.
struct TextButton: View {
    let title: String
    var color: Color = Palette.green
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(color.opacity(isHovered ? 1 : 0.85))
                .underline(isHovered, color: color.opacity(0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Reacts the moment the pointer goes down rather than when it comes back up, so a button that
/// opens a board doesn't feel a beat late.
private struct PressDown: ViewModifier {
    let action: () -> Void
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    action()
                }
                .onEnded { _ in isPressed = false }
        )
    }
}

extension View {
    func onPressDown(_ action: @escaping () -> Void) -> some View {
        modifier(PressDown(action: action))
    }
}

// MARK: - Key recorder

/// Shows the assigned key; click it, then press the key to assign. Click again or press Esc to cancel.
/// The key itself is read by the event tap, which also sees F-keys and lone modifiers.
struct KeyRecorderButton: View {
    let target: KeyCaptureTarget
    let keyName: String

    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var model: SettingsModel
    @State private var isHovered = false

    private var isRecording: Bool { settings.captureTarget == target }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Text(isRecording ? "Press a key…" : keyName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isRecording ? Palette.green : Palette.brightWhite)
            .lineLimit(1)
            .frame(width: 128, height: 26)
            .overlay(shape.strokeBorder(isRecording ? Palette.green : Color.white.opacity(isHovered ? 0.30 : 0.16), lineWidth: 1))
            .contentShape(shape)
            .onHover { isHovered = $0 }
            .onTapGesture {
                if isRecording {
                    settings.cancelCapture()
                } else {
                    model.lastCaptureTarget = target
                    settings.beginCapture(for: target)
                }
            }
            .help(isRecording ? "Press the key to assign, or Esc to cancel" : "Click, then press a key")
    }
}

/// A key recorder row, with the reason under it when the pressed key was refused.
struct KeyRow: View {
    let title: String
    var subtitle: String?
    let target: KeyCaptureTarget
    let keyName: String
    var onClear: (() -> Void)?

    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(title: title, subtitle: subtitle) {
                HStack(spacing: 8) {
                    if let onClear, settings.captureTarget != target {
                        Button(action: onClear) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Palette.dimWhite)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                    KeyRecorderButton(target: target, keyName: keyName)
                }
            }
            if model.lastCaptureTarget == target, let message = settings.captureErrorMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.red)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Dropdown

struct DropdownOption: Identifiable {
    let id: String
    let title: String
    var icon: NSImage?
}

/// An open dropdown: where its button sits and what choosing a row does. The settings view draws
/// the board above everything else, so a scroll view or a plate never clips it.
struct DropdownRequest {
    let anchor: CGRect
    let width: CGFloat
    let options: [DropdownOption]
    let selectedID: String?
    let onSelect: (String) -> Void
}

enum DropdownSpace {
    static let name = "settingsWindow"
}

/// The button that drops a board of choices.
struct DropdownButton: View {
    let title: String
    let options: [DropdownOption]
    var selectedID: String?
    var width: CGFloat = 190
    var icon: NSImage?
    let onSelect: (String) -> Void

    @EnvironmentObject private var model: SettingsModel
    @State private var frame: CGRect = .zero
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 6) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.brightWhite)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.dimWhite)
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 26)
        .overlay(shape.strokeBorder(Color.white.opacity(isHovered ? 0.30 : 0.16), lineWidth: 1))
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DropdownSpace.name)) } action: { frame = $0 }
        .onPressDown {
            AppSettings.shared.cancelCapture()
            model.dropdown = DropdownRequest(
                anchor: frame,
                width: max(width, 190),
                options: options,
                selectedID: selectedID,
                onSelect: onSelect
            )
        }
    }
}

/// Covers the window while a dropdown is open: a click anywhere outside the board closes it.
struct DropdownLayer: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        GeometryReader { geometry in
            if let request = model.dropdown {
                let size = geometry.size
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { model.dropdown = nil }
                    placedBoard(request, in: size)
                }
            }
        }
    }

    private func placedBoard(_ request: DropdownRequest, in size: CGSize) -> some View {
        let gap: CGFloat = 6
        let edge: CGFloat = 12
        let below = size.height - request.anchor.maxY - gap - edge
        let above = request.anchor.minY - gap - edge
        let natural = CGFloat(request.options.count) * DropdownBoard.rowHeight + DropdownBoard.padding * 2
        // Open upward only when the room below is too short and there is more room above.
        let opensUp = natural > below && above > below
        let maxHeight = max(opensUp ? above : below, DropdownBoard.rowHeight * 3)
        let height = min(natural, maxHeight)
        let x = min(max(request.anchor.minX, edge), size.width - request.width - edge)
        let y = opensUp ? request.anchor.minY - gap - height : request.anchor.maxY + gap
        return DropdownBoard(request: request, height: height, opensUp: opensUp) { id in
            model.dropdown = nil
            request.onSelect(id)
        }
        .offset(x: x, y: y)
    }
}

private struct DropdownBoard: View {
    static let rowHeight: CGFloat = 28
    static let padding: CGFloat = 5

    let request: DropdownRequest
    let height: CGFloat
    let opensUp: Bool
    let onSelect: (String) -> Void

    @State private var hovered: String?
    @State private var progress: CGFloat = 0
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(request.options) { option in
                    row(option)
                }
            }
            .padding(Self.padding)
        }
        .scrollIndicators(.never)
        .frame(width: request.width, height: height)
        .background(GlassBackground(shape: shape))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.30), radius: 8, x: 0, y: 2)
        .scaleEffect(reduceMotion ? 1 : 0.94 + 0.06 * progress, anchor: opensUp ? .bottom : .top)
        .blur(radius: reduceMotion ? 0 : (1 - progress) * 12)
        .opacity(Double(progress))
        .onAppear {
            withAnimation(Motion.materialize(reduceMotion: reduceMotion)) { progress = 1 }
        }
    }

    private func row(_ option: DropdownOption) -> some View {
        let isSelected = option.id == request.selectedID
        return HStack(spacing: 8) {
            if let icon = option.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 16)
            }
            Text(option.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(hovered == option.id || isSelected ? Palette.brightWhite : Palette.white)
        .padding(.horizontal, 8)
        .frame(height: Self.rowHeight)
        .background {
            if hovered == option.id {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.selection)
                    .matchedGeometryEffect(id: "dropdownHighlight", in: highlight)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                withAnimation(Motion.selection(reduceMotion: reduceMotion)) { hovered = option.id }
            } else if hovered == option.id {
                withAnimation(Motion.selection(reduceMotion: reduceMotion)) { hovered = nil }
            }
        }
        .onTapGesture { onSelect(option.id) }
    }
}
