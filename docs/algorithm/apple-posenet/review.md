# 리뷰: Apple Core ML 샘플 PoseNet 리서치 (docs/algorithm/apple-posenet/)

- 리뷰 일자: 2026-07-21
- 대상 문서:
  - [README.md](README.md)
  - [analysis.md](analysis.md)
  - [references.md](references.md)
- 종합 판정: 문제 없음

## 요약

apple-posenet 문서 그룹의 핵심 외부 주장(서드파티 PoseNet, 17개 COCO 관절, MobileNetV1 0.75·stride 16, 4개 출력 tensor, 라이선스)은 Apple 공식 문서·TensorFlow 원문·번들 `.mlmodel` metadata 파싱·Apple 샘플 zip 다운로드로 모두 확인됐다. 번들 모델 파일은 Apple 샘플 배포본과 md5가 완전히 일치하며, decoder 로직·offset 채널 인덱싱·좌표 공식·fallback 조건도 문서 서술과 코드가 정확히 일치한다. references.md의 URL 5개는 전부 유효하고, 규범 문서와의 충돌도 없다. 수정이 필요한 오류는 발견되지 않았고 info 수준 참고 사항 2건만 남긴다.

## 확인된 사항

| 문서 주장 | 확인 결과 | 근거 |
|---|---|---|
| Apple 샘플은 PoseNet을 서드파티 Core ML 모델로 소개하며 Vision 2D와 별개 기술이다 | 일치 | <https://developer.apple.com/documentation/coreml/detecting-human-body-poses-in-an-image> ("an illustrative example of using a third-party Core ML model, PoseNet"); Vision은 별도 문서 <https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images> |
| 사람별 17개 관절, nose→eyes→ears→shoulders→elbows→wrists→hips→knees→ankles 순서 | 일치 | Apple 문서 "PoseNet models detect 17 different body parts or joints"; tfjs pose-detection README의 17 COCO keypoint 순서; `Sources/TurtleCore/Camera/PoseNetDetector.swift:125-143` `PoseNetJoint` enum; Apple 샘플 Joint.swift 동일 순서 |
| 번들 모델은 MobileNetV1 0.75, output stride 16, `heatmap`·`offsets`·`displacementFwd`·`displacementBwd` 4개 출력 | 일치 | `Resources/PoseNetMobileNet075S16FP16.mlmodel` protobuf 직접 파싱: metadata "MobileNetV1 architecture with a width multiplier of 0.75 and an output stride of 16", 출력 4개 이름 확인 |
| 모델 입력 기본 513×513 RGB, 제품 코드는 513×513 BGRA `scaleFill` 고정 | 일치 | mlmodel spec(default 513×513, enumerated 257/353/513, RGB); `PoseNetDetector.swift:10, 105-123` (inputSize 513, `kCVPixelFormatType_32BGRA`, `scaleFill`) |
| 번들 모델 파일은 Apple 샘플 배포본과 동일 | byte 단위 일치 | Apple 샘플 zip(docs-assets.developer.apple.com/published/3e1c865293a0/DetectingHumanBodyPosesInAnImage.zip) 내 모델과 md5 일치 (7188b08d22750efba1bcf028211bdae2) |
| ThirdPartyNotices.md 고지(모델 Apache-2.0, 샘플 코드 MIT) | 일치 | Apple 샘플 LICENSE.txt: "based on the PoseNet model which is distributed under the Apache License 2.0" + Apple Inc. 저작권 MIT 본문; `Resources/ThirdPartyNotices.md:14-21`; `Resources/Apache-2.0.txt` 존재 |
| 단일 인물 decoding은 joint별 heatmap 전역 최댓값 cell + offset 보정 | 일치 | Apple 샘플 PoseBuilder+Single.swift·PoseNetOutput.swift:170-179 (yOffset=joint, xOffset=joint+numberOfJoints 채널); `PoseNetDetector.swift:74-98` 동일 인덱싱 |
| 좌표 공식 `x=(gridX×16+xOffset)/513`, `y=(gridY×16+yOffset)/513` | 일치 | `PoseNetDetector.swift:93-97` `(bestX*outputStride+xOffset)/inputSize` |
| 다인 해석은 root 후보와 displacement로 조립하며, 현재 decoder는 displacement를 읽지 않고 상체 7개 관절만 반환 | 일치 | Apple 문서 "identifies a set of candidate root joints..."; 샘플 PoseBuilder+Multiple.swift:175-235; `PoseNetDetector.swift:28-44`는 heatmap·offsets만 조회 |
| PoseNet 우선·Vision fallback 계약과 품질 게이트(머리 anchor 1개 이상 + 양쪽 어깨 reliable + 어깨 폭·기울기 조건), 같은 프레임 재분석·관절 혼합 없음 | 일치 | `Sources/TurtleCore/Camera/PoseDetector.swift:17-33, 73-81`; `Tuning.swift:7-8` (minimumShoulderWidth 0.08, maximumShoulderSlope 0.18) |
| 실패 조건 목록(모델 파일·compile/load 실패, 입력 이미지 생성 실패, heatmap/offsets 부재) | 일치 | `PoseNetDetector.swift:14-31, 47-56, 145-149` (`PoseNetError` → `PoseDetector`의 `try?`가 Vision fallback으로 전환) |
| Vision 2D는 최대 19개 body point, PoseNet 17개에는 `neck`·`root` 없음 | 일치 | Apple Vision 문서 "detecting up to 19 unique body points"; tfjs 17 COCO keypoint 목록에 neck/root 없음; neck은 Vision 경로(`PoseDetector.swift:57`)에서만 설정 |
| `scaleFill`은 crop 없이 입력 크기를 채우도록 스케일 | 일치 | <https://developer.apple.com/documentation/vision/vnimagecropandscaleoption/scalefill>; Apple 샘플 PoseNetInput.swift:44 동일 옵션 |
| TensorFlow 자료의 keypoint score 0.0~1.0 confidence, heatmap·offset 단일 인물, displacement 다인 해석 인용 | 일치 | <https://blog.tensorflow.org/2018/05/real-time-human-pose-estimation-in.html> ("the confidence that an estimated keypoint position is accurate. It ranges between 0.0 and 1.0") |
| 번들 모델 metadata가 원본 tfjs-models 저장소와 Core ML converter 저장소를 출처로 가리킴 | 일치 | mlmodel metadata: "Please see https://github.com/infocom-tpo/PoseNet-CoreML ... and https://github.com/tensorflow/tfjs-models for license information for the original model" |

