# PoseNet과 Vision 2D

## 채택 상태

목바로는 번들된 PoseNet MobileNet 0.75 모델을 상체 랜드마크 우선 추출기로 사용한다.
PoseNet이 사용할 수 있는 머리·양쪽 어깨 기하를 만들지 못하면 같은 RGB 프레임을 Apple Vision 2D body pose로 다시 분석한다.
두 경로는 랜드마크와 신뢰도만 제공하며 자세 상태를 직접 판정하지 않는다.

## 모델과 라이선스

| 항목 | 현재 계약 |
|---|---|
| 모델 리소스 | `Resources/PoseNetMobileNet075S16FP16.mlmodel` |
| 출처 | [Apple 샘플 `Detecting Human Body Poses in an Image`](https://developer.apple.com/documentation/coreml/detecting-human-body-poses-in-an-image)에 포함된 PoseNet |
| 변형 | MobileNet 0.75, output stride 16, FP16 |
| 모델 라이선스 | Apache-2.0 |
| 샘플 코드 라이선스 | MIT |
| 실행 위치 | 기기 내부 Core ML, CPU |

라이선스와 배포 출처는 [ThirdPartyNotices.md](../../Resources/ThirdPartyNotices.md)와 [Apache-2.0.txt](../../Resources/Apache-2.0.txt)에서 관리한다.

## 런타임 계약

1. RGB 이미지를 `scaleFill`로 513×513 BGRA 입력으로 변환한다.
2. 모델의 `heatmap`과 `offsets`에서 각 관절의 최대 신뢰도 위치와 오프셋을 읽는다.
3. nose, eyes, ears, shoulders, wrists를 공통 `PoseLandmarks`로 변환한다.
4. 머리 기준점과 양쪽 어깨가 신뢰도·너비·기울기 조건을 통과하면 PoseNet 결과를 사용한다.
5. 조건을 통과하지 못하거나 PoseNet 실행이 실패하면 `VNDetectHumanBodyPoseRequest`를 실행한다.
6. Vision의 좌하단 원점 좌표를 분석 도메인의 좌상단 원점 좌표로 변환한다.
7. Vision 후보가 없으면 PoseNet의 부분 검출을 보존해 사람 부재와 어깨 미검출을 구분한다.

현재 decoder는 모델의 displacement 출력을 사용하지 않고 관절별 최댓값으로 한 사람의 자세를 만든다.
화면 속 최종 대상은 이후 `UpperBodySubjectSelector`가 상체 크기와 버스트 내 위치 연속성으로 선택한다.

## 제품 경계와 한계

- PoseNet과 Vision의 confidence가 같은 척도라고 가정하지 않는다.
- PoseNet 손목은 실측에서 배경 고정점 오검출이 있어 판정 근거가 아니라 진단 정보로만 남긴다.
- 현재 PoseNet decoder는 다인 분리용 displacement를 사용하지 않는다.
- `scaleFill`은 원본 종횡비를 모델 입력에 맞게 바꾸므로 랜드마크 편향은 제품 데이터로 검증한다.
- 모델 누락·컴파일·실행 실패를 임의의 랜드마크로 대체하지 않는다.
- 최종 `good`·`bad`·`noEval`은 상대 깊이 특성값, 개인 기준 자세, 버스트 품질과 상태 지속성으로 결정한다.

## 구현 대응

- 모델 로딩과 decoding: [`PoseNetDetector.swift`](../../Sources/TurtleCore/Inference/PoseNetDetector.swift)
- Vision 2D 대체 경로: [`PoseDetector.swift`](../../Sources/TurtleCore/Inference/PoseDetector.swift)
- 랜드마크 품질 기준: [`Tuning.swift`](../../Sources/TurtleCore/Detection/Tuning.swift)
- 전체 판정 순서: [상세 판정 알고리즘](algorithm.md)
