import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class DebugCaptureStore: @unchecked Sendable {
    private let latestURL: URL
    private let ciContext = CIContext()

    init(rootURL: URL? = nil) {
        let root = rootURL ?? Self.defaultRootURL()
        latestURL = root.appendingPathComponent("latest", isDirectory: true)
    }

    var latestPath: String {
        latestURL.path
    }

    func prepareLatestRun() {
        try? FileManager.default.removeItem(at: latestURL)
        try? FileManager.default.createDirectory(at: latestURL, withIntermediateDirectories: true)
    }

    func clearLatestRun() {
        try? FileManager.default.removeItem(at: latestURL)
    }

    func inputImage(from sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        let image = CIImage(cvPixelBuffer: buffer)
        return ciContext.createCGImage(image, from: image.extent)
    }

    func writeImages(index: Int, inputImage: CGImage?, depthImage: CGImage?) {
        let prefix = framePrefix(index)
        if let inputImage {
            write(inputImage, to: latestURL.appendingPathComponent("\(prefix)-capture.png"))
        }
        if let depthImage {
            write(depthImage, to: latestURL.appendingPathComponent("\(prefix)-depth.png"))
        }
    }

    func writeFrameAnalysis(index: Int, time: Double, frame: AnalyzedFrame) {
        let report = DebugFrameReport(
            frame: index,
            time: time,
            assessment: frame.assessment,
            signalKind: frame.signal?.kind,
            value: frame.signal?.angleDegrees,
            confidence: frame.signal?.confidence,
            viewpoint: frame.viewpoint?.band,
            reason: frame.reason,
            debugNotes: frame.debugNotes
        )
        writeJSON(report, to: latestURL.appendingPathComponent("\(framePrefix(index))-analysis.json"))
    }

    func writeFinalAnalysis(
        mode: String,
        verdict: BurstVerdict?,
        calibrationResult: CalibrationResult?,
        diagnostic: PostureDiagnostic?,
        frames: [TimedFrame],
        settings: Settings,
        baseline: Baseline?
    ) -> String {
        let report = DebugRunReport(
            createdAt: ISO8601DateFormatter().string(from: Date()),
            mode: mode,
            algorithm: settings.postureAlgorithm,
            sensitivity: settings.sensitivity,
            baseline: baseline,
            verdict: verdict?.assessment,
            calibrationResult: calibrationResult?.debugLabel,
            diagnostic: diagnostic,
            frames: frames.enumerated().map { offset, item in
                DebugFrameReport(
                    frame: item.index ?? (offset + 1),
                    time: item.time,
                    assessment: item.frame.assessment,
                    signalKind: item.frame.signal?.kind,
                    value: item.frame.signal?.angleDegrees,
                    confidence: item.frame.signal?.confidence,
                    viewpoint: item.frame.viewpoint?.band,
                    reason: item.frame.reason,
                    debugNotes: item.frame.debugNotes
                )
            }
        )
        writeJSON(report, to: latestURL.appendingPathComponent("analysis.json"))
        return latestPath
    }

    private func write(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    private func framePrefix(_ index: Int) -> String {
        "frame-\(String(format: "%02d", index))"
    }

    static func defaultRootURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundlePath: String = Bundle.main.bundleURL.standardizedFileURL.path,
        executablePath: String = URL(fileURLWithPath: CommandLine.arguments.first ?? "").standardizedFileURL.path,
        fallbackBaseURL: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    ) -> URL {
        if let override = environment["TURTLEMECK_DEBUG_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        if let projectRoot = projectRoot(containingBuildDirectoryIn: bundlePath) {
            return projectRoot.appendingPathComponent("debug", isDirectory: true)
        }

        if let projectRoot = projectRoot(containingBuildDirectoryIn: executablePath) {
            return projectRoot.appendingPathComponent("debug", isDirectory: true)
        }

        let fallbackBaseURL = fallbackBaseURL ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return fallbackBaseURL
            .appendingPathComponent("turtlemeck", isDirectory: true)
            .appendingPathComponent("debug", isDirectory: true)
    }

    private static func projectRoot(containingBuildDirectoryIn path: String) -> URL? {
        if let range = path.range(of: "/.build/") {
            let rootPath = String(path[..<range.lowerBound])
            return URL(fileURLWithPath: rootPath, isDirectory: true)
        }
        if path.hasSuffix("/.build") {
            let rootPath = String(path.dropLast("/.build".count))
            return URL(fileURLWithPath: rootPath, isDirectory: true)
        }
        return nil
    }
}

private struct DebugRunReport: Codable {
    var createdAt: String
    var mode: String
    var algorithm: PostureAlgorithmID
    var sensitivity: Sensitivity
    var baseline: Baseline?
    var verdict: PostureAssessment?
    var calibrationResult: String?
    var diagnostic: PostureDiagnostic?
    var frames: [DebugFrameReport]
}

private struct DebugFrameReport: Codable {
    var frame: Int
    var time: Double
    var assessment: PostureAssessment
    var signalKind: SignalKind?
    var value: Double?
    var confidence: Double?
    var viewpoint: ViewpointBand?
    var reason: String?
    var debugNotes: [String]
}

private extension CalibrationResult {
    var debugLabel: String {
        switch self {
        case .accepted:
            return "accepted"
        case .rejected(let reason):
            return "rejected:\(reason.rawValue)"
        }
    }
}
