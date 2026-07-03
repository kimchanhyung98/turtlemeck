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
        try expectEqual(CameraBurstTiming.collectionTime(elapsed: 3.81), nil, "late frames should be discarded")
        try expectApprox(CameraBurstTiming.totalDuration, 3.8, tolerance: 0.001, "warmup plus collection duration")
        try expectApprox(CameraBurstTiming.finishDelay, 5.8, tolerance: 0.001, "processing grace after capture stop")
    }

    TestRegistry.test("debug capture fallback uses user-writable cache root") {
        let fallback = URL(fileURLWithPath: "/tmp/turtlemeck-cache-test", isDirectory: true)
        let url = DebugCaptureStore.defaultRootURL(
            environment: [:],
            bundlePath: "/Applications/turtlemeck.app",
            executablePath: "/Applications/turtlemeck.app/Contents/MacOS/turtlemeck",
            fallbackBaseURL: fallback
        )

        try expectEqual(url.path, "/tmp/turtlemeck-cache-test/turtlemeck/debug", "packaged app fallback should not depend on current working directory")
    }

    TestRegistry.test("debug capture store clears latest run") {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("turtlemeck-debug-\(UUID().uuidString)", isDirectory: true)
        let store = DebugCaptureStore(rootURL: root)
        store.prepareLatestRun()
        let marker = root.appendingPathComponent("latest", isDirectory: true).appendingPathComponent("marker.txt")
        try "debug".write(to: marker, atomically: true, encoding: .utf8)
        try expect(FileManager.default.fileExists(atPath: marker.path), "debug marker should exist before clear")

        store.clearLatestRun()

        try expect(!FileManager.default.fileExists(atPath: marker.path), "debug marker should be removed after clear")
        try? FileManager.default.removeItem(at: root)
    }

    TestRegistry.test("core ml prewarm marks missing model load as resolved") {
        let provider = CoreMLRelativeDepthProvider(modelName: "MissingModelForPrewarmTest")
        try expect(!provider.isModelLoadResolved, "new provider starts unresolved")
        try expect(!provider.prewarm(), "missing model cannot prewarm")
        try expect(provider.isModelLoadResolved, "failed model lookup should still resolve the first-load state")
    }

    TestRegistry.test("package script compiles Core ML source models before bundling") {
        let script = try String(contentsOfFile: "scripts/package-app.sh", encoding: .utf8)
        try expect(script.contains("coremlcompiler compile"), "package script should compile mlpackage/mlmodel into mlmodelc")
        try expect(!script.contains("for ext in mlmodelc mlpackage mlmodel"), "package script should not bundle source model packages by default")
    }
}
