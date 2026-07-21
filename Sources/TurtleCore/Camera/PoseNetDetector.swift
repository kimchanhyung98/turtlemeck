import CoreGraphics
import CoreML
import CoreMedia
import Foundation
import VideoToolbox
import Vision

final class PoseNetDetector {
    private static let modelName = "PoseNetMobileNet075S16FP16"
    fileprivate static let inputSize = 513
    private static let outputStride = 16
    private var model: MLModel?

    func detect(sampleBuffer: CMSampleBuffer) throws -> [PoseLandmarks] {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw PoseNetError.imageUnavailable
        }
        var image: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image) == noErr,
              let image else {
            throw PoseNetError.imageUnavailable
        }
        return try detect(cgImage: image)
    }

    func detect(cgImage: CGImage) throws -> [PoseLandmarks] {
        let prediction = try loadedModel().prediction(from: PoseNetInput(image: cgImage))
        guard let heatmap = prediction.featureValue(for: "heatmap")?.multiArrayValue,
              let offsets = prediction.featureValue(for: "offsets")?.multiArrayValue else {
            throw PoseNetError.outputUnavailable
        }

        let points = PoseNetJoint.allCases.map { joint in
            point(for: joint, heatmap: heatmap, offsets: offsets)
        }
        return [PoseLandmarks(
            nose: points[PoseNetJoint.nose.rawValue],
            leftEye: points[PoseNetJoint.leftEye.rawValue],
            rightEye: points[PoseNetJoint.rightEye.rawValue],
            leftEar: points[PoseNetJoint.leftEar.rawValue],
            rightEar: points[PoseNetJoint.rightEar.rawValue],
            leftShoulder: points[PoseNetJoint.leftShoulder.rawValue],
            rightShoulder: points[PoseNetJoint.rightShoulder.rawValue]
        )]
    }

    private func loadedModel() throws -> MLModel {
        if let model { return model }
        guard let url = modelURL() else { throw PoseNetError.modelUnavailable }
        let compiledURL = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let loaded = try MLModel(contentsOf: compiledURL, configuration: configuration)
        model = loaded
        return loaded
    }

    private func modelURL() -> URL? {
        Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodel")
            ?? developmentModelURL()
    }

    private func developmentModelURL() -> URL? {
        let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        for fileExtension in ["mlmodelc", "mlmodel"] {
            let candidate = resources.appendingPathComponent("\(Self.modelName).\(fileExtension)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private func point(for joint: PoseNetJoint, heatmap: MLMultiArray, offsets: MLMultiArray) -> Point2D {
        let height = heatmap.shape[1].intValue
        let width = heatmap.shape[2].intValue
        var bestY = 0
        var bestX = 0
        var bestConfidence = -Double.infinity
        for y in 0..<height {
            for x in 0..<width {
                let confidence = heatmap[valueIndex(joint.rawValue, y, x)].doubleValue
                if confidence > bestConfidence {
                    bestConfidence = confidence
                    bestY = y
                    bestX = x
                }
            }
        }

        let yOffset = offsets[valueIndex(joint.rawValue, bestY, bestX)].doubleValue
        let xOffset = offsets[valueIndex(joint.rawValue + PoseNetJoint.allCases.count, bestY, bestX)].doubleValue
        return Point2D(
            x: (Double(bestX * Self.outputStride) + xOffset) / Double(Self.inputSize),
            y: (Double(bestY * Self.outputStride) + yOffset) / Double(Self.inputSize),
            confidence: bestConfidence
        )
    }

    private func valueIndex(_ first: Int, _ second: Int, _ third: Int) -> [NSNumber] {
        [NSNumber(value: first), NSNumber(value: second), NSNumber(value: third)]
    }
}

private final class PoseNetInput: MLFeatureProvider {
    let image: CGImage
    var featureNames: Set<String> { ["image"] }

    init(image: CGImage) {
        self.image = image
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        guard featureName == "image" else { return nil }
        return try? MLFeatureValue(
            cgImage: image,
            pixelsWide: PoseNetDetector.inputSize,
            pixelsHigh: PoseNetDetector.inputSize,
            pixelFormatType: kCVPixelFormatType_32BGRA,
            options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue]
        )
    }
}

private enum PoseNetJoint: Int, CaseIterable {
    case nose
    case leftEye
    case rightEye
    case leftEar
    case rightEar
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

private enum PoseNetError: Error {
    case modelUnavailable
    case imageUnavailable
    case outputUnavailable
}
