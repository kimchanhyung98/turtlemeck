import CoreGraphics
import CoreMedia
import CoreML
import CoreVideo
import Foundation
import Vision

struct CoreMLRelativeDepthEstimate {
    var summary: RelativeDepthSummary
    var debugImage: CGImage?
}

public final class CoreMLRelativeDepthProvider: @unchecked Sendable {
    private let modelName: String
    private let modelLock = NSLock()
    private var cachedModel: VNCoreMLModel?
    private var loadFailed = false

    public init(modelName: String = "DepthAnythingV2SmallF16") {
        self.modelName = modelName
    }

    public var isModelLoadResolved: Bool {
        modelLock.lock()
        defer { modelLock.unlock() }
        return cachedModel != nil || loadFailed
    }

    @discardableResult
    public func prewarm() -> Bool {
        visionModel() != nil
    }

    public func estimate(sampleBuffer: CMSampleBuffer, landmarks: PoseLandmarks) -> RelativeDepthSummary? {
        estimateWithDebugImage(sampleBuffer: sampleBuffer, landmarks: landmarks, includeDebugImage: false)?.summary
    }

    func estimateWithDebugImage(
        sampleBuffer: CMSampleBuffer,
        landmarks: PoseLandmarks,
        includeDebugImage: Bool
    ) -> CoreMLRelativeDepthEstimate? {
        guard
            let anchors = DepthAnchors(landmarks: landmarks),
            let model = visionModel()
        else {
            return nil
        }

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        return estimate(handler: handler, model: model, anchors: anchors, includeDebugImage: includeDebugImage)
    }

    public func estimate(cgImage: CGImage, landmarks: PoseLandmarks) -> RelativeDepthSummary? {
        estimateWithDebugImage(cgImage: cgImage, landmarks: landmarks, includeDebugImage: false)?.summary
    }

    func estimateWithDebugImage(
        cgImage: CGImage,
        landmarks: PoseLandmarks,
        includeDebugImage: Bool
    ) -> CoreMLRelativeDepthEstimate? {
        guard
            let anchors = DepthAnchors(landmarks: landmarks),
            let model = visionModel()
        else {
            return nil
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        return estimate(handler: handler, model: model, anchors: anchors, includeDebugImage: includeDebugImage)
    }

    private func estimate(
        handler: VNImageRequestHandler,
        model: VNCoreMLModel,
        anchors: DepthAnchors,
        includeDebugImage: Bool
    ) -> CoreMLRelativeDepthEstimate? {
        var resultBuffer: CVPixelBuffer?
        var resultArray: MLMultiArray?
        let request = VNCoreMLRequest(model: model) { request, _ in
            if let observation = request.results?.compactMap({ $0 as? VNPixelBufferObservation }).first {
                resultBuffer = observation.pixelBuffer
                return
            }
            if let observation = request.results?.compactMap({ $0 as? VNCoreMLFeatureValueObservation }).first {
                resultBuffer = observation.featureValue.imageBufferValue
                resultArray = observation.featureValue.multiArrayValue
            }
        }
        request.imageCropAndScaleOption = .scaleFill

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let headValues: [Double]
        let shoulderValues: [Double]
        if let resultBuffer {
            guard let samples = sample(pixelBuffer: resultBuffer, anchors: anchors) else {
                return nil
            }
            headValues = samples.head
            shoulderValues = samples.shoulders
        } else if let resultArray {
            headValues = anchors.head.compactMap { sample(multiArray: resultArray, point: $0) }
            shoulderValues = anchors.shoulders.compactMap { sample(multiArray: resultArray, point: $0) }
        } else {
            return nil
        }

        guard
            let head = median(headValues),
            let shoulder = median(shoulderValues)
        else {
            return nil
        }

        let confidence = min(anchors.confidence, 0.6)
        let debugImage: CGImage?
        if includeDebugImage {
            if let resultBuffer {
                debugImage = visualization(pixelBuffer: resultBuffer)
            } else if let resultArray {
                debugImage = visualization(multiArray: resultArray)
            } else {
                debugImage = nil
            }
        } else {
            debugImage = nil
        }
        return CoreMLRelativeDepthEstimate(
            summary: RelativeDepthSummary(headCloserDelta: head - shoulder, confidence: confidence),
            debugImage: debugImage
        )
    }

    private func visionModel() -> VNCoreMLModel? {
        modelLock.lock()
        defer { modelLock.unlock() }

        if let cachedModel {
            return cachedModel
        }
        guard !loadFailed else {
            return nil
        }

        guard let url = modelURL() else {
            loadFailed = true
            return nil
        }

        do {
            let modelURL = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let model = try MLModel(contentsOf: modelURL, configuration: configuration)
            let visionModel = try VNCoreMLModel(for: model)
            cachedModel = visionModel
            return visionModel
        } catch {
            loadFailed = true
            return nil
        }
    }

    private func modelURL() -> URL? {
        Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: modelName, withExtension: "mlpackage")
            ?? Bundle.main.url(forResource: modelName, withExtension: "mlmodel")
    }

    private func sample(pixelBuffer: CVPixelBuffer, anchors: DepthAnchors) -> (head: [Double], shoulders: [Double])? {
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        return (
            head: anchors.head.compactMap { sampleLocked(pixelBuffer: pixelBuffer, point: $0) },
            shoulders: anchors.shoulders.compactMap { sampleLocked(pixelBuffer: pixelBuffer, point: $0) }
        )
    }

