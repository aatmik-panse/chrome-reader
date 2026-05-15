import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// General preferences: launch at login, summon hotkey, Dock-mode toggle.
/// Launch-at-login uses SMAppService.mainApp; the macOS user may be asked
/// to approve in System Settings → General → Login Items the first time.
struct GeneralTab: View {
    @AppStorage("dockMode") private var dockMode: Bool = false
    @State private var loginItemStatus: SMAppService.Status = .notRegistered
    @State private var lastError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItemStatus == .enabled },
                    set: { newValue in setLoginItem(enabled: newValue) }
                ))
                if loginItemStatus == .requiresApproval {
                    Text("Approval required — open System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Hotkey") {
                LabeledContent("Summon Reader") {
                    KeyboardShortcuts.Recorder(for: .toggleReader)
                }
            }

            Section("Dock") {
                Toggle("Show app in Dock", isOn: $dockMode)
                Text("When off, the app runs as a menu-bar agent only. Reading is unaffected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItemStatus = SMAppService.mainApp.status }
        .onChange(of: dockMode) { _, newValue in
            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
        }
    }

    private func setLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemStatus = SMAppService.mainApp.status
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
