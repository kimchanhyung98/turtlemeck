import Foundation
import TurtleCore

let testCaptureConfiguration = CaptureConfiguration(
    cameraUniqueID: "test-camera",
    width: 640,
    height: 480,
    orientation: "up-unmirrored"
)

struct TestFailure: Error, CustomStringConvertible {
    var description: String
}

struct TestCase {
    var name: String
    var body: () throws -> Void
}

enum TestRegistry {
    nonisolated(unsafe) static var cases: [TestCase] = []

    static func test(_ name: String, _ body: @escaping () throws -> Void) {
        cases.append(TestCase(name: name, body: body))
    }
}

func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    guard condition() else { throw testFailure(message, file: file, line: line) }
}

func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: String,
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    guard actual == expected else {
        throw testFailure("\(message): expected \(expected), got \(actual)", file: file, line: line)
    }
}

func expectApprox(
    _ actual: Double,
    _ expected: Double,
    accuracy: Double = 1e-9,
    _ message: String,
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    guard abs(actual - expected) <= accuracy else {
        throw testFailure("\(message): expected \(expected), got \(actual)", file: file, line: line)
    }
}

func unwrap<T>(
    _ value: T?,
    _ message: String,
    file: StaticString = #fileID,
    line: UInt = #line
) throws -> T {
    guard let value else { throw testFailure(message, file: file, line: line) }
    return value
}

func testFailure(
    _ message: String,
    file: StaticString = #fileID,
    line: UInt = #line
) -> TestFailure {
    TestFailure(description: "\(file):\(line): \(message)")
}
