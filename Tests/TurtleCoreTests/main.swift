import Darwin
import Foundation

registerWorkflowTests()
registerProductTests()

var failures = 0
for test in TestRegistry.cases {
    print("→ \(test.name)")
    let startedAt = Date()
    do {
        try test.body()
        let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        print("✓ \(test.name) (\(milliseconds)ms)")
    } catch {
        failures += 1
        print("✗ \(test.name): \(error)")
    }
}

print("\n\(TestRegistry.cases.count - failures)/\(TestRegistry.cases.count) tests passed")
if failures > 0 { exit(1) }
