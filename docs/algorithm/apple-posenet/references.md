# Apple Core ML 샘플 PoseNet — 참고 자료

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 공식 자료·원본 저장소·로컬 artifact 근거 목록 |
| 적용 상태 | 근거 문서 |
| 다루는 범위 | PoseNet 출처, 17개 관절, 모델 출력, Core ML 통합과 배포 책임 |
| 제품 내 역할 | [analysis.md](analysis.md)의 모델·decoder 사실 추적 |

## 핵심 근거

| 주장 | 근거 수준 | 출처 |
|---|---|---|
| Apple 샘플의 PoseNet은 Vision API가 아닌 서드파티 Core ML 모델이다 | Apple 공식 | “Detecting human body poses in an image” |
| PoseNet은 사람별 17개 관절을 제공한다 | Apple 공식·원본 저장소 | Apple Core ML 샘플, TensorFlow `tfjs-models` |
| 단일 인물 해석은 joint별 heatmap 최댓값과 offset을 사용한다 | Apple 공식 | Apple Core ML 샘플 설명 |
| 다인 해석은 root 후보와 displacement를 이용해 pose를 조립한다 | Apple 공식·원본 저장소 | Apple Core ML 샘플, TensorFlow PoseNet |
| 현재 artifact는 MobileNetV1 0.75, stride 16이며 네 output tensor를 가진다 | 로컬 1차 근거 | 번들 `.mlmodel` metadata |
| 현재 제품은 heatmap·offset만 해석해 한 명의 상체 anchor를 반환한다 | 로컬 구현 근거 | `PoseNetDetector.swift` |

## 공식 문서와 1차 자료

- Apple Core ML sample, “Detecting human body poses in an image”: <https://developer.apple.com/documentation/coreml/detecting-human-body-poses-in-an-image>
- Apple Core ML model integration samples: <https://developer.apple.com/documentation/coreml/model-integration-samples>
- TensorFlow `tfjs-models` PoseNet source: <https://github.com/tensorflow/tfjs-models/tree/master/posenet>
- TensorFlow pose-detection keypoint contract: <https://github.com/tensorflow/tfjs-models/blob/master/pose-detection/README.md>
- TensorFlow.js PoseNet 소개: <https://blog.tensorflow.org/2018/05/real-time-human-pose-estimation-in.html>

## 로컬 artifact와 구현 근거

- 모델: `Resources/PoseNetMobileNet075S16FP16.mlmodel`
- 모델·샘플 배포 고지: `Resources/ThirdPartyNotices.md`
- 라이선스 사본: `Resources/Apache-2.0.txt`
- 모델 실행·단일 인물 decoder: `Sources/TurtleCore/Camera/PoseNetDetector.swift`
- PoseNet 우선·Vision fallback: `Sources/TurtleCore/Camera/PoseDetector.swift`

번들 모델 metadata는 원본 TensorFlow `tfjs-models` PoseNet 저장소와 Core ML converter 저장소를 출처로 가리킨다. 라이선스는 문서의 요약만 믿지 않고 실제 배포 artifact와 원본 저장소의 라이선스를 릴리스마다 다시 확인한다.

## 추가·관련 자료

- Vision 2D fallback: [`../apple-body-pose/analysis.md`](../apple-body-pose/analysis.md)
- 자세 모델 비교: [`../pose-estimation/comparison.md`](../pose-estimation/comparison.md)
- 목표 판정 흐름: [`../posture-analysis-workflow.md`](../posture-analysis-workflow.md)

## 직접 적용하지 않는 범위

- Apple 샘플의 다인 decoder 설명을 현재 제품 구현 상태로 간주하지 않는다.
- TensorFlow.js API의 image-space 좌표나 threshold를 Core ML 변환 모델에 그대로 복사하지 않는다.
- 공개 benchmark 수치를 현재 Mac 카메라의 정확도·지연·전력 결과로 간주하지 않는다.
- PoseNet score와 Vision confidence를 동일하게 보정된 확률로 해석하지 않는다.
