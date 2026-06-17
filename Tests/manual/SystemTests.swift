import AVFoundation
import Foundation

func registerSystemTests() {
    TestRegistry.test("system info detects Apple Silicon from runtime hardware flag") {
        try expect(SystemInfo.detectAppleSilicon { name in
            name == "hw.optional.arm64" ? 1 : nil
        }, "sysctl arm64 flag 1 should be Apple Silicon")

        try expect(!SystemInfo.detectAppleSilicon { name in
            name == "hw.optional.arm64" ? 0 : nil
        }, "sysctl arm64 flag 0 should not be Apple Silicon")

        try expect(!SystemInfo.detectAppleSilicon { _ in nil }, "missing sysctl flag should fail closed")
    }

    TestRegistry.test("camera authorization decision separates request from authorized start") {
        try expectEqual(CameraManager.authorizationAction(for: .authorized), .start, "authorized should start capture")
        try expectEqual(CameraManager.authorizationAction(for: .notDetermined), .requestAccess, "undetermined should request once")
        try expectEqual(CameraManager.authorizationAction(for: .denied), .blocked("camera permission denied"), "denied should block")
        try expectEqual(CameraManager.authorizationAction(for: .restricted), .blocked("camera permission denied"), "restricted should block")
    }

    TestRegistry.test("camera burst timing discards warmup before collection") {
        try expect(!CameraBurstTiming.isCollecting(elapsed: 0.79), "warmup frames should be discarded")
        try expect(CameraBurstTiming.isCollecting(elapsed: 0.8), "collection starts after warmup")
        try expectApprox(CameraBurstTiming.collectionTime(elapsed: 1.0) ?? -1, 0.2, tolerance: 0.001, "collection timestamp")
        try expectApprox(CameraBurstTiming.totalDuration, 2.8, tolerance: 0.001, "warmup plus collection duration")
    }
}
