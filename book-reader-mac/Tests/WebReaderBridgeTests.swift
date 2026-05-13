import XCTest
@testable import InstantBookReader

final class WebReaderBridgeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "WebReaderBridgeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSetThenGetSingleKey() throws {
        let store = WebReaderStorage(defaults: defaults)
        store.set(["currentBookHash": "abc"])
        let got = store.get(.array(["currentBookHash"]))
        XCTAssertEqual(got["currentBookHash"] as? String, "abc")
    }

    func testGetAllReturnsKnownKeys() throws {
        let store = WebReaderStorage(defaults: defaults)
        store.set(["a": 1, "b": "two", "c": true])
        let got = store.get(.allKeys)
        XCTAssertEqual(got["a"] as? Int, 1)
        XCTAssertEqual(got["b"] as? String, "two")
        XCTAssertEqual(got["c"] as? Bool, true)
    }

    func testRemoveErases() throws {
        let store = WebReaderStorage(defaults: defaults)
        store.set(["x": "y"])
        XCTAssertEqual(store.get(.array(["x"]))["x"] as? String, "y")
        store.remove(.array(["x"]))
        XCTAssertNil(store.get(.array(["x"]))["x"])
    }

    func testGetByObjectAppliesDefaults() throws {
        let store = WebReaderStorage(defaults: defaults)
        // No value yet for theme; default should propagate.
        let got = store.get(.object(["theme": "clay-dark"]))
        XCTAssertEqual(got["theme"] as? String, "clay-dark")
        store.set(["theme": "clay-light"])
        let after = store.get(.object(["theme": "clay-dark"]))
        XCTAssertEqual(after["theme"] as? String, "clay-light")
    }

    func testChangeListenersFireOnSet() throws {
        let store = WebReaderStorage(defaults: defaults)
        let exp = expectation(description: "change fired")
        store.onChange { changes in
            if let entry = changes["k"], entry.newValue as? String == "v" {
                exp.fulfill()
            }
        }
        store.set(["k": "v"])
        wait(for: [exp], timeout: 1.0)
    }
}
