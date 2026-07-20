import Foundation

/// 한 RGB 프레임의 Vision 2D landmark와 DA-V2 map을 하나의 정규화 feature로 변환한다.
public struct PostureFrameAnalyzer: Sendable {
    public init() {}

    public func analyze(landmarks: PoseLandmarks, depthMap: RelativeDepthMap?) -> FrameAnalysis {
        guard let depthMap, depthMap.isValid else {
            return FrameAnalysis(landmarks: landmarks, exclusionReason: .modelFailure)
        }
        let depth = DepthSummary(map: depthMap)
        guard !landmarks.reliableHeadAnchors.isEmpty else {
            return FrameAnalysis(landmarks: landmarks, depth: depth, exclusionReason: .missingHeadAnchor)
        }
        guard let neck = landmarks.neck, neck.isReliable else {
            return FrameAnalysis(landmarks: landmarks, depth: depth, exclusionReason: .missingNeck)
        }
        guard
            let leftShoulder = landmarks.leftShoulder, leftShoulder.isReliable,
            let rightShoulder = landmarks.rightShoulder, rightShoulder.isReliable
        else {
            return FrameAnalysis(landmarks: landmarks, depth: depth, exclusionReason: .missingShoulder)
        }

        let shoulderWidth = distance(leftShoulder, rightShoulder)
        guard shoulderWidth >= Tuning.minimumShoulderWidth else {
            return FrameAnalysis(landmarks: landmarks, depth: depth, exclusionReason: .excessiveRotation)
        }
        guard abs(leftShoulder.y - rightShoulder.y) <= Tuning.maximumShoulderSlope else {
            return FrameAnalysis(landmarks: landmarks, depth: depth, exclusionReason: .excessiveRotation)
        }

        let requiredPoints = landmarks.reliableHeadAnchors + [neck, leftShoulder, rightShoulder]
        guard requiredPoints.allSatisfy(isInsideFrame) else {
            return FrameAnalysis(landmarks: landmarks, depth: depth, exclusionReason: .croppedUpperBody)
        }

        let rois = makeROIs(
            headAnchors: landmarks.reliableHeadAnchors,
            neck: neck,
            leftShoulder: leftShoulder,
            rightShoulder: rightShoulder,
            shoulderWidth: shoulderWidth
        )
        let boundaryContactRatio = max(
            rois.head.boundaryContactRatio,
            rois.torso.boundaryContactRatio,
            rois.reference.boundaryContactRatio
        )
        let landmarkConfidence = requiredPoints.map(\.confidence).min() ?? 0
        guard boundaryContactRatio <= Tuning.maximumROIBoundaryContactRatio else {
            return FrameAnalysis(
                landmarks: landmarks,
                rois: rois,
                depth: depth,
                quality: FrameQuality(
                    landmarkConfidence: landmarkConfidence,
                    roiBoundaryContactRatio: boundaryContactRatio
                ),
                exclusionReason: .croppedUpperBody
            )
        }
        guard rois.head.intersectionArea(with: rois.torso) <= min(rois.head.area, rois.torso.area) * Tuning.maximumROIOverlapRatio else {
            return FrameAnalysis(landmarks: landmarks, rois: rois, depth: depth, exclusionReason: .invalidROIGeometry)
        }

        let headValues = depthMap.values(in: rois.head)
        let torsoValues = depthMap.values(in: rois.torso)
        let referenceValues = depthMap.values(in: rois.reference)
        let headRatio = validRatio(headValues.count, rect: rois.head, map: depthMap)
        let torsoRatio = validRatio(torsoValues.count, rect: rois.torso, map: depthMap)
        let referenceRatio = validRatio(referenceValues.count, rect: rois.reference, map: depthMap)

        guard
            headValues.count >= Tuning.minimumROIPixels,
            torsoValues.count >= Tuning.minimumROIPixels,
            referenceValues.count >= Tuning.minimumROIPixels,
            headRatio >= Tuning.minimumValidDepthRatio,
            torsoRatio >= Tuning.minimumValidDepthRatio,
            referenceRatio >= Tuning.minimumValidDepthRatio
        else {
            return FrameAnalysis(
                landmarks: landmarks,
                rois: rois,
                depth: depth,
                quality: FrameQuality(
                    landmarkConfidence: landmarkConfidence,
                    headValidPixelRatio: headRatio,
                    torsoValidPixelRatio: torsoRatio,
                    referenceValidPixelRatio: referenceRatio,
                    roiBoundaryContactRatio: boundaryContactRatio
                ),
                exclusionReason: .insufficientDepthPixels
            )
        }

        guard
            let head = median(headValues),
            let torso = median(torsoValues),
            let referenceIQR = interquartileRange(referenceValues),
            referenceIQR >= Tuning.minimumReferenceIQR
        else {
            return FrameAnalysis(
                landmarks: landmarks,
                rois: rois,
                depth: depth,
                quality: FrameQuality(
                    landmarkConfidence: landmarkConfidence,
                    headValidPixelRatio: headRatio,
                    torsoValidPixelRatio: torsoRatio,
                    referenceValidPixelRatio: referenceRatio,
                    roiBoundaryContactRatio: boundaryContactRatio
                ),
                exclusionReason: .insufficientDepthRange
            )
        }

        let feature = depthMap.direction.multiplier * (head - torso) / referenceIQR
        return FrameAnalysis(
            landmarks: landmarks,
            rois: rois,
            depth: depth,
            feature: feature,
            quality: FrameQuality(
                landmarkConfidence: landmarkConfidence,
                headValidPixelRatio: headRatio,
                torsoValidPixelRatio: torsoRatio,
                referenceValidPixelRatio: referenceRatio,
                referenceIQR: referenceIQR,
                roiBoundaryContactRatio: boundaryContactRatio
            )
        )
    }

