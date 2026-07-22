import CoreGraphics
import CoreMedia
import CoreML
import CoreVideo
import Foundation
import Vision

public final class CoreMLRelativeDepthProvider: @unchecked Sendable {
    private let modelName: String
    private let direction: DepthDirection
    private let modelLock = NSLock()
    private var cachedModel: VNCoreMLModel?
    private var loadFailed = false

    public init(
        modelName: String = "DepthAnythingV2SmallF16",
        direction: DepthDirection = Tuning.defaultDepthDirection
    ) {
        self.modelName = modelName
        self.direction = direction
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

    public func estimate(sampleBuffer: CMSampleBuffer) -> RelativeDepthMap? {
        guard let model = visionModel() else { return nil }
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        return estimate(handler: handler, model: model)
    }

    public func estimate(cgImage: CGImage) -> RelativeDepthMap? {
        guard let model = visionModel() else { return nil }
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        return estimate(handler: handler, model: model)
    }

    func debugImage(for map: RelativeDepthMap) -> CGImage? {
        visualization(map)
    }

    private func estimate(handler: VNImageRequestHandler, model: VNCoreMLModel) -> RelativeDepthMap? {
        var resultBuffer: CVPixelBuffer?
        var resultArray: MLMultiArray?
        let request = VNCoreMLRequest(model: model) { request, _ in
            if let observation = request.results?.compactMap({ $0 as? VNPixelBufferObservation }).first {
                resultBuffer = observation.pixelBuffer
            } else if let observation = request.results?.compactMap({ $0 as? VNCoreMLFeatureValueObservation }).first {
                resultBuffer = observation.featureValue.imageBufferValue
                resultArray = observation.featureValue.multiArrayValue
            }
        }
        request.imageCropAndScaleOption = .scaleFill
        guard (try? handler.perform([request])) != nil else { return nil }

        if let resultBuffer {
            return depthMap(pixelBuffer: resultBuffer)
        }
        if let resultArray {
            return depthMap(multiArray: resultArray)
        }
        return nil
    }

    private func visionModel() -> VNCoreMLModel? {
        modelLock.lock()
        defer { modelLock.unlock() }
        if let cachedModel { return cachedModel }
        guard !loadFailed, let url = modelURL() else {
            loadFailed = true
            return nil
        }

        do {
            let compiledURL = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let model = try MLModel(contentsOf: compiledURL, configuration: configuration)
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
            ?? developmentModelURL()
    }

    private func developmentModelURL() -> URL? {
        let resources = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).appendingPathComponent("Resources", isDirectory: true)
        for fileExtension in ["mlmodelc", "mlpackage", "mlmodel"] {
            let candidate = resources.appendingPathComponent("\(modelName).\(fileExtension)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func depthMap(pixelBuffer: CVPixelBuffer) -> RelativeDepthMap? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0, CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var values: [Double] = []
        values.reserveCapacity(width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow)
            switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
            case kCVPixelFormatType_OneComponent32Float:
                let pixels = row.assumingMemoryBound(to: Float.self)
                for x in 0..<width { values.append(Double(pixels[x])) }
            case kCVPixelFormatType_OneComponent16Half:
                let pixels = row.assumingMemoryBound(to: UInt16.self)
                for x in 0..<width { values.append(float16ToDouble(pixels[x])) }
            case kCVPixelFormatType_OneComponent8:
                let pixels = row.assumingMemoryBound(to: UInt8.self)
                for x in 0..<width { values.append(Double(pixels[x]) / 255) }
            default:
                return nil
            }
        }
        return RelativeDepthMap(width: width, height: height, values: values, direction: direction)
    }

    private func depthMap(multiArray: MLMultiArray) -> RelativeDepthMap? {
        let shape = multiArray.shape.map(\.intValue)
        guard shape.count >= 2 else { return nil }
        let height = shape[shape.count - 2]
        let width = shape[shape.count - 1]
        guard width > 0, height > 0 else { return nil }

        var values: [Double] = []
        values.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                let leading = Array(repeating: NSNumber(value: 0), count: shape.count - 2)
                values.append(multiArray[leading + [NSNumber(value: y), NSNumber(value: x)]].doubleValue)
            }
        }
        return RelativeDepthMap(width: width, height: height, values: values, direction: direction)
    }

    private func visualization(_ map: RelativeDepthMap) -> CGImage? {
        let finite = map.values.filter(\.isFinite)
        guard finite.count == map.values.count, let lower = finite.min(), let upper = finite.max() else { return nil }
        let range = max(upper - lower, .leastNonzeroMagnitude)
        let bytes = map.values.map { UInt8((max(0, min(1, ($0 - lower) / range)) * 255).rounded()) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: map.width,
            height: map.height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: map.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func float16ToDouble(_ bits: UInt16) -> Double {
        let sign = (bits & 0x8000) == 0 ? 1.0 : -1.0
        let exponent = Int((bits >> 10) & 0x1F)
        let fraction = Int(bits & 0x03FF)
        if exponent == 0 {
            return fraction == 0 ? sign * 0 : sign * pow(2, -14) * (Double(fraction) / 1024)
        }
        if exponent == 31 { return fraction == 0 ? sign * .infinity : .nan }
        return sign * pow(2, Double(exponent - 15)) * (1 + Double(fraction) / 1024)
    }
}
