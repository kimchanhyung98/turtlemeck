# Apple Vision 2D body pose — 참고 자료

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 공식 자료·관련 자료 목록 |
| 적용 상태 | 근거 문서 |
| 다루는 범위 | Vision 2D body pose, 관절별 confidence와 좌표 계약 |
| 제품 내 역할 | Vision 2D [analysis.md](analysis.md)의 API 사실과 현재 통합 근거 추적 |

## 핵심 근거

| 주장 | 근거 수준 | 출처 |
|---|---|---|
| Vision 2D는 관절별 2D 좌표와 confidence를 제공 | Apple 공식 | `VNDetectHumanBodyPoseRequest`, WWDC20 |
| Vision 2D와 Apple Core ML 샘플 PoseNet은 별도 기술이다 | Apple 공식 | PoseNet Core ML sample, Vision 2D 안내 |
| 현재 구현은 Vision 좌하단 좌표의 y축을 반전해 공통 좌상단 좌표로 변환한다 | 로컬 구현 근거 | `PoseDetector.swift` |

## 공식 문서와 1차 자료

- Apple “Detecting Human Body Poses in Images”: <https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images>
- Apple `VNDetectHumanBodyPoseRequest`: <https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest>
- Apple body landmarks: <https://developer.apple.com/documentation/vision/body-landmarks>
- Apple Core ML sample “Detecting human body poses in an image”: <https://developer.apple.com/documentation/coreml/detecting-human-body-poses-in-an-image>
- WWDC20 “Detect Body and Hand Pose with Vision”: <https://developer.apple.com/videos/play/wwdc2020/10653/>

## 로컬 구현 근거

- Vision 2D 실행·좌표 변환·관절 매핑: `Sources/TurtleCore/Inference/PoseDetector.swift`
- 공통 관절점·상체 기하: `Sources/TurtleCore/Detection/Models.swift`
- ROI·품질·feature 계산: `Sources/TurtleCore/Detection/PostureAnalyzer.swift`

## 추가·관련 자료

- 목표 알고리즘: [`../posture-analysis-workflow.md`](../posture-analysis-workflow.md)
- Apple Core ML 샘플 PoseNet: [`../apple-posenet/`](../apple-posenet/)
- Depth Anything V2: [`../../depth-estimation/depth-anything-v2/README.md`](../../depth-estimation/depth-anything-v2/README.md)
- depth feature 설계: [`../../depth-estimation/etc/related-feature-design.md`](../../depth-estimation/etc/related-feature-design.md)

## 적용 경계

- Vision 2D 관절을 z축 깊이나 실제 거리로 해석하지 않는다.
- Vision 2D API가 최종 자세 상태를 직접 출력한다고 해석하지 않는다.
- API 가용성만으로 목표 제품 환경의 정확도·지연·전력 적합성을 확정하지 않는다.
- Apple PoseNet 샘플의 모델 계약을 Vision 2D API 계약으로 옮겨 적지 않는다.
