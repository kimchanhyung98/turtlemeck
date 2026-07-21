# 리뷰: Apple Vision 2D/3D body pose 리서치 (docs/algorithm/apple-body-pose/)

- 리뷰 일자: 2026-07-21
- 대상 문서:
  - [README.md](README.md)
  - [analysis.md](analysis.md)
  - [checklist.md](checklist.md)
  - [references.md](references.md)
  - [related-person-observations.md](related-person-observations.md)
  - [related-vision-3d.md](related-vision-3d.md)
- 종합 판정: 경미한 수정 권장

## 요약

외부 기술 주장을 Apple 공식 문서와 WWDC20/WWDC23 트랜스크립트로 대조한 결과 사실상 전부 일치했고, references.md의 URL 15개와 내부 상대 링크도 모두 유효했다. 코드 대조에서도 PoseNet 우선·Vision fallback 순서, y좌표 반전, neck 비필수 처리, 상체 품질 게이트가 구현과 정확히 일치한다. 발견된 문제는 Apple 출처로 확인되지 않는 3D 관절 all-or-nothing 계약 귀속 1건과 형식 규칙 관련 2건으로 모두 minor다.

## 확인된 사항

| 문서 주장 | 확인 결과 | 근거 |
|---|---|---|
| `VNDetectHumanBodyPoseRequest`는 iOS 14·macOS 11부터 제공 (analysis.md 1절) | 일치 | <https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest> (platforms: iOS 14.0, macOS 11.0) |
| Vision 2D는 최대 19개 body point 검출 (analysis.md 1절, README) | 일치 ("detecting up to 19 unique body points") | <https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images>, <https://developer.apple.com/documentation/vision/body-landmarks> |
| recognized point는 `[0,1]` 정규화·좌하단 원점이며 코드가 `y_internal = 1 - y_vision`을 적용 (analysis.md 3절) | 일치 | Apple 문서 "normalized coordinates (0.0 to 1.0), with the origin at the bottom-left"; `Sources/TurtleCore/Camera/PoseDetector.swift:63-71` |
| 실패 조건 4종: 숙이거나 거꾸로 된 자세, 흐르는 옷, 부분 가림, 화면 가장자리 근접 (analysis.md 5절) | 일치, WWDC20의 한계 서술 그대로 | <https://developer.apple.com/videos/play/wwdc2020/10653/> 트랜스크립트 |
| 알려진 대상 영역이 있으면 ROI 지정이 정확도를 개선할 수 있음 (analysis.md 5절) | 일치 | <https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images> ("Setting an ROI... generally results in more accurate pose estimation") |
| `VNDetectHumanBodyPose3DRequest`는 iOS 17·macOS 14부터, RGB만으로 실행 가능하고 depth가 있으면 정확도 개선 (related-vision-3d.md 1·3절) | 일치 | <https://developer.apple.com/documentation/vision/vndetecthumanbodypose3drequest>, <https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images> |
| Vision 3D는 17-joint skeleton을 meter 단위로 반환, 초기 revision은 가장 두드러진 한 사람, 원점은 hip 사이 root joint (related-vision-3d.md 1·2절) | 일치 | WWDC23 <https://developer.apple.com/videos/play/wwdc2023/111241/> ("a 3D skeleton with 17 joints", "one skeleton for the most prominent person") |
| `bodyHeight`는 depth metadata가 충분하면 measured 값, 없으면 reference height 1.8m (related-vision-3d.md 3절) | 일치 | WWDC23 트랜스크립트 "either a more accurate measured height or a reference height of 1.8 meters"; Apple 문서 동일 서술 |
| `VNHumanBodyRecognizedPoint3D`에는 per-joint confidence가 없음 (related-vision-3d.md 4절) | 일치 (`localPosition`, `parentJoint`만 제공, `VNRecognizedPoint3D` 상속) | <https://developer.apple.com/documentation/vision/vnhumanbodyrecognizedpoint3d> |
| `VNObservation.confidence`는 `[0.0, 1.0]` 정규화된 observation-level 값 (related-vision-3d.md 4절 전제) | 일치 | <https://developer.apple.com/documentation/vision/vnobservation/confidence> |
| `VNGeneratePersonInstanceMaskRequest`는 macOS 14+/iOS 17+, 최대 4명 mask, 혼잡 장면에서 누락·병합 가능 (related-person-observations.md) | 일치 | <https://developer.apple.com/documentation/vision/vngeneratepersoninstancemaskrequest>; WWDC23 "This new request segments up to four people" |
| `AVCaptureDepthDataOutput`은 네이티브 macOS API가 아님 (references.md 핵심 근거) | 일치 (iOS 11.0+, iPadOS 11.0+, Mac Catalyst 14.0+, tvOS 17.0+만 지원) | <https://developer.apple.com/documentation/avfoundation/avcapturedepthdataoutput> platforms 메타데이터 |
| `VNFaceObservation`의 yaw·roll·pitch는 계산되지 않으면 `nil`일 수 있음 (related-person-observations.md) | 일치 (optional `NSNumber`) | <https://developer.apple.com/documentation/vision/vnfaceobservation> |
| Apple Core ML 샘플 PoseNet은 17개 관절이며 neck·root 없음 (analysis.md 1절) | 일치, 번들 코드의 관절 enum도 정확히 17개 | <https://developer.apple.com/documentation/coreml/detecting-human-body-poses-in-an-image>; `Sources/TurtleCore/Camera/PoseNetDetector.swift:125-143` |
| fallback 순서(PoseNet 우선, 상체 품질 통과 시 그 결과만, 실패 시 같은 프레임에 Vision 2D)와 상체 품질 게이트(머리 anchor, 양쪽 어깨 confidence, 최소 어깨 폭, 어깨 기울기) (analysis.md 4·6절) | 코드와 일치 | `Sources/TurtleCore/Camera/PoseDetector.swift:17-33, 73-81` (`Tuning.minimumShoulderWidth`, `Tuning.maximumShoulderSlope`) |

