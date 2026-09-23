//
//  MenuBarContentView.swift
//  BallGesture
//
//  Content shown from the menu bar icon.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarContentView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var engine = GestureEngine.shared
    @State private var isAccessibilityTrusted = AccessibilityPermission.isTrusted
    @State private var resetCommandCopied = false

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Enabled", isOn: $settings.isEnabled)

            Divider()

            accessibilitySection

            Divider()

            triggerKeySection

            Divider()

            scrollSection

            Divider()

            zoomSection

            Divider()

            gestureSection

            Divider()

            Button("Quit BallGesture") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 300)
        .onReceive(refreshTimer) { _ in
            isAccessibilityTrusted = AccessibilityPermission.isTrusted
        }
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.subheadline)
            }
            if engine.tapStatus != .running {
                Button("Open Accessibility Settings") {
                    AccessibilityPermission.requestIfNeeded()
                    AccessibilityPermission.openSystemSettings()
                }

                if isAccessibilityTrusted {
                    // The most confusing case: System Settings shows the
                    // switch ON, but the event tap still can't be created.
                    // This happens when install.sh replaces the app bundle
                    // at the same path — the old TCC grant doesn't reliably
                    // carry over to the new binary on disk.
                    Text(
                        "The switch may show ON in System Settings even though the grant is stale " +
                        "(this happens after reinstalling the app). If the status above won't turn " +
                        "green, reset the permission and grant it again:"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Button("Copy 'Reset Permission' Command") {
                        AccessibilityPermission.copyResetCommandToClipboard()
                        resetCommandCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            resetCommandCopied = false
                        }
                    }
                    Text(resetCommandCopied
                        ? "Copied. Paste it into Terminal, press Enter, then relaunch BallGesture."
                        : "Copies: \(AccessibilityPermission.resetCommand)")
                        .font(.caption)
                        .foregroundColor(resetCommandCopied ? .green : .secondary)
                } else {
                    Text("Grant access, then this will start working automatically (no relaunch needed).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var statusColor: Color {
        switch engine.tapStatus {
        case .running: return .green
        case .retrying: return .yellow
        case .notStarted: return .red
        }
    }

    private var statusText: String {
        switch engine.tapStatus {
        case .running:
            return "Accessibility access granted — event tap running"
        case .retrying:
            return "Accessibility access needed — retrying automatically"
        case .notStarted:
            return isAccessibilityTrusted ? "Accessibility access granted, but tap not started" : "Accessibility access needed"
        }
    }

    private var triggerKeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trigger Keys").font(.headline)

            keyRow(title: "Scroll Mode", keyCode: settings.scrollTriggerKeyCode, target: .scrollTrigger)
            keyRow(title: "Zoom Mode", keyCode: settings.zoomTriggerKeyCode, target: .zoomTrigger)
            keyRow(title: "Gesture Mode", keyCode: settings.gestureTriggerKeyCode, target: .gestureTrigger)

            if let message = settings.captureErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func keyRow(title: String, keyCode: Int64, target: KeyCaptureTarget) -> some View {
        HStack {
            Text(title)
            Spacer()
            if settings.captureTarget == target {
                Text("Press any key…")
                    .foregroundColor(.secondary)
                Button("Cancel") {
                    settings.cancelCapture()
                }
            } else {
                Text(KeyCodeNaming.displayName(for: keyCode))
                    .foregroundColor(.secondary)
                Button("Set Key") {
                    settings.beginCapture(for: target)
                }
                .disabled(settings.captureTarget != nil)
            }
        }
    }

    private var scrollSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scroll Mode").font(.headline)
            Toggle("Natural scrolling direction", isOn: $settings.naturalScrollDirection)
            reversedAppsList
            sensitivitySlider(title: "Sensitivity", value: $settings.scrollSensitivity)
            Toggle("Momentum scrolling", isOn: $settings.momentumScrollingEnabled)
            if settings.momentumScrollingEnabled {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Momentum strength").font(.caption)
                    Slider(value: $settings.momentumStrength, in: 0...1)
                }
            }
        }
    }

    private var reversedAppsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reverse direction in these apps").font(.caption)
            ForEach(settings.reversedScrollBundleIDs, id: \.self) { bundleID in
                HStack(spacing: 6) {
                    Image(nsImage: Self.appIcon(for: bundleID))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(Self.appName(for: bundleID))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        settings.reversedScrollBundleIDs.removeAll { $0 == bundleID }
                    } label: {
                        Image(systemName: "minus.circle")
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Remove")
                }
            }
            Button("Add App…") {
                addReversedApps()
            }
        }
    }

    private func addReversedApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                  !settings.reversedScrollBundleIDs.contains(bundleID) else { continue }
            settings.reversedScrollBundleIDs.append(bundleID)
        }
    }

    private static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    private static func appIcon(for bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var zoomSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Zoom Mode").font(.headline)
            Picker("Method", selection: $settings.zoomMethod) {
                ForEach(ZoomMethod.allCases) { method in
                    Text(method.displayName).tag(method)
                }
            }
            .pickerStyle(.menu)
            sensitivitySlider(title: "Sensitivity", value: $settings.zoomSensitivity)
        }
    }

    private var gestureSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gesture Mode").font(.headline)
            VStack(alignment: .leading, spacing: 2) {
                Text("Trigger Distance (px)").font(.caption)
                Slider(value: $settings.gestureDistance, in: 10.0...200.0, step: 10.0)
                Text("\(Int(settings.gestureDistance)) px")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func sensitivitySlider(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption)
            Slider(value: value, in: 0.1...5.0)
        }
    }
}

#Preview {
    MenuBarContentView()
}
