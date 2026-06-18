import Foundation
import Darwin

public struct SystemInfo: Equatable, Sendable {
    public let isAppleSilicon: Bool

    public init(isAppleSilicon: Bool) {
        self.isAppleSilicon = isAppleSilicon
    }

    public static let current = SystemInfo(isAppleSilicon: detectAppleSilicon(query: sysctlInt32))

    public static func detectAppleSilicon(query: (String) -> Int32?) -> Bool {
        query("hw.optional.arm64") == 1
    }

    private static func sysctlInt32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        guard result == 0 else {
            return nil
        }
        return value
    }
}
