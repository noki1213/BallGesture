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

/// One page of the settings, by mode.
private enum SettingsTab: String, CaseIterable, Identifiable {
    case scroll, zoom, gesture, threeD, mouse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scroll: return "Scroll"
        case .zoom: return "Zoom"
        case .gesture: return "Gesture"
        case .threeD: return "3D"
        case .mouse: return "Mouse"
        }
    }
}

struct MenuBarContentView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var engine = GestureEngine.shared
    @State private var isAccessibilityTrusted = AccessibilityPermission.isTrusted
    @State private var resetCommandCopied = false
    @State private var isAddingThreeDApp = false
    /// Bundle ID of the app whose 3D settings are shown; empty for the default set.
    @State private var selectedThreeDApp = ""
    @State private var pointingDevices = PointingDeviceMonitor.connectedDevices()
    @Namespace private var threeDAppNamespace
    @Namespace private var tabNamespace
    @State private var selectedTab: SettingsTab = .scroll
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Enabled", isOn: $settings.isEnabled)

            Divider()

            accessibilitySection

            Divider()

            tabBar

            Group {
                switch selectedTab {
                case .scroll: scrollSection
                case .zoom: zoomSection
                case .gesture: gestureSection
                case .threeD: threeDSection
                case .mouse: autoMouseSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let message = settings.captureErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Divider()

            Button("Quit BallGesture") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onReceive(refreshTimer) { _ in
            isAccessibilityTrusted = AccessibilityPermission.isTrusted
            pointingDevices = PointingDeviceMonitor.connectedDevices()
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

    /// The selection pill is a single view that glides to the chosen tab.
    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Text(tab.title)
                    .font(.subheadline)
                    .foregroundColor(isSelected ? Color(red: 0xfc / 255, green: 0xfc / 255, blue: 0xfa / 255) : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color(red: 0x33 / 255, green: 0xA5 / 255, blue: 0xA5 / 255).opacity(0.3))
                                .matchedGeometryEffect(id: "settingsTab", in: tabNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settings.cancelCapture()
                        withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .timingCurve(0.65, 0, 0.35, 1, duration: 0.4)) {
                            selectedTab = tab
                        }
                    }
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
            keyRow(title: "Trigger Key", keyCode: settings.scrollTriggerKeyCode, target: .scrollTrigger)
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
            ForEach(ThreeDAction.allCases) { action in
                keyRow(
                    title: "\(action.displayName) Key",
                    keyCode: settings.threeDTriggerKeyCode(for: action),
                    target: .threeDTrigger(action)
                )
            }
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

    private var autoMouseSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Auto Mouse Layer", isOn: $settings.autoMouseEnabled)
            Text("While the pointer moves, these keys click instead of typing.")
                .font(.caption)
                .foregroundColor(.secondary)
            if settings.autoMouseEnabled {
                Picker("Device", selection: $settings.autoMouseDevice) {
                    Text("Any Pointer").tag(PointingDeviceID?.none)
                    ForEach(autoMouseDeviceChoices) { device in
                        Text(pointingDevices.contains(device) ? device.product : "\(device.product) (not connected)")
                            .tag(PointingDeviceID?.some(device))
                    }
                }
                .pickerStyle(.menu)
                if engine.pointingMonitorNeedsAccess {
                    Text("Watching one device needs Input Monitoring access.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open Input Monitoring Settings") {
                        PointingDeviceMonitor.openInputMonitoringSettings()
                    }
                }
                ForEach(AutoMouseButton.allCases) { button in
                    keyRow(
                        title: button.displayName,
                        keyCode: settings.autoMouseKeyCode(for: button),
                        target: .autoMouseButton(button)
                    )
                }
                Text("Hold Keys").font(.caption)
                Text("For keys that send a modifier when held, such as home row mods: holding sends that modifier, which then holds the button to drag.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(AutoMouseButton.allCases) { button in
                    holdKeyRow(button)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stays On After Moving").font(.caption)
                    Slider(value: $settings.autoMouseTimeout, in: 0.2...2.0, step: 0.1)
                    Text("\(Int((settings.autoMouseTimeout * 1000).rounded())) ms")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func holdKeyRow(_ button: AutoMouseButton) -> some View {
        let target = KeyCaptureTarget.autoMouseHoldKey(button)
        let keyCode = settings.autoMouseHoldKeyCodes[button]
        return HStack {
            Text(button.displayName)
            Spacer()
            if settings.captureTarget == target {
                Text("Press any key…")
                    .foregroundColor(.secondary)
                Button("Cancel") {
                    settings.cancelCapture()
                }
            } else {
                Text(keyCode.map(KeyCodeNaming.displayName(for:)) ?? "None")
                    .foregroundColor(.secondary)
                if keyCode != nil {
                    Button {
                        settings.clearAutoMouseHoldKey(for: button)
                    } label: {
                        Image(systemName: "minus.circle")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Remove")
                }
                Button("Set Key") {
                    settings.beginCapture(for: target)
                }
                .disabled(settings.captureTarget != nil)
            }
        }
    }

    /// Connected devices, plus the chosen one while it is disconnected.
    private var autoMouseDeviceChoices: [PointingDeviceID] {
        guard let chosen = settings.autoMouseDevice, !pointingDevices.contains(chosen) else {
            return pointingDevices
        }
        return pointingDevices + [chosen]
    }

    private var zoomSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            keyRow(title: "Trigger Key", keyCode: settings.zoomTriggerKeyCode, target: .zoomTrigger)
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
            keyRow(title: "Trigger Key", keyCode: settings.gestureTriggerKeyCode, target: .gestureTrigger)
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
