# 리뷰: Apple Vision·플랫폼 depth 리서치 (docs/depth-estimation/apple-vision-depth/)

- 리뷰 일자: 2026-07-21
- 대상 문서:
  - [README.md](README.md)
  - [analysis.md](analysis.md)
  - [references.md](references.md)
- 종합 판정: 경미한 수정 권장

## 요약

세 문서의 핵심 주장(AVFoundation·Vision API의 플랫폼 가용성, WWDC23 Vision 3D 내용, Apple 배포 DA-V2 Small 모델 카드 수치, Depth Pro 라이선스 이중 구조)을 Apple 공식 문서·모델 카드·저장소 등 1차 출처와 대조한 결과 대부분 정확했다. 코드 서술(PoseNet 우선·Vision 2D fallback, VNCoreMLRequest 실행, 제외 API 미사용)도 실제 구현과 모순이 없다. 발견된 문제는 ARKit 가용성 목록에 현재 Apple 문서에 없는 Mac Catalyst 14.0을 포함한 것과 Swift 예제 제공 주체를 Apple로 귀속한 것 두 건의 minor뿐이다. references.md의 외부 URL 17건은 모두 유효했다.

## 확인된 사항

| 문서 주장 | 확인 결과 | 근거 |
|---|---|---|
| `AVCaptureDepthDataOutput`은 iOS 11.0/iPadOS/Mac Catalyst 14.0/tvOS 17.0 전용, 네이티브 macOS 미지원. 정의 "A capture output that records scene depth information on compatible camera devices" (analysis.md 1-1) | 일치. platforms에 macOS 없음, 정의 인용 정확 | <https://developer.apple.com/documentation/avfoundation/avcapturedepthdataoutput> |
| `AVDepthData`는 macOS 10.13+에 존재하는 컨테이너. 정의 "A container for per-pixel distance or disparity information captured by compatible camera devices" (analysis.md 1-2) | 일치 | <https://developer.apple.com/documentation/avfoundation/avdepthdata> |
| `builtInTrueDepthCamera`는 iOS 11.1/iPadOS 11.1/Mac Catalyst 14.0/tvOS 17.0, 네이티브 macOS 없음. "two cameras, one Infrared and one YUV" (analysis.md 1-3) | 일치 | <https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype-swift.struct/builtintruedepthcamera> |
| Vision 요청 가용성 — Segmentation macOS 12.0+, InstanceMask·ForegroundMask macOS 14.0+, HumanBodyPose iOS 14/macOS 11+, BodyPose3D macOS 14+, VNCoreMLRequest macOS 10.13+ (analysis.md 2절) | 전부 일치 | 각 요청별 Apple 공식 문서 platforms 필드 |
| WWDC23 세션 111241: 17-joint skeleton, hip 중심 root joint, `AVDepthData`로 정확도 보강, depth 부재 시 기준 신장 1.8m (analysis.md 1-5) | 일치. transcript에 "a reference height of 1.8 meters" 명시 | <https://developer.apple.com/videos/play/wwdc2023/111241/> |
| Vision 3D 관절점에 관절별 confidence가 없음 (analysis.md 1-5) | 일치. `VNHumanBodyRecognizedPoint3D` 멤버는 localPosition, parentJoint 등이며 confidence 속성 없음 | <https://developer.apple.com/documentation/vision/vnhumanbodyrecognizedpoint3d> |
| DA-V2 Small 모델 카드: F16 49.8MB, F32 99.2MB, M1 Max 32.80ms, M3 Max 24.58ms, Neural Engine dominant, COCO 512장 518×396 stretch 평가, DPT+DINOv2 (analysis.md 3-2) | 전부 일치 | <https://huggingface.co/apple/coreml-depth-anything-v2-small> |
| 2024-06-25 Apple Core ML Models 라이브러리 편입 (analysis.md 3-2) | 일치. 공식 저장소 뉴스 항목과 동일 | <https://github.com/DepthAnything/Depth-Anything-V2> |
| DA-V2는 affine-invariant inverse depth(상대 깊이, scale·shift 미정)를 출력 (analysis.md 3-3) | 일치 | <https://arxiv.org/html/2406.09414v2> |
| Depth Pro는 표준 GPU에서 2.25MP 깊이맵 0.3초 생성, 카메라 intrinsics 불요 (analysis.md 3-4) | 일치 | <https://github.com/apple/ml-depth-pro> |
| Depth Pro 라이선스 이중 구조: GitHub LICENSE는 use·modify·redistribute 허용, HF `apple/DepthPro`는 `apple-amlr` 연구 전용, 다운로드 스크립트는 Apple CDN + 동봉 LICENSE 안내 (analysis.md 3-4) | 일치 | GitHub LICENSE, `get_pretrained_models.sh`, <https://huggingface.co/apple/DepthPro/blob/main/LICENSE> |
| DA-V2 Small은 `VNCoreMLRequest`로 실행되고 observation 유형을 고정하지 않음 (analysis.md 3-1) | 일치. 코드가 `VNPixelBufferObservation`·`VNCoreMLFeatureValueObservation`을 모두 처리, 번들 모델 존재 | `Sources/TurtleCore/Camera/CoreMLRelativeDepthProvider.swift:53-59`, `Resources/DepthAnythingV2SmallF16.mlpackage` |
| PoseNet 우선·Vision 2D fallback, 제외 선언 경로(Vision 3D·segmentation/instance mask·`AVCaptureDepthDataOutput`·TrueDepth·ARKit) 미사용 (analysis.md 5절) | 일치. Sources/Tests grep에서 제외 API 무일치 | `Sources/TurtleCore/Camera/PoseDetector.swift:17-21,36` |
| 영역 depth는 median 같은 견고한 통계로 집계 (analysis.md 5절 2항) | 일치. 규범 문서·구현 모두 median 사용 | `docs/algorithm/posture-analysis-workflow.md` §6, `Sources/TurtleCore/Detection/PostureAnalyzer.swift:99-100,186` |
| references.md 외부 URL 17건 | 전부 유효. TrueDepth 스트리밍 샘플 페이지도 실제 존재 | 개별 접속 확인 |

