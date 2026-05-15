import SwiftUI
import UniformTypeIdentifiers

struct ImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var onFileImported: (Result<[URL], Error>) -> Void

    @State private var showingFileImporter = false

    private var theme: Theme {
        ReaderSettings.shared.resolvedTheme(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: ClayConstants.spacingSM) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.matcha600)
                        .padding(.top, ClayConstants.spacingLG)

                    Text("Import a Book")
                        .clayHeading()
                        .foregroundStyle(theme.primaryText)

                    Text("Choose where to import from")
                        .clayCaption()
                        .foregroundStyle(theme.secondaryText)
                        .padding(.bottom, ClayConstants.spacingMD)
                }

                Divider().foregroundStyle(theme.divider)

                ScrollView {
                    VStack(spacing: 0) {
                        importRow(
                            icon: "folder.fill",
                            iconColor: .blue,
                            title: "Files",
                            subtitle: "Browse your device",
                            enabled: true
                        ) {
                            showingFileImporter = true
                        }

                        importRow(
                            icon: "icloud.fill",
                            iconColor: .cyan,
                            title: "iCloud Drive",
                            subtitle: "Import from iCloud",
                            enabled: true
                        ) {
                            showingFileImporter = true
                        }

                        importRow(
                            icon: "globe",
                            iconColor: .orange,
                            title: "OPDS Catalog",
                            subtitle: "Browse open catalogs",
                            enabled: false,
                            badge: "Coming Soon"
                        )

                        importRow(
                            icon: "arrow.down.doc.fill",
                            iconColor: .blue,
                            title: "Dropbox",
                            subtitle: "Connect your Dropbox",
                            enabled: false,
                            badge: "Coming Soon"
                        )

                        importRow(
                            icon: "externaldrive.fill",
                            iconColor: .green,
                            title: "Google Drive",
                            subtitle: "Connect your Google Drive",
                            enabled: false,
                            badge: "Coming Soon"
                        )
                    }
                    .padding(.horizontal, ClayConstants.spacingMD)
                    .padding(.top, ClayConstants.spacingSM)
                }

                Spacer(minLength: 0)

                VStack(spacing: ClayConstants.spacingSM) {
                    Divider().foregroundStyle(theme.divider)

                    Text("Supported formats: EPUB, PDF, TXT")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                        .padding(.bottom, ClayConstants.spacingSM)
                }
            }
            .background(theme.backgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.primaryText)
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.epub, .pdf, .plainText],
            allowsMultipleSelection: false
        ) { result in
            dismiss()
            onFileImported(result)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ClayConstants.cornerRadiusLarge)
    }

    // MARK: - Import Row

    @ViewBuilder
    private func importRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        enabled: Bool,
        badge: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: ClayConstants.spacingMD) {
                ZStack {
                    RoundedRectangle(cornerRadius: ClayConstants.cornerRadiusSmall)
                        .fill(iconColor.opacity(enabled ? 0.12 : 0.06))
                        .frame(width: 40, height: 40)

                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(enabled ? iconColor : Color.silver)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(enabled ? theme.primaryText : theme.secondaryText)

                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.silver.opacity(0.6)))
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()

                if enabled {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .padding(.vertical, ClayConstants.spacingSM)
            .padding(.horizontal, ClayConstants.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: ClayConstants.cornerRadiusMedium)
                    .fill(enabled ? theme.surfaceColor : Color.clear)
            )
        }
        .disabled(!enabled)
        .padding(.vertical, 2)
    }
}
