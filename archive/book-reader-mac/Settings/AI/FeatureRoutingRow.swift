import SwiftUI

struct FeatureRoutingRow: View {
    let feature: AIFeature
    @Bindable var model: AISettingsViewModel

    var body: some View {
        let provider = model.featureProvider[feature] ?? .openai
        HStack {
            Text(feature.displayName).frame(width: 160, alignment: .leading)
            Picker("", selection: Binding(
                get: { provider },
                set: { model.setProvider($0, for: feature) }
            )) {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    Text(id.displayName).tag(id)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            Picker("", selection: Binding(
                get: { model.featureModel[feature] ?? "" },
                set: { model.setModel($0, for: feature) }
            )) {
                Text("Default").tag("")
                ForEach(model.availableModels(for: provider), id: \.self) { m in
                    Text(m).tag(m)
                }
            }
            .labelsHidden()
        }
    }
}
