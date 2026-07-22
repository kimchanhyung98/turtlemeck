import Foundation

/// 공통 분석 결과를 읽기만 하는 디버그 표시 문자열. 이 값은 판정 경로에 입력되지 않는다.
extension AppModel {
    public var debugLines: [String] {
        Self.debugLines(diagnostic: latestDiagnostic, settings: settings)
    }

    public nonisolated static func debugLines(diagnostic: PostureDiagnostic?, settings: Settings) -> [String] {
        var lines: [String] = []
        if let diagnostic {
            let reason = diagnostic.reason.map { " — \($0)" } ?? ""
            lines.append("제품 상태  \(diagnostic.productState.rawValue)")
            lines.append("이번 버스트  \(Self.assessmentLabel(diagnostic.assessment))\(reason)")
            lines.append("증거  \(diagnostic.evidence.rawValue)")
            let summary = diagnostic.summary
            lines.append("버스트  프레임=\(summary.totalFrameCount)  유효=\(summary.validFrameCount)")
            if let feature = summary.medianFeature, let mad = summary.featureMAD {
                lines.append("feature  중앙값=\(String(format: "%.3f", feature))  MAD=\(String(format: "%.3f", mad))")
            }
            if let center = diagnostic.baselineCenter {
                let delta = diagnostic.baselineDelta.map { String(format: "%.3f", $0) } ?? "-"
                lines.append("baseline  중심=\(String(format: "%.3f", center))  delta=\(delta)")
            }
            if !summary.exclusionCounts.isEmpty {
                let exclusions = summary.exclusionCounts
                    .sorted { $0.key.rawValue < $1.key.rawValue }
                    .map { "\($0.key.rawValue)=\($0.value)" }
                    .joined(separator: " · ")
                lines.append("제외  \(exclusions)")
            }
            for frame in diagnostic.frames.sorted(by: { $0.index < $1.index }) {
                let analysis = frame.analysis
                let feature = analysis.feature.map { String(format: "%.3f", $0) } ?? "-"
                let exclusion = analysis.exclusionReason?.rawValue ?? "none"
                lines.append("프레임 \(frame.index)  feature=\(feature)  제외=\(exclusion)")
                lines.append("landmark  \(Self.landmarkSummary(analysis.landmarks))")
                lines.append("ROI  \(Self.roiSummary(analysis.rois))")
                lines.append("depth·품질  \(Self.depthAndQualitySummary(analysis))")
            }
            if !diagnostic.stageProcessingMilliseconds.isEmpty {
                let timings = diagnostic.stageProcessingMilliseconds
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\(String(format: "%.1f", $0.value))ms" }
                    .joined(separator: " · ")
                lines.append("처리 시간  \(timings)")
            }
            if let path = diagnostic.debugArtifactPath {
                lines.append("파일  \(path)")
            } else if settings.debugEnabled {
                lines.append("파일  출력 불가 — 프로젝트 root 또는 TURTLEMECK_DEBUG_ROOT 확인")
            }
        } else {
            lines.append("아직 측정 데이터 없음 (점검 대기)")
        }
        lines.append("보정  \(Self.baselineSummary(settings.baseline))")
        lines.append("환경  주기=\(settings.checkIntervalSeconds)s")
        return lines
    }

    nonisolated static func describe(_ diagnostic: PostureDiagnostic) -> String {
        let feature = diagnostic.summary.medianFeature.map { String(format: "%.3f", $0) } ?? "-"
        return "\(assessmentLabel(diagnostic.assessment)) · feature \(feature) · \(diagnostic.evidence.rawValue)"
    }

    private nonisolated static func landmarkSummary(_ landmarks: PoseLandmarks) -> String {
        landmarks.namedPoints.map { name, point in
            guard let point else { return "\(name)=-" }
            return "\(name)=(\(String(format: "%.2f", point.x)),\(String(format: "%.2f", point.y)),c=\(String(format: "%.2f", point.confidence)))"
        }.joined(separator: " · ")
    }

    private nonisolated static func roiSummary(_ rois: PostureROIs?) -> String {
        guard let rois else { return "-" }
        func describe(_ rect: NormalizedRect) -> String {
            "(\(String(format: "%.2f", rect.x)),\(String(format: "%.2f", rect.y)),\(String(format: "%.2f", rect.width)),\(String(format: "%.2f", rect.height)))"
        }
        return "head=\(describe(rois.head)) · torso=\(describe(rois.torso)) · reference=\(describe(rois.reference))"
    }

    private nonisolated static func depthAndQualitySummary(_ analysis: FrameAnalysis) -> String {
        let depth: String
        if let summary = analysis.depth {
            let range = if let minimum = summary.minimum, let maximum = summary.maximum {
                "\(String(format: "%.3f", minimum))...\(String(format: "%.3f", maximum))"
            } else {
                "-"
            }
            depth = "\(summary.width)x\(summary.height) \(summary.direction.rawValue) range=\(range)"
        } else {
            depth = "-"
        }
        let quality = analysis.quality
        return "\(depth) · confidence=\(String(format: "%.2f", quality.landmarkConfidence)) · pixels=\(String(format: "%.2f", quality.headValidPixelRatio))/\(String(format: "%.2f", quality.torsoValidPixelRatio))/\(String(format: "%.2f", quality.referenceValidPixelRatio)) · IQR=\(quality.referenceIQR.map { String(format: "%.3f", $0) } ?? "-")"
    }

    private nonisolated static func assessmentLabel(_ assessment: PostureAssessment) -> String {
        switch assessment {
        case .good:
            return "정상"
        case .bad:
            return "주의(자세 흐트러짐)"
        case .noEval:
            return "판정 불가"
        }
    }

    private nonisolated static func baselineSummary(_ baseline: Baseline?) -> String {
        guard let baseline else {
            return "없음(미보정)"
        }
        return "중심 \(String(format: "%.3f", baseline.center)) · 변동 \(String(format: "%.3f", baseline.dispersion)) · \(baseline.burstCount)회"
    }
}