references.md의 외부 URL 15개와 대상 문서의 내부 상대 링크는 모두 유효했다.

## 발견된 문제

### 수정 필요 (major)

없음.

### 권장 (minor)

1. [related-vision-3d.md](related-vision-3d.md) 1절 — 근거 미확인 귀속
   - 문서 서술: "Apple은 필요한 관절 일부만 반환하는 방식이 아니라 17개 전체를 얻거나 observation을 얻지 못하는 계약으로 설명한다."
   - 문제: 이 all-or-nothing 계약을 Apple의 설명으로 귀속하고 있으나, 문서가 인용한 출처(`VNDetectHumanBodyPose3DRequest`·`VNHumanBodyPose3DObservation` 문서, "Identifying 3D human body poses in images" 아티클, WWDC23 트랜스크립트)에서 그런 명시적 서술을 확인할 수 없다. 오히려 observation에는 `availableJointNames` 속성이 있어 API 표면상 부분 가용 관절을 전제한다. 실제 동작이 그렇더라도 "Apple이 설명한다"는 표현은 수정하거나 출처를 제시해야 한다.
   - 근거: WWDC23 트랜스크립트에는 "a 3D skeleton with 17 joints"만 있고 전체 반환 보장 서술 없음; <https://developer.apple.com/documentation/vision/vnhumanbodypose3dobservation> (`availableJointNames` 존재)
2. [README.md](README.md) 문서 구성 표, [analysis.md](analysis.md) 문서 요약 — 정의되지 않은 적용 상태 용어
   - 문서 서술: README.md:56의 analysis.md 행 적용 상태 "fallback", analysis.md:8의 "PoseNet 상체 품질 실패 시 fallback".
   - 문제: [`../README.md`](../README.md)가 정의한 적용 상태 용어는 채택·보조·검증 필요·미채택·제외·근거 문서 6종이며 "fallback"은 정의된 상태가 아니다. 형제 문서(pose-estimation/README.md "PoseNet 우선 채택, Apple Vision 2D fallback", apple-posenet/README.md "상체 landmark 우선 추출기로 채택")는 정의 용어를 포함해 표기하므로, "채택(fallback)" 같은 형태로 정의 용어에 앵커하는 것이 규칙에 부합한다.
   - 근거: docs/algorithm/README.md:82-93 (적용 상태 용어 표) vs docs/algorithm/apple-body-pose/README.md:56, analysis.md:8
3. [related-vision-3d.md](related-vision-3d.md) — related 문서 형식 불일치
   - 문서 서술: 문서 요약 → 1. API 계약 → 2. 좌표 표현 → 3. depth metadata와 신장 추정 → 4. confidence → 5. 현재 제품에서 제외하는 이유 → 6. Vision 2D와 구분 → 참고 자료 구조.
   - 문제: [`../README.md`](../README.md)는 `related-<topic>.md`를 "문서 요약 → 핵심 근거 → 현재 방식과의 관계 → 적용하지 않는 범위 → 참고 자료" 순서로 작성하도록 규정하는데, 이 문서는 핵심 근거 표 없이 analysis.md 형식의 번호 섹션 구조를 쓴다. 같은 그룹의 related-person-observations.md는 규정 순서를 따르고 있어 그룹 내 형식이 불일치한다.
   - 근거: docs/algorithm/README.md:80 vs related-vision-3d.md 섹션 구성; 대조 예: related-person-observations.md는 핵심 근거·현재 방식과의 관계 섹션 보유

## 참고 (info)

없음.

## 결론

apple-body-pose 그룹은 품질이 높다. OS 가용성, 19 point·17 joint 구성, 좌표계, confidence 계약, 실패 조건, person mask 4인 제한, `AVCaptureDepthDataOutput`의 macOS 미지원 등 외부 기술 주장이 Apple 공식 자료와 일치하고 코드 대조도 통과했다. 남은 항목은 related-vision-3d.md의 all-or-nothing 계약 귀속 표현 수정과 형식 규칙 정합(적용 상태 용어 앵커, related 문서 섹션 순서) 3건으로 모두 minor이므로 경미한 수정만 권장한다.
