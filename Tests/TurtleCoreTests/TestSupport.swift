import CoreGraphics
import Foundation
import Testing
@testable import TurtleCore

struct TestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}

struct TestCase: @unchecked Sendable, CustomTestStringConvertible {
    let name: String
    let run: () throws -> Void

    var testDescription: String {
        name
    }
}

enum TestRegistry {
    nonisolated(unsafe) static var tests: [TestCase] = []

    static func test(_ name: String, _ body: @escaping () throws -> Void) {
        tests.append(TestCase(name: name, run: body))
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw TestFailure(message: message)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    if actual != expected {
        throw TestFailure(message: "\(message): expected \(expected), got \(actual)")
    }
}

func expectApprox(_ actual: Double, _ expected: Double, tolerance: Double = 0.001, _ message: String) throws {
    if abs(actual - expected) > tolerance {
        throw TestFailure(message: "\(message): expected \(expected), got \(actual)")
    }
}

func confident(_ x: Double, _ y: Double) -> Point2D {
    Point2D(x: x, y: y, confidence: 0.95)
}

func lowConfidence(_ x: Double, _ y: Double) -> Point2D {
    Point2D(x: x, y: y, confidence: 0.2)
}

func p3(_ x: Double, _ y: Double, _ z: Double) -> Point3D {
    Point3D(x: x, y: y, z: z, confidence: 0.95)
}

func tinyTestImage() throws -> CGImage {
    let width = 2
    let height = 2
    let bytes: [UInt8] = [0, 64, 128, 255]
    let data = Data(bytes)
    guard
        let provider = CGDataProvider(data: data as CFData),
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    else {
        throw TestFailure(message: "failed to create tiny test image")
    }
    return image
}

private let testCases: [TestCase] = {
    registerDetectionTests()
    registerStateTests()
    registerStorageTests()
    registerSystemTests()
    registerRoutingTests()

    return TestRegistry.tests
}()

@Suite("TurtleCore")
struct TurtleCoreTests {
    @Test(arguments: testCases)
    func run(_ testCase: TestCase) throws {
        try testCase.run()
    }
}
