import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(Preferences.self) private var preferences
    let close: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchMessage: String?

    private static let refreshOptions: [Double] = [2, 5, 10, 30, 60]

    var body: some View {
        @Bindable var preferences = preferences
        VStack(spacing: 0) {
            ZStack {
                Text("Settings").font(.headline)
                HStack {
                    Button(action: close) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                }
            }
            .padding(12)

            Divider()

            Form {
                Section("General") {
                    Toggle("Launch at login", isOn: launchAtLoginBinding)
                    if let launchMessage {
                        Text(launchMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Show port count in menu bar", isOn: $preferences.showCountInMenuBar)
                    Picker("Refresh every", selection: $preferences.refreshInterval) {
                        ForEach(Self.refreshOptions, id: \.self) { seconds in
                            Text(verbatim: "\(Int(seconds)) seconds").tag(seconds)
                        }
                    }
                }

                Section("Ports") {
                    Toggle("Include UDP ports", isOn: $preferences.includeUDP)
                    Toggle("Hide macOS system processes", isOn: $preferences.hideSystemProcesses)
                }

                Section {
                    Stepper(value: $preferences.graceSeconds, in: 1...30) {
                        Text(verbatim: "Give a normal kill \(preferences.graceSeconds)s before warning")
                    }
                    Toggle("Force kill automatically if a normal kill fails", isOn: $preferences.autoForceKill)
                    Toggle("Confirm before force killing", isOn: $preferences.confirmForceKill)
                } header: {
                    Text("Killing")
                }

                Section("Folders") {
                    Picker("Open working directories in", selection: $preferences.folderOpenerID) {
                        ForEach(FolderOpener.installed) { opener in
                            Text(opener.name).tag(opener.id)
                        }
                    }
                }

                Section("Hidden processes") {
                    if preferences.hiddenProcesses.isEmpty {
                        Text("None. Hide a process from a port's ⋯ menu.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(preferences.hiddenProcesses, id: \.self) { name in
                        HStack {
                            Text(verbatim: name)
                            Spacer()
                            Button("Unhide") {
                                preferences.hiddenProcesses.removeAll { $0 == name }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            launchAtLogin
        } set: { enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                launchMessage = nil
            } catch {
                launchMessage = "Couldn't change login item: \(error.localizedDescription)"
            }
            let status = SMAppService.mainApp.status
            launchAtLogin = status == .enabled
            if status == .requiresApproval {
                launchMessage = "Approve Whack-a-Port in System Settings › General › Login Items."
            }
        }
    }
}
