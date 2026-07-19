# Apple Vision 기반 자세 추정 — 참고 자료

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 공식 자료·관련 자료 목록 |
| 적용 상태 | 근거 문서 |
| 다루는 범위 | Vision 2D·3D body pose, observation confidence, person mask, 카메라 depth |
| 제품 내 역할 | [analysis.md](analysis.md)의 API 사실과 채택·제외 판단을 추적할 출처 제공 |

## 핵심 근거

| 주장 | 근거 수준 | 출처 |
|---|---|---|
| Vision 2D는 관절별 2D 좌표와 confidence를 제공 | Apple 공식 | `VNDetectHumanBodyPoseRequest`, WWDC20 |
| Vision 3D는 17-joint skeleton이며 dense/measured depth가 아님 | Apple 공식 | `VNDetectHumanBodyPose3DRequest`, WWDC23 |
| person instance mask는 사람 단위 2D mask이며 신체 부위·depth 정보가 아님 | Apple 공식 | `VNGeneratePersonInstanceMaskRequest`, WWDC23 |
| `AVCaptureDepthDataOutput`은 네이티브 macOS API가 아니며 지원 플랫폼에서도 호환 장치·depth format을 요구 | Apple 공식 | `AVCaptureDepthDataOutput` |

## 공식 문서와 1차 자료

- Apple `VNDetectHumanBodyPoseRequest`: <https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest>
- Apple `VNDetectHumanBodyPose3DRequest`: <https://developer.apple.com/documentation/vision/vndetecthumanbodypose3drequest>
- Apple `VNHumanBodyPose3DObservation`: <https://developer.apple.com/documentation/vision/vnhumanbodypose3dobservation>
- Apple `VNObservation.confidence`: <https://developer.apple.com/documentation/vision/vnobservation/confidence>
- Apple `VNFaceObservation` (optional pitch·yaw·roll): <https://developer.apple.com/documentation/vision/vnfaceobservation>
- Apple `VNHumanBodyRecognizedPoint3D`: <https://developer.apple.com/documentation/vision/vnhumanbodyrecognizedpoint3d>
- Apple `VNDetectedPoint`: <https://developer.apple.com/documentation/vision/vndetectedpoint>
- Apple `VNGeneratePersonInstanceMaskRequest`: <https://developer.apple.com/documentation/vision/vngeneratepersoninstancemaskrequest>
- Apple `AVCaptureDepthDataOutput`: <https://developer.apple.com/documentation/avfoundation/avcapturedepthdataoutput>
- WWDC23 “Explore 3D body pose and person segmentation in Vision”: <https://developer.apple.com/videos/play/wwdc2023/111241/>
- WWDC20 “Detect Body and Hand Pose with Vision”: <https://developer.apple.com/videos/play/wwdc2020/10653/>

## 추가·관련 자료

- 목표 알고리즘: [`../posture-analysis-workflow.md`](../posture-analysis-workflow.md)
- Depth Anything V2: [`../../depth-estimation/depth-anything-v2/README.md`](../../depth-estimation/depth-anything-v2/README.md)
- depth feature 설계: [`../../depth-estimation/etc/related-feature-design.md`](../../depth-estimation/etc/related-feature-design.md)

## 직접 적용하지 않는 범위

- Vision 3D의 skeleton 좌표를 머리·몸통 dense depth나 실제 센서 거리로 해석하지 않는다.
- person instance mask를 머리·몸통 부위 분할 결과로 해석하지 않는다.
- API 가용성만으로 목표 제품 환경의 정확도·지연·전력 적합성을 확정하지 않는다.
