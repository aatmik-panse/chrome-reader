import AppIntents

struct PreviousPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Page"
    static var description = IntentDescription("Go back one page in the current book.")

    @MainActor
    func perform() async throws -> some IntentResult {
        PageAdvanceBus.shared.post(.previous)
        return .result()
    }
}
