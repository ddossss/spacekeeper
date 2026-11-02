// Minimal assertion adapter for Command Line Tools installations without XCTest.
// The exact same test methods also run under XCTest in a full Xcode installation.
import Foundation

var failures = 0
class XCTestCase {
    func setUpWithError() throws {}
    func tearDownWithError() throws {}
}
func fail(_ text: String, file: StaticString, line: UInt) {
    failures += 1
    print("FAIL \(file):\(line): \(text)")
}
func XCTAssertTrue(_ expression: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !expression() { fail("Expected true", file: file, line: line) } }
    catch { fail(error.localizedDescription, file: file, line: line) }
}
func XCTAssertFalse(_ expression: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try expression() { fail("Expected false", file: file, line: line) } }
    catch { fail(error.localizedDescription, file: file, line: line) }
}
func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { let left = try lhs(); let right = try rhs(); if left != right { fail("\(left) != \(right)", file: file, line: line) } }
    catch { fail(error.localizedDescription, file: file, line: line) }
}
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() != nil { fail("Expected nil", file: file, line: line) } }
    catch { fail(error.localizedDescription, file: file, line: line) }
}
func XCTAssertNotNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() == nil { fail("Expected non-nil", file: file, line: line) } }
    catch { fail(error.localizedDescription, file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); fail("Expected an error", file: file, line: line) } catch {}
}
func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected non-nil value"]) }
    return value
}
