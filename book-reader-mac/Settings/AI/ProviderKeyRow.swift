import SwiftUI

struct ProviderKeyRow: View {
    let provider: ProviderID
    @Bindable var model: AISettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.displayName)
                    .font(.headline)
                Spacer()
                statusBadge
            }
            HStack(spacing: 8) {
                SecureField(
                    "Paste API key",
                    text: Binding(
                        get: { model.keyDrafts[provider] ?? "" },
                        set: { model.keyDrafts[provider] = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                Button("Save") { model.saveKey(for: provider) }
                    .disabled((model.keyDrafts[provider] ?? "").isEmpty)
                Button("Test") {
                    Task { await model.testKey(for: provider) }
                }
                .disabled(!(model.hasSavedKey[provider] ?? false))
                Button("Delete") { model.deleteKey(for: provider) }
                    .disabled(!(model.hasSavedKey[provider] ?? false))
            }
            if case .failed(let msg) = model.testState[provider] ?? .idle {
                Text(msg).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch model.testState[provider] ?? .idle {
        case .idle:
            if model.hasSavedKey[provider] == true {
                Text("Saved").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No key").font(.caption).foregroundStyle(.secondary)
            }
        case .running:
            ProgressView().controlSize(.small)
        case .ok:
            Label("OK", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}