    private func sampleLocked(pixelBuffer: CVPixelBuffer, point: Point2D) -> Double? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else {
            return nil
        }
        let x = clamp(Int((point.x * Double(width - 1)).rounded()), min: 0, max: width - 1)
        let y = clamp(Int((point.y * Double(height - 1)).rounded()), min: 0, max: height - 1)

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let row = base.advanced(by: y * bytesPerRow)
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_OneComponent32Float:
            return Double(row.assumingMemoryBound(to: Float.self)[x])
        case kCVPixelFormatType_OneComponent16Half:
            return float16ToDouble(row.assumingMemoryBound(to: UInt16.self)[x])
        case kCVPixelFormatType_OneComponent8:
            return Double(row.assumingMemoryBound(to: UInt8.self)[x]) / 255
        default:
            return nil
        }
    }

    private func sample(multiArray: MLMultiArray, point: Point2D) -> Double? {
        let shape = multiArray.shape.map(\.intValue)
        guard shape.count >= 2 else {
            return nil
        }
        let height = shape[shape.count - 2]
        let width = shape[shape.count - 1]
        guard width > 0, height > 0 else {
            return nil
        }

        let x = clamp(Int((point.x * Double(width - 1)).rounded()), min: 0, max: width - 1)
        let y = clamp(Int((point.y * Double(height - 1)).rounded()), min: 0, max: height - 1)
        let index: [NSNumber]
        if shape.count == 2 {
            index = [NSNumber(value: y), NSNumber(value: x)]
        } else {
            index = Array(repeating: NSNumber(value: 0), count: shape.count - 2) + [NSNumber(value: y), NSNumber(value: x)]
        }
        return multiArray[index].doubleValue
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func visualization(pixelBuffer: CVPixelBuffer) -> CGImage? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else {
            return nil
        }

        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var values: [Double] = []
        values.reserveCapacity(width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow)
            switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
            case kCVPixelFormatType_OneComponent32Float:
                let pixels = row.assumingMemoryBound(to: Float.self)
                for x in 0..<width {
                    values.append(Double(pixels[x]))
                }
            case kCVPixelFormatType_OneComponent16Half:
                let pixels = row.assumingMemoryBound(to: UInt16.self)
                for x in 0..<width {
                    values.append(float16ToDouble(pixels[x]))
                }
            case kCVPixelFormatType_OneComponent8:
                let pixels = row.assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    values.append(Double(pixels[x]) / 255)
                }
            default:
                return nil
            }
        }
        return grayscaleImage(values: values, width: width, height: height)
    }

    private func visualization(multiArray: MLMultiArray) -> CGImage? {
        let shape = multiArray.shape.map(\.intValue)
        guard shape.count >= 2 else {
            return nil
        }
        let height = shape[shape.count - 2]
        let width = shape[shape.count - 1]
        guard width > 0, height > 0 else {
            return nil
        }

        var values: [Double] = []
        values.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let index: [NSNumber]
                if shape.count == 2 {
                    index = [NSNumber(value: y), NSNumber(value: x)]
                } else {
                    index = Array(repeating: NSNumber(value: 0), count: shape.count - 2) + [NSNumber(value: y), NSNumber(value: x)]
                }
                values.append(multiArray[index].doubleValue)
            }
        }
        return grayscaleImage(values: values, width: width, height: height)
    }

    private func grayscaleImage(values: [Double], width: Int, height: Int) -> CGImage? {
        let finite = values.filter(\.isFinite)
        guard
            finite.count == values.count,
            let minValue = finite.min(),
            let maxValue = finite.max()
        else {
            return nil
        }

        let range = max(maxValue - minValue, .leastNonzeroMagnitude)
        var bytes = [UInt8]()
        bytes.reserveCapacity(values.count)
        for value in values {
            let normalized = max(0, min(1, (value - minValue) / range))
            bytes.append(UInt8((normalized * 255).rounded()))
        }

        guard
            let provider = CGDataProvider(data: Data(bytes) as CFData)
        else {
            return nil
        }

        return CGImage(
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
    }

    private func clamp(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
        min(max(value, minValue), maxValue)
    }

    private func float16ToDouble(_ bits: UInt16) -> Double {
        let sign = (bits & 0x8000) == 0 ? 1.0 : -1.0
        let exponent = Int((bits >> 10) & 0x1F)
        let fraction = Int(bits & 0x03FF)

        if exponent == 0 {
            guard fraction != 0 else {
                return sign * 0
            }
            return sign * pow(2.0, -14.0) * (Double(fraction) / 1024.0)
        }
        if exponent == 31 {
            return fraction == 0 ? sign * Double.infinity : Double.nan
        }
        return sign * pow(2.0, Double(exponent - 15)) * (1.0 + Double(fraction) / 1024.0)
    }
}

private struct DepthAnchors {
    let head: [Point2D]
    let shoulders: [Point2D]
    let confidence: Double

    init?(landmarks: PoseLandmarks) {
        let head = [landmarks.nose, landmarks.leftEye, landmarks.rightEye, landmarks.leftEar, landmarks.rightEar]
            .compactMap { $0 }
            .filter(\.isTrackable)
        let shoulders = [landmarks.leftShoulder, landmarks.rightShoulder, landmarks.neck]
            .compactMap { $0 }
            .filter(\.isTrackable)
        guard !head.isEmpty, shoulders.count >= 2 else {
            return nil
        }

        self.head = head
        self.shoulders = shoulders
        self.confidence = (head + shoulders).map(\.confidence).min() ?? Tuning.minimumTrackingConfidence
    }
}
