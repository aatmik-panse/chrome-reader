import SwiftUI
import SwiftData

public struct AISettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: AISettingsViewModel?

    public init() {}

    public var body: some View {
        Form {
            Section("Providers") {
                if let model {
                    ForEach(ProviderID.allCases, id: \.self) { p in
                        ProviderKeyRow(provider: p, model: model)
                    }
                }
            }
            Section("Routing") {
                if let model {
                    ForEach(AIFeature.allCases, id: \.self) { f in
                        FeatureRoutingRow(feature: f, model: model)
                    }
                }
            }
            if let model {
                CacheControlSection(model: model)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 620, minHeight: 540)
        .task {
            if model == nil {
                model = AISettingsViewModel(container: modelContext.container)
            }
        }
    }
}
