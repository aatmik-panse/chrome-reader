import Foundation
import XCTest

/// Static accessors for the bundled test fixtures. The files live in
/// `Tests/Fixtures/` and are copied as resources by the test target.
enum Fixtures {
    private static let bundle = Bundle(for: FixturesAnchor.self)

    static var epubURL: URL {
        bundle.url(forResource: "sample", withExtension: "epub")!
    }

    static var pdfURL: URL {
        bundle.url(forResource: "sample", withExtension: "pdf")!
    }

    static var txtURL: URL {
        bundle.url(forResource: "sample", withExtension: "txt")!
    }
}

/// Anchor class used solely to resolve the test bundle via `Bundle(for:)`.
private final class FixturesAnchor {}
