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
    @State private var isAddingThreeDApp = false
    /// Bundle ID of the app whose 3D settings are shown; empty for the default set.
    @State private var selectedThreeDApp = ""
    @Namespace private var threeDAppNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            threeDSection

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
            ForEach(ThreeDAction.allCases) { action in
                keyRow(
                    title: "3D \(action.displayName)",
                    keyCode: settings.threeDTriggerKeyCode(for: action),
                    target: .threeDTrigger(action)
                )
            }

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

    private var threeDSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("3D Mode").font(.headline)
            Text("Apps").font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                threeDAppRow(
                    bundleID: "",
                    name: "All Other Apps",
                    icon: NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil) ?? NSImage()
                )
                ForEach(settings.threeDAppProfiles) { app in
                    threeDAppRow(
                        bundleID: app.bundleID,
                        name: Self.appName(for: app.bundleID),
                        icon: Self.appIcon(for: app.bundleID)
                    )
                }
            }
            Button(isAddingThreeDApp ? "Done" : "Add App…") {
                isAddingThreeDApp.toggle()
            }
            if isAddingThreeDApp {
                runningAppsToAdd
            }
            Text("Keys in \(selectedThreeDAppName)").font(.caption)
            ForEach(ThreeDAction.allCases) { action in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(action.displayName)
                        Text(KeyCodeNaming.displayName(for: settings.threeDTriggerKeyCode(for: action)))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 52, alignment: .leading)
                    Picker("", selection: outputBinding(for: action)) {
                        ForEach(ThreeDOutput.allCases) { output in
                            Text(output.displayName).tag(output)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    Toggle("Reverse", isOn: reversedBinding(for: action))
                }
            }
            sensitivitySlider(title: "Sensitivity (all apps)", value: $settings.threeDSensitivity)
        }
    }

    private var selectedThreeDAppName: String {
        selectedThreeDApp.isEmpty ? "All Other Apps" : Self.appName(for: selectedThreeDApp)
    }

    /// One app in the 3D app list; selecting it shows its keys below.
    private func threeDAppRow(bundleID: String, name: String, icon: NSImage) -> some View {
        let isSelected = selectedThreeDApp == bundleID
        return HStack(spacing: 6) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(name)
                .lineLimit(1)
                .foregroundColor(isSelected ? Color(red: 0xfc / 255, green: 0xfc / 255, blue: 0xfa / 255) : .primary)
            Spacer()
            if !bundleID.isEmpty {
                Button {
                    settings.threeDAppProfiles.removeAll { $0.bundleID == bundleID }
                    if isSelected {
                        selectedThreeDApp = ""
                    }
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
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(red: 0x33 / 255, green: 0xA5 / 255, blue: 0xA5 / 255).opacity(0.3))
                    .matchedGeometryEffect(id: "threeDAppSelection", in: threeDAppNamespace)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(duration: 0.28, bounce: 0)) {
                selectedThreeDApp = bundleID
            }
        }
    }

    /// The profile being edited: the selected app's override, or the default set.
    private var selectedProfile: Binding<ThreeDProfile> {
        Binding(
            get: { settings.threeDAppProfiles.first { $0.bundleID == selectedThreeDApp }?.profile
                ?? settings.threeDDefaultProfile },
            set: { profile in
                if let index = settings.threeDAppProfiles.firstIndex(where: { $0.bundleID == selectedThreeDApp }) {
                    settings.threeDAppProfiles[index].profile = profile
                } else {
                    settings.threeDDefaultProfile = profile
                }
            }
        )
    }

    private func outputBinding(for action: ThreeDAction) -> Binding<ThreeDOutput> {
        let profile = selectedProfile
        return Binding(
            get: { profile.wrappedValue[action].output },
            set: { profile.wrappedValue[action].output = $0 }
        )
    }

    private func reversedBinding(for action: ThreeDAction) -> Binding<Bool> {
        let profile = selectedProfile
        return Binding(
            get: { profile.wrappedValue[action].reversed },
            set: { profile.wrappedValue[action].reversed = $0 }
        )
    }

    private func addThreeDApp(bundleID: String) {
        settings.addThreeDAppProfile(bundleID: bundleID)
        selectedThreeDApp = bundleID
    }

    /// Running apps are offered first because some apps (Autodesk Fusion,
    /// for one) start from a launcher in /Applications whose bundle ID
    /// differs from the process that ends up frontmost.
    private var runningAppsToAdd: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Running apps").font(.caption2).foregroundColor(.secondary)
            ForEach(addableRunningApps, id: \.bundleIdentifier) { app in
                HStack(spacing: 6) {
                    Image(nsImage: app.icon ?? NSImage())
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(app.localizedName ?? app.bundleIdentifier ?? "")
                        .lineLimit(1)
                    Spacer()
                    Button {
                        if let bundleID = app.bundleIdentifier {
                            addThreeDApp(bundleID: bundleID)
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Add")
                }
            }
            Button("Other…") {
                chooseThreeDApps()
            }
        }
        .padding(.leading, 8)
    }

    private var addableRunningApps: [NSRunningApplication] {
        var seen = Set(settings.threeDAppProfiles.map(\.bundleID))
        seen.insert(Bundle.main.bundleIdentifier ?? "")
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular,
                      let bundleID = app.bundleIdentifier else { return false }
                return seen.insert(bundleID).inserted
            }
            .sorted {
                ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending
            }
    }

    private func chooseThreeDApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            addThreeDApp(bundleID: bundleID)
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
