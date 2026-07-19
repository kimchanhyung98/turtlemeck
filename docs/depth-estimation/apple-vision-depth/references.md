# macOS 단일 RGB 깊이 경로 — 참고 자료

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | Apple 공식 자료·모델 자료 목록 |
| 적용 상태 | 근거 문서 |
| 다루는 범위 | AVFoundation, Vision, Core ML, DA-V2, Depth Pro |
| 제품 내 역할 | [analysis.md](analysis.md)의 플랫폼 가용성·제약을 추적할 출처 제공 |

## 핵심 근거

| 주장 | 근거 수준 | 대표 출처 |
|---|---|---|
| `AVCaptureDepthDataOutput`은 네이티브 macOS API가 아니며 지원 플랫폼에서도 호환 장치·depth format을 요구 | Apple 공식 | `AVCaptureDepthDataOutput`, `AVDepthData` |
| TrueDepth·ARKit 경로는 목표 Mac 내장 카메라 경로가 아님 | Apple 공식 | device type·ARKit 문서 |
| Vision 3D는 skeleton 추정이며 dense depth가 아님 | Apple 공식 | Vision 3D 문서·WWDC23 |
| DA-V2 Small은 Apple 배포 Core ML 패키지가 존재 | Apple 모델 배포 | Apple Hugging Face 모델 카드 |

## 공식 문서와 1차 자료

- AVCaptureDepthDataOutput (iOS·iPadOS·Mac Catalyst·tvOS, `compatible camera devices` 요구): <https://developer.apple.com/documentation/avfoundation/avcapturedepthdataoutput>
- AVDepthData (컨테이너, "compatible camera devices" 전제; macOS 10.13+이나 측정 아님): <https://developer.apple.com/documentation/avfoundation/avdepthdata>
- builtInTrueDepthCamera ("two cameras, one Infrared and one YUV"; macOS 없음): <https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype-swift.struct/builtintruedepthcamera>
- Streaming depth data from the TrueDepth camera (TrueDepth 전제 샘플): <https://developer.apple.com/documentation/AVFoundation/streaming-depth-data-from-the-truedepth-camera>
- ARKit (macOS 네이티브 없음, 하드웨어 센싱 전제): <https://developer.apple.com/documentation/arkit>
- VNGeneratePersonSegmentationRequest (macOS 12.0+): <https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest>
- VNGeneratePersonInstanceMaskRequest (macOS 14.0+): <https://developer.apple.com/documentation/vision/vngeneratepersoninstancemaskrequest>
- VNGenerateForegroundInstanceMaskRequest (macOS 14.0+): <https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest>
- VNDetectHumanBodyPose3DRequest (macOS 14+, RGB skeleton 추정): <https://developer.apple.com/documentation/vision/vndetecthumanbodypose3drequest>
- WWDC23 Vision 3D body pose (`AVDepthData`, hip root, reference height): <https://developer.apple.com/videos/play/wwdc2023/111241/>
- VNCoreMLRequest (Core ML 모델 실행, macOS 10.13+): <https://developer.apple.com/documentation/vision/vncoremlrequest>
- Apple 공식 Core ML 변환본 Depth Anything V2 Small (49.8MB F16, M3 Max NE 24.58ms): <https://huggingface.co/apple/coreml-depth-anything-v2-small>
- Hugging Face Core ML 예시 (DepthAnythingV2SmallF16.mlpackage Swift 데모): <https://github.com/huggingface/coreml-examples/blob/main/depth-anything-example/README.md>
- Depth Anything V2 원논문 (affine-invariant/상대 깊이): <https://arxiv.org/html/2406.09414v2>
- Apple Depth Pro (metric 단안, 공식 Core ML 패키지 확인되지 않음): <https://github.com/apple/ml-depth-pro>
- Apple Depth Pro 저장소 LICENSE: <https://github.com/apple/ml-depth-pro/blob/main/LICENSE>
- Apple CDN checkpoint 다운로드 스크립트: <https://github.com/apple/ml-depth-pro/blob/main/get_pretrained_models.sh>
- Apple Depth Pro Hugging Face LICENSE (`apple-amlr`, research-only): <https://huggingface.co/apple/DepthPro/blob/main/LICENSE>
- 단안 깊이 한계와 상대 변화 결론: [../../algorithm/pose-estimation/related-monocular-limits.md](../../algorithm/pose-estimation/related-monocular-limits.md)

## 추가·관련 자료

- Apple Vision 자세 입력의 역할: [../../algorithm/apple-body-pose/README.md](../../algorithm/apple-body-pose/README.md)
- 현재 채택 depth 모델: [../depth-anything-v2/README.md](../depth-anything-v2/README.md)
- 대형 metric 대안: [../apple-depth-pro/README.md](../apple-depth-pro/README.md)

## 직접 적용하지 않는 범위

- API가 macOS에 존재한다는 사실만으로 목표 Mac 카메라가 measured depth를 제공한다고 판단하지 않는다.
- Vision 3D skeleton을 dense depth map이나 실제 센서 거리로 해석하지 않는다.
- Core ML 모델 카드의 단일 모델 지연을 전체 자세 판정 파이프라인 성능으로 전용하지 않는다.
