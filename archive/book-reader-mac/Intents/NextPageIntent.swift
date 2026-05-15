import AppIntents

struct NextPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Page"
    static var description = IntentDescription("Advance to the next page in the current book.")

    @MainActor
    func perform() async throws -> some IntentResult {
        PageAdvanceBus.shared.post(.next)
        return .result()
    }
}