## 발견된 문제

### 수정 필요 (major)

없음.

### 권장 (minor)

1. analysis.md 1-4
   - 문서 서술: "ARKit 플랫폼 가용성(Apple 공식): iOS 11.0 / iPadOS 11.0 / Mac Catalyst 14.0 / visionOS 1.0 → 네이티브 macOS 없음."
   - 문제: 현재 Apple 공식 문서에서 ARKit 프레임워크와 주요 심벌(ARSession, ARFrame, ARWorldTrackingConfiguration 등)의 가용 플랫폼은 iOS 11.0 / iPadOS 11.0 / visionOS 1.0뿐이고 Mac Catalyst는 나열되지 않는다. "(Apple 공식)"으로 명시한 목록에 현재 문서에 없는 Mac Catalyst 14.0이 포함되어 출처와 불일치한다. 핵심 결론(네이티브 macOS 없음)은 유효하다.
   - 근거: <https://developer.apple.com/documentation/arkit> (platforms: iOS, iPadOS, visionOS)
2. analysis.md 3-1
   - 문서 서술: "Apple은 DA-V2 Small의 `.mlpackage`와 Swift 예제를 제공한다."
   - 문제: `.mlpackage`는 Apple(HF `apple/` 조직) 배포가 맞지만, Swift 예제는 Apple이 아니라 Hugging Face의 `huggingface/coreml-examples` 저장소가 제공한다. Apple 모델 카드도 "The huggingface/coreml-examples repository contains sample Swift code"라고 안내하며, 같은 그룹의 references.md 35행도 "Hugging Face Core ML 예시"로 올바르게 귀속하고 있어 그룹 내 표기와도 어긋난다.
   - 근거: <https://huggingface.co/apple/coreml-depth-anything-v2-small>, references.md 35행

## 참고 (info)

- references.md에는 analysis.md 2절 표의 다른 Vision 요청(Segmentation·InstanceMask·ForegroundMask·3D) URL이 모두 있으나 `VNDetectHumanBodyPoseRequest` 공식 문서 URL만 누락되어, 해당 항목의 근거 추적이 그룹 내에서 닫히지 않는다(간접적으로 apple-body-pose 그룹 링크로만 연결). 가용성 자체(iOS 14.0/macOS 11.0)는 <https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest>로 확인되어 정확하다.

## 결론

세 문서는 플랫폼 가용성, 모델 카드 수치, 라이선스 구조, 코드 정합성 모두 1차 출처와 일치하는 정확한 리서치다. ARKit 가용성 목록의 Mac Catalyst 표기와 Swift 예제 제공 주체 귀속 두 건만 바로잡으면 되고, 결론에 영향을 주는 오류는 없다.
