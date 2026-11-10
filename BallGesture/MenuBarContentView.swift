//
//  MenuBarContentView.swift
//  BallGesture
//
//  Content shown from the menu bar icon: the switch, the permission status, and the way
//  into the settings window.
//

import AppKit
import SwiftUI

struct MenuBarContentView: View {
    /// Closes the panel, before the settings window opens.
    let dismiss: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var engine = GestureEngine.shared
    @ObservedObject private var status = SystemStatus.shared
    @State private var hoveredRow: Row?
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Row {
        case status, settings, quit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Enabled")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.brightWhite)
                Spacer()
                Toggle("", isOn: $settings.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.glassSwitch)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)

            divider

            // Not running: the row leads to the page that explains how to grant access.
            row(.status, action: engine.tapStatus == .running ? nil : { openSettings(.general) }) {
                Circle()
                    .fill(AccessibilityStatus.color(engine.tapStatus))
                    .frame(width: 8, height: 8)
                    .frame(width: 16)
                Text(AccessibilityStatus.text(engine.tapStatus, trusted: status.isAccessibilityTrusted))
                    .foregroundStyle(Palette.dimWhite)
            }

            divider

            row(.settings, action: { openSettings(nil) }) {
                Image(systemName: "gearshape")
                    .frame(width: 16)
                Text("Settings…")
                Spacer()
                Text("⌘,")
                    .foregroundStyle(Palette.dimWhite)
            }
            row(.quit, action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
                    .frame(width: 16)
                Text("Quit BallGesture")
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Palette.white)
        .tint(Palette.green)
        .padding(6)
        .frame(width: 270)
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 1)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
    }

    private func row<Content: View>(_ row: Row, action: (() -> Void)?, @ViewBuilder content: () -> Content) -> some View {
        let isHovered = hoveredRow == row && action != nil
        return HStack(spacing: 8) {
            content()
        }
        .foregroundStyle(isHovered ? Palette.brightWhite : Palette.white)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 30)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.selection)
                    .matchedGeometryEffect(id: "menuHighlight", in: highlight)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(Motion.selection(reduceMotion: reduceMotion)) {
                if inside {
                    hoveredRow = row
                } else if hoveredRow == row {
                    hoveredRow = nil
                }
            }
        }
        .onTapGesture { action?() }
    }

    private func openSettings(_ page: SettingsPage?) {
        dismiss()
        SettingsWindowController.shared.show(page: page)
    }
}
