import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct DebugCaptureSession: Equatable, Sendable {
    public let path: String

    fileprivate var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}

public final class DebugCaptureStore: @unchecked Sendable {
    private let rootURL: URL?
    private let ciContext = CIContext()

    public init(rootURL: URL? = nil) {
        self.rootURL = rootURL ?? Self.defaultRootURL()
    }

    public func prepareRun(now: Date = Date()) -> DebugCaptureSession? {
        guard let rootURL else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = rootURL.appendingPathComponent(formatter.string(from: now), isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return DebugCaptureSession(path: url.path)
        } catch {
            return nil
        }
    }

    func inputImage(from sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        return ciContext.createCGImage(image, from: image.extent)
    }

    public func writeFrame(
        session: DebugCaptureSession,
        index: Int,
        time: Double,
        inputImage: CGImage?,
        depthImage: CGImage?,
        analysis: FrameAnalysis
    ) {
        let runURL = session.url
        if let inputImage {
            write(inputImage, to: runURL.appendingPathComponent("capture-\(index).png"))
            if let overlay = overlay(inputImage, analysis: analysis) {
                write(overlay, to: runURL.appendingPathComponent("overlay-\(index).png"))
            }
        }
        if let depthImage {
            write(depthImage, to: runURL.appendingPathComponent("depth-\(index).png"))
        }
        writeJSON(
            DebugFrameReport(frame: index, time: time, analysis: analysis),
            to: runURL.appendingPathComponent("frame-\(index).json")
        )
    }

    public func writeSession(
        session: DebugCaptureSession,
        verdict: BurstVerdict?,
        calibrationResult: CalibrationResult?,
        diagnostic: PostureDiagnostic,
        baseline: Baseline?
    ) -> String {
        let runURL = session.url
        let report = DebugSessionReport(
            createdAt: ISO8601DateFormatter().string(from: Date()),
            verdict: verdict,
            calibrationResult: calibrationResult?.debugLabel,
            diagnostic: diagnostic,
            baseline: baseline,
            stageProcessingMilliseconds: diagnostic.stageProcessingMilliseconds
        )
        return writeJSON(report, to: runURL.appendingPathComponent("session.json")) ? runURL.path : ""
    }

    private func overlay(_ image: CGImage, analysis: FrameAnalysis) -> CGImage? {
        let width = image.width
        let height = image.height
        guard
            width > 0,
            height > 0,
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setLineWidth(max(1, Double(width) / 320))

        context.setFillColor(CGColor(red: 0.15, green: 0.9, blue: 0.35, alpha: 1))
        for point in allLandmarks(analysis.landmarks) {
            let radius = max(2, Double(width) / 180)
            let center = CGPoint(x: point.x * Double(width), y: (1 - point.y) * Double(height))
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }

        if let rois = analysis.rois {
            draw(rois.reference, color: CGColor(gray: 1, alpha: 0.9), in: context, width: width, height: height)
            draw(rois.head, color: CGColor(red: 1, green: 0.25, blue: 0.2, alpha: 1), in: context, width: width, height: height)
            draw(rois.torso, color: CGColor(red: 0.2, green: 0.55, blue: 1, alpha: 1), in: context, width: width, height: height)
        }
        return context.makeImage()
    }

    private func draw(_ rect: NormalizedRect, color: CGColor, in context: CGContext, width: Int, height: Int) {
        context.setStrokeColor(color)
        context.stroke(CGRect(
            x: rect.x * Double(width),
            y: (1 - rect.maxY) * Double(height),
            width: rect.width * Double(width),
            height: rect.height * Double(height)
        ))
    }

    private func allLandmarks(_ landmarks: PoseLandmarks) -> [Point2D] {
        [
            landmarks.nose,
            landmarks.leftEye,
            landmarks.rightEye,
            landmarks.leftEar,
            landmarks.rightEar,
            landmarks.neck,
            landmarks.leftShoulder,
            landmarks.rightShoulder
        ].compactMap { $0 }
    }

    private func write(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
    }

    @discardableResult
    private func writeJSON<T: Encodable>(_ value: T, to url: URL) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    static func defaultRootURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundlePath: String = Bundle.main.bundleURL.standardizedFileURL.path,
        executablePath: String = URL(fileURLWithPath: CommandLine.arguments.first ?? "").standardizedFileURL.path,
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        sourceFilePath: String = #filePath
    ) -> URL? {
        if let override = environment["TURTLEMECK_DEBUG_ROOT"], override.hasPrefix("/") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        for path in [sourceFilePath, bundlePath, executablePath, currentDirectory] {
            if let root = projectRoot(containingPackageManifestIn: path) {
                return root.appendingPathComponent("debug", isDirectory: true)
            }
            if let root = projectRoot(containingBuildDirectoryIn: path) {
                return root.appendingPathComponent("debug", isDirectory: true)
            }
        }
        return nil
    }

    private static func projectRoot(containingPackageManifestIn path: String) -> URL? {
        var candidate = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            candidate.deleteLastPathComponent()
        }
        while candidate.path != "/" {
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    private static func projectRoot(containingBuildDirectoryIn path: String) -> URL? {
        guard let range = path.range(of: "/.build/") else { return nil }
        return URL(fileURLWithPath: String(path[..<range.lowerBound]), isDirectory: true)
    }
}

private struct DebugFrameReport: Codable {
    var frame: Int
    var time: Double
    var analysis: FrameAnalysis
}

private struct DebugSessionReport: Codable {
    var createdAt: String
    var verdict: BurstVerdict?
    var calibrationResult: String?
    var diagnostic: PostureDiagnostic
    var baseline: Baseline?
    var stageProcessingMilliseconds: [String: Double]
}

private extension CalibrationResult {
    var debugLabel: String {
        switch self {
        case .accepted: "accepted"
        case .rejected(let reason): "rejected:\(reason.rawValue)"
        }
    }
}
