# 자세 추정 방식 — 모델 비교

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 자세 추정 모델 비교 |
| 적용 상태 | Apple 공식 샘플 PoseNet 우선 채택, Vision 2D fallback |
| 다루는 범위 | 필요한 landmark, 플랫폼 통합, 라이선스 |
| 제품 내 역할 | PoseNet 선정 근거, Vision fallback과 대안 미채택 이유 기록 |

## 동일 기준 비교

| 방식 | 공식적으로 확인한 출력 | 플랫폼·배포 조건 | 현재 판단 |
|---|---|---|---|
| Apple PoseNet Core ML sample | 17개 2D keypoint와 heatmap 기반 confidence | Core ML 모델 번들, 모델 Apache-2.0·샘플 MIT | 우선 채택 — 제품 카메라에서 초기 보정과 반복 분석 성공 |
| Apple Vision 2D | 최대 19개 2D body point와 point별 confidence | macOS 11+, OS 내장 | fallback — API 실행 또는 PoseNet 상체 품질 실패 시 보조 |
| MediaPipe Pose Landmarker | 33개 image/world landmark | iOS용 Swift API 제공, 네이티브 macOS 지원은 공식 가이드에 명시되지 않음 | 미채택 — 별도 SDK·모델·플랫폼 검증 필요 |
| MoveNet | 17개 2D keypoint, Lightning·Thunder 변형 | TensorFlow 계열 런타임·모델 통합 필요 | 미채택 |
| OpenPose | bottom-up 다인 2D keypoint | 별도 C++/GPU 경로, 기본 라이선스는 비상업 연구용 | 미채택 |
| YOLO-Pose | 모델별 2D keypoint | Ultralytics는 AGPL-3.0 또는 Enterprise 조건 | 미채택 |

MediaPipe에 “Swift binding이 없다”는 표현은 정확하지 않다. Google은 Pose Landmarker에 대해서도 공식 iOS 가이드와 Swift API를 제공한다. 다만 공식 플랫폼 가이드는 Android·Python·Web(JavaScript)·iOS만 안내하며 네이티브 macOS는 지원 플랫폼으로 명시되지 않는다. 따라서 macOS 제품에 도입하려면 iOS용 Swift API를 그대로 쓰는 것이 아니라 별도 빌드·검증 경로가 필요하다. 현재는 Apple 샘플 PoseNet과 Vision fallback으로 필요한 역할을 충족하므로 별도 SDK·모델·업데이트 경로를 추가하지 않는다.

## 정확도 비교를 하지 않는 이유

각 자료의 mAP·PCK·FPS는 데이터셋, 입력 크기, 하드웨어와 평가 목적이 달라 한 표의 순위로 사용할 수 없다. 현재 선택은 “가장 높은 공개 점수”가 아니라 다음 요구를 기준으로 한다.

- nose·eyes·ears·neck·shoulders를 안정적으로 제공할 것
- point별 품질 판단이 가능할 것
- macOS 온디바이스 경로가 단순할 것
- 최종 판정이 아니라 DA-V2용 ROI와 품질 입력 역할을 수행할 것

제품 카메라에서 Vision 단독 경로는 초기 보정에 필요한 ROI 반복성을 충족하지 못했다. 동일 입력에서 Apple 공식 샘플 PoseNet은 머리·양쪽 어깨 anchor를 반복 제공했고, 실제 보정 3개 버스트와 자동 분석 5/5 유효 프레임을 통과했다. 따라서 PoseNet을 우선 사용하고, 상체 기하·confidence 게이트를 통과하지 못할 때 Vision 2D를 fallback으로 사용한다.

## 라이선스 확인

- MediaPipe 저장소: Apache-2.0
- Apple sample PoseNet 모델: Apache-2.0, sample code: MIT
- MoveNet SinglePose 모델 카드: Apache-2.0
- Ultralytics: AGPL-3.0 또는 Enterprise License
- OpenPose: 비상업 연구용 기본 라이선스, 상업 사용은 별도 문의

라이선스는 모델 버전과 배포 형태가 바뀔 수 있으므로 실제 도입 시 다시 확인한다.

## 결론

Apple 공식 Core ML 샘플의 PoseNet을 신체 landmark·ROI·품질의 우선 입력으로 사용하고 Vision 2D를 fallback으로 둔다. 자세 판정은 어느 pose 모델도 아닌 프로젝트 자세 분석기가 DA-V2 relative depth, 개인 baseline, 시간 조건을 적용해 수행한다. 다른 pose 모델과 Vision 3D는 현재 플로우에 추가하지 않는다.

## 참고 자료

- Apple Core ML 샘플 PoseNet 상세: [`../apple-posenet/`](../apple-posenet/)
- Apple Vision 2D 상세: [`../apple-body-pose/analysis.md`](../apple-body-pose/analysis.md)
- Apple Vision 2D body pose: <https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images>
- Apple PoseNet Core ML sample: <https://developer.apple.com/documentation/coreml/detecting-human-body-poses-in-an-image>
- MediaPipe Pose Landmarker: <https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker>
- MediaPipe Tasks Vision Swift API: <https://ai.google.dev/edge/api/mediapipe/swift/vision/Protocols>
- MediaPipe Tasks iOS setup: <https://ai.google.dev/edge/mediapipe/solutions/setup_ios>
- MediaPipe LICENSE: <https://github.com/google-ai-edge/mediapipe/blob/master/LICENSE>
- MoveNet: <https://www.tensorflow.org/hub/tutorials/movenet>
- MoveNet model card: <https://storage.googleapis.com/movenet/MoveNet.SinglePose%20Model%20Card.pdf>
- Ultralytics license options: <https://www.ultralytics.com/license>
- OpenPose LICENSE: <https://github.com/CMU-Perceptual-Computing-Lab/openpose/blob/master/LICENSE>
