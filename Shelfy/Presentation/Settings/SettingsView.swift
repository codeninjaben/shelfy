import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let app: AppModel

    var body: some View {
        SettingsForm(app: app, preferences: app.preferences, folder: app.folder, screens: app.screens)
    }
}

private struct SettingsForm: View {
    let app: AppModel
    @Bindable var preferences: Preferences
    let folder: WatchedFolder
    let screens: ScreenDirectory

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginNeedsApproval = LoginItem.needsApproval
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Picker("Show Shelfy", selection: $preferences.presentation) {
                    ForEach(PresentationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }

            Section {
                Picker("Edge", selection: $preferences.edge) {
                    ForEach(ScreenEdge.allCases) { edge in
                        Text(edge.title).tag(edge)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Position") {
                    Slider(value: $preferences.verticalPosition, in: 0...1) {
                        Text("Position")
                    } minimumValueLabel: {
                        Text("Top").font(.caption).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("Bottom").font(.caption).foregroundStyle(.secondary)
                    }
                    .labelsHidden()
                    .accessibilityValue(positionDescription)
                }

                Picker("Display", selection: displaySelection) {
                    Text("Main Display").tag(String?.none)
                    ForEach(screens.displays) { display in
                        Text(display.name).tag(Optional(display.id))
                    }
                    if let id = preferences.displayID, !screens.isConnected(id) {
                        Text("\(preferences.displayName ?? "Display") (Disconnected)").tag(Optional(id))
                    }
                }

                Picker("Show Tab", selection: $preferences.tabVisibility) {
                    Text(TabVisibility.always.title).tag(TabVisibility.always)
                    Text(TabVisibility.nearPointer.title).tag(TabVisibility.nearPointer)
                }
                .pickerStyle(.segmented)

                Toggle("Hide When Shelf Is Empty", isOn: $preferences.hideTabWhenEmpty)

                Picker("Hover Sensitivity", selection: $preferences.hoverSensitivity) {
                    ForEach(HoverSensitivity.allCases) { sensitivity in
                        Text(sensitivity.title).tag(sensitivity)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Arrival Animation", isOn: $preferences.arrivalAnimation)
            } header: {
                Text("Edge Tab")
            } footer: {
                Text(edgeTabFootnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .disabled(!preferences.presentation.showsEdgeTab)

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Image(nsImage: folder.icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(folder.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(folder.url.path)
                        Button("Choose…") { folder.chooseFolder() }
                            .controlSize(.small)
                    }
                } label: {
                    Text("Watched Folder")
                    if folder.status != .available {
                        Label(folder.status == .missing ? "Folder not found" : "Shelfy can’t read this folder",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                if !folder.isDefault {
                    Button("Use Downloads Folder") { folder.useDownloads() }
                }
            } header: {
                Text("Files")
            } footer: {
                Text("Shelfy only keeps references. Removing or clearing files in Shelfy never moves or deletes the originals.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if loginNeedsApproval {
                    HStack {
                        Text("Approve Shelfy in Login Items to finish.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") { LoginItem.openSystemSettings() }
                    }
                }
                if let loginError {
                    Text(loginError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            screens.refresh()
            folder.refreshStatus()
            launchAtLogin = LoginItem.isEnabled
            loginNeedsApproval = LoginItem.needsApproval
        }
    }

    private var edgeTabFootnote: String {
        var lines: [String] = []
        if preferences.tabVisibility == .nearPointer {
            lines.append("Near Pointer keeps the tab out of sight until the pointer reaches the screen edge beside it. New downloads still peek out.")
        }
        if preferences.hideTabWhenEmpty && preferences.presentation == .edge {
            lines.append("With the menu bar icon hidden, open Shelfy from Spotlight to get back to Settings while the shelf is empty.")
        }
        return lines.isEmpty ? "The tab stays visible at the edge of the screen." : lines.joined(separator: " ")
    }

    private var displaySelection: Binding<String?> {
        Binding {
            preferences.displayID
        } set: { id in
            preferences.displayName = screens.displays.first { $0.id == id }?.name
            preferences.displayID = id
        }
    }

    private var positionDescription: String {
        switch preferences.verticalPosition {
        case ..<0.2: "Near the top"
        case 0.8...: "Near the bottom"
        default: "\(Int((preferences.verticalPosition * 100).rounded())) percent down"
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != LoginItem.isEnabled else { return }
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = "Couldn’t update Login Items: \(error.localizedDescription)"
            launchAtLogin = LoginItem.isEnabled
        }
        loginNeedsApproval = LoginItem.needsApproval
    }
}