## 발견된 문제

### 수정 필요 (major)

없음.

### 권장 (minor)

없음.

## 참고 (info)

- `references.md:27`의 TensorFlow `tfjs-models` PoseNet 링크는 유효하지만, 해당 posenet 패키지는 README 첫머리에서 "This package is deprecated in favor of the new pose-detection package"로 명시된 deprecated 상태다. README.md가 모델 라이선스와 업데이트를 제품 책임 범위로 강조하는 만큼, upstream이 더 이상 유지되지 않는다는 사실을 근거 문서에 한 줄 기록해 두면 좋다.
- `Resources/ThirdPartyNotices.md:14-21`의 고지(샘플 코드 MIT)는 Apple 샘플 LICENSE.txt와 일치하지만, Resources에는 Apache-2.0 본문만 있고 MIT 본문 사본은 없다. `PoseNetDetector.swift`의 decoder가 Apple 샘플과 동일한 알고리즘·offset 채널 인덱싱(joint / joint+17)을 사용하는 파생 성격이므로, MIT 조건(사본에 허가 고지 포함)을 위해 MIT 본문 번들을 검토할 만하다. 문서 사실 오류는 아니다.

## 결론

세 문서 모두 외부 근거·번들 artifact·제품 코드와 대조해 오류가 발견되지 않았다. 종합 판정은 "문제 없음"이며, upstream posenet 패키지의 deprecated 상태 기록과 MIT 라이선스 본문 번들 검토 두 가지를 info 수준 참고 사항으로 남긴다.
