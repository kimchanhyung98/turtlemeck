import Foundation

/// 한 RGB 프레임의 2D pose landmark와 DA-V2 map을 하나의 정규화 feature로 변환한다.
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
        guard
            let leftShoulder = landmarks.leftShoulder, leftShoulder.isReliable,
            let rightShoulder = landmarks.rightShoulder, rightShoulder.isReliable,
            let geometry = landmarks.upperBodyGeometry
        else {
            return FrameAnalysis(landmarks: landmarks, depth: depth, exclusionReason: .missingShoulder)
        }

        let shoulderWidth = geometry.shoulderWidth
        guard shoulderWidth >= Tuning.minimumShoulderWidth else {
            return FrameAnalysis(landmarks: landmarks, depth: depth, exclusionReason: .excessiveRotation)
        }
        guard geometry.isHeadAnchoredSide || abs(leftShoulder.y - rightShoulder.y) <= Tuning.maximumShoulderSlope else {
            return FrameAnalysis(landmarks: landmarks, depth: depth, exclusionReason: .excessiveRotation)
        }

        // 기준 어깨 신뢰도가 낮으면 정상 자세를 확인할 수 없다. 측면에서 반대쪽 점만 위의
        // 의자·헤드레스트로 튄 경우에는 upperBodyGeometry가 신뢰 가능한 머리 아래 어깨를 고른다.
        guard geometry.assessableShoulderConfidence >= Tuning.minimumAssessableShoulderConfidence else {
            return FrameAnalysis(landmarks: landmarks, depth: depth, exclusionReason: .missingShoulder)
        }

        // 머리(신뢰 anchor 중앙값)가 어깨선에 비정상적으로 가까우면 옆으로 기울거나 앞으로 숙인 자세다.
        if let headAnchorY = median(landmarks.reliableHeadAnchors.map(\.y)) {
            if (geometry.headShoulderY - headAnchorY) / shoulderWidth < Tuning.minimumHeadShoulderGapRatio {
                return FrameAnalysis(landmarks: landmarks, depth: depth, exclusionReason: .headDropped)
            }
        }

        let requiredPoints = landmarks.reliableHeadAnchors + [leftShoulder, rightShoulder]
        guard requiredPoints.allSatisfy(isInsideFrame) else {
            return FrameAnalysis(landmarks: landmarks, depth: depth, exclusionReason: .croppedUpperBody)
        }

        let rawROIs = makeROIs(
            headAnchors: landmarks.reliableHeadAnchors,
            shoulderX: geometry.centerX,
            shoulderY: geometry.shoulderY,
            shoulderWidth: shoulderWidth
        )
        let boundaryContactRatio = max(
            rawROIs.head.boundaryContactRatio,
            rawROIs.torso.boundaryContactRatio,
            rawROIs.reference.boundaryContactRatio
        )
        let landmarkConfidence = requiredPoints.map(\.confidence).min() ?? 0
        guard boundaryContactRatio <= Tuning.maximumROIBoundaryContactRatio else {
            return FrameAnalysis(
                landmarks: landmarks,
                rois: rawROIs,
                depth: depth,
                quality: FrameQuality(
                    landmarkConfidence: landmarkConfidence,
                    roiBoundaryContactRatio: boundaryContactRatio
                ),
                exclusionReason: .croppedUpperBody
            )
        }
        let rois = PostureROIs(
            head: rawROIs.head.clippedToUnitSquare,
            torso: rawROIs.torso.clippedToUnitSquare,
            reference: rawROIs.reference.clippedToUnitSquare
        )
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
        shoulderX: Double,
        shoulderY: Double,
        shoulderWidth: Double
    ) -> PostureROIs {
        let headX = median(headAnchors.map(\.x)) ?? 0
        let headY = median(headAnchors.map(\.y)) ?? 0

        let head = centeredRect(
            x: headX,
            y: headY,
            width: shoulderWidth * 0.54,
            height: shoulderWidth * 0.66
        ).inset(by: Tuning.roiErosionFraction)
        // 몸통 ROI는 어깨선 바로 아래의 얇은 상흉부 밴드다. 노트북 내장캠의 전형 구도(어깨 y 0.86~0.93)에서
        // 어깨 아래 0.34sw 배치는 프레임 하단을 항상 벗어났다(2026-07-21~22 debug 42프레임 전수 실측).
        // 밴드(0.05sw, 높이 0.20sw)는 같은 데이터에서 45/45 프레임 화면 안 + 나쁜 자세 분리 유지가 검증됐다.
        let torso = centeredRect(
            x: shoulderX,
            y: shoulderY + shoulderWidth * 0.05,
            width: shoulderWidth * 0.83,
            height: shoulderWidth * 0.20
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

    private func validRatio(_ count: Int, rect: NormalizedRect, map: RelativeDepthMap) -> Double {
        let expected = max(1, Int((rect.area * Double(map.width * map.height)).rounded()))
        return min(1, Double(count) / Double(expected))
    }

    private func median(_ values: [Double]) -> Double? {
        // ROI 경로는 기존 percentile 보간 연산을 유지한다. 짝수 표본의 반올림은 Statistics.median과 다를 수 있다.
        Statistics.percentile(values, 0.5)
    }

    private func interquartileRange(_ values: [Double]) -> Double? {
        Statistics.interquartileRange(values)
    }
}
