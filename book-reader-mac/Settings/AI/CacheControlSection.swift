import SwiftUI

struct CacheControlSection: View {
    @Bindable var model: AISettingsViewModel

    var body: some View {
        Section("Cache") {
            HStack {
                Text("Current size")
                Spacer()
                Text(format(bytes: model.totalCacheBytes))
                    .foregroundStyle(.secondary)
                Button("Refresh") { model.refreshCacheSize() }
            }
            HStack {
                Text("Clear all cached AI responses")
                Spacer()
                Button("Clear cache", role: .destructive) { model.clearCache() }
            }
            Toggle("Sync API keys via iCloud Keychain",
                   isOn: Binding(
                       get: { model.syncToICloud },
                       set: { model.setSync($0) }
                   ))
        }
    }

    private func format(bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB, .useBytes]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}
