import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}

struct TestCase {
    let name: String
    let run: () throws -> Void
}

enum TestRegistry {
    static var tests: [TestCase] = []

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

@main
enum ManualTestRunner {
    static func main() {
        registerDetectionTests()
        registerStateTests()
        registerStorageTests()
        registerSystemTests()

        var failures: [(String, Error)] = []
        var assertions = 0

        for test in TestRegistry.tests {
            do {
                try test.run()
                assertions += 1
                print("PASS \(test.name)")
            } catch {
                failures.append((test.name, error))
                print("FAIL \(test.name): \(error)")
            }
        }

        print("\n\(TestRegistry.tests.count) tests, \(assertions) passed, \(failures.count) failed")

        if !failures.isEmpty {
            exit(1)
        }
    }
}