    private func makeROIs(
        headAnchors: [Point2D],
        neck: Point2D,
        leftShoulder: Point2D,
        rightShoulder: Point2D,
        shoulderWidth: Double
    ) -> PostureROIs {
        let headX = headAnchors.map(\.x).reduce(0, +) / Double(headAnchors.count)
        let headY = headAnchors.map(\.y).reduce(0, +) / Double(headAnchors.count)
        let shoulderX = (leftShoulder.x + rightShoulder.x) / 2

        let head = centeredRect(
            x: headX,
            y: headY,
            width: shoulderWidth * 0.54,
            height: shoulderWidth * 0.66
        ).inset(by: Tuning.roiErosionFraction)
        let torso = centeredRect(
            x: shoulderX,
            y: neck.y + shoulderWidth * 0.34,
            width: shoulderWidth * 0.83,
            height: shoulderWidth * 0.60
        ).inset(by: Tuning.roiErosionFraction)
        let padding = shoulderWidth * 0.08
        let reference = NormalizedRect(
            x: min(head.x, torso.x) - padding,
            y: min(head.y, torso.y) - padding,
            width: max(head.maxX, torso.maxX) - min(head.x, torso.x) + padding * 2,
            height: max(head.maxY, torso.maxY) - min(head.y, torso.y) + padding * 2
        ).inset(by: Tuning.roiErosionFraction / 3)
        return PostureROIs(head: head, torso: torso, reference: reference)
    }

    private func centeredRect(x: Double, y: Double, width: Double, height: Double) -> NormalizedRect {
        NormalizedRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
    }

    private func isInsideFrame(_ point: Point2D) -> Bool {
        let margin = Tuning.frameBoundaryMargin
        return point.x >= margin && point.x <= 1 - margin && point.y >= margin && point.y <= 1 - margin
    }

    private func distance(_ lhs: Point2D, _ rhs: Point2D) -> Double {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func validRatio(_ count: Int, rect: NormalizedRect, map: RelativeDepthMap) -> Double {
        let expected = max(1, Int((rect.area * Double(map.width * map.height)).rounded()))
        return min(1, Double(count) / Double(expected))
    }

    private func median(_ values: [Double]) -> Double? {
        percentile(values, 0.5)
    }

    private func interquartileRange(_ values: [Double]) -> Double? {
        guard let lower = percentile(values, 0.25), let upper = percentile(values, 0.75) else { return nil }
        return upper - lower
    }

    private func percentile(_ values: [Double], _ fraction: Double) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let rank = min(1, max(0, fraction)) * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Int(rank.rounded(.up))
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (rank - Double(lower))
    }
}
