import Foundation
import Darwin

public struct SystemInfo: Equatable, Sendable {
    public let isAppleSilicon: Bool

    public init(isAppleSilicon: Bool) {
        self.isAppleSilicon = isAppleSilicon
    }

    public static let current = SystemInfo(isAppleSilicon: detectAppleSilicon(query: sysctlInt32, machine: machineHardwareName))

    public var canRequestVision3D: Bool {
        isAppleSilicon && !Self.isCodexSeatbeltSandboxed
    }

    public static func detectAppleSilicon(query: (String) -> Int32?) -> Bool {
        query("hw.optional.arm64") == 1
    }

    public static func detectAppleSilicon(query: (String) -> Int32?, machine: () -> String?) -> Bool {
        if let flag = query("hw.optional.arm64") {
            return flag == 1
        }
        return machine() == "arm64"
    }

    public static var isCodexSeatbeltSandboxed: Bool {
        ProcessInfo.processInfo.environment["CODEX_SANDBOX"] == "seatbelt"
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

    private static func machineHardwareName() -> String? {
        var value = utsname()
        guard uname(&value) == 0 else {
            return nil
        }

        var machineName = value.machine
        let capacity = MemoryLayout.size(ofValue: machineName)
        return withUnsafePointer(to: &machineName) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { machine in
                String(cString: machine)
            }
        }
    }
}
