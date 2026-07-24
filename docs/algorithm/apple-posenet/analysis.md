# Apple Core ML 샘플 PoseNet — 로직 분석

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 모델·decoder 로직 분석 |
| 적용 상태 | 상체 landmark 우선 추출기로 채택 |
| 입력 | RGB 이미지 → 513×513 BGRA `scaleFill` |
| 출력 | 17개 관절 후보 중 머리·양쪽 어깨를 공통 `PoseLandmarks`로 변환 |
| 제품 내 역할 | Depth Anything V2 ROI와 평가 가능성 판단을 위한 2D anchor 제공 |

## 1. 출처와 소유 경계

Apple의 “Detecting human body poses in an image”는 PoseNet을 **서드파티 Core ML 모델**을 사용하는 예제로 소개한다. 따라서 다음 둘을 같은 기능으로 취급하지 않는다.

- PoseNet 경로: 앱이 `.mlmodel`을 번들하고 Core ML로 직접 실행하며 tensor를 직접 해석한다.
- Vision 2D 경로: 운영체제가 제공하는 `VNDetectHumanBodyPoseRequest`를 실행하고 observation을 받는다.

PoseNet의 모델 artifact, 전처리, decoder, 라이선스와 배포 상태는 앱이 관리한다. Vision의 request revision과 지원 OS는 Vision 계약에 속한다.

## 2. 번들 모델 계약

현재 번들 artifact의 내장 metadata와 제품 코드는 다음 계약을 사용한다.

| 항목 | 값 |
|---|---|
| 모델 파일 | `Resources/PoseNetMobileNet075S16FP16.mlmodel` |
| backbone | MobileNetV1 |
| width multiplier | 0.75 |
| output stride | 16 |
| 제품 입력 크기 | 513×513 |
| 관절 수 | 17 |
| 출력 tensor | `heatmap`, `offsets`, `displacementFwd`, `displacementBwd` |

17개 관절의 순서는 nose, left/right eye, left/right ear, left/right shoulder, left/right elbow, left/right wrist, left/right hip, left/right knee, left/right ankle이다. Vision 2D가 제공하는 `neck`과 `root`는 PoseNet의 17개 관절에 없다.

## 3. 모델 출력의 의미

### heatmap

각 관절이 출력 grid의 각 cell에 있을 가능성을 나타낸다. 현재 단일 인물 decoder는 관절 `j`마다 heatmap 값이 가장 큰 cell `(x_j, y_j)`를 선택하고 그 값을 관절 confidence로 보존한다.

### offsets

출력 grid cell만 사용하면 위치가 stride 단위로 양자화된다. offsets는 선택한 cell 안에서 원래 입력 공간의 관절 위치를 보정한다. 현재 구현의 정규화 좌표는 다음과 같다.

```text
x = (gridX × 16 + xOffset) / 513
y = (gridY × 16 + yOffset) / 513
```

### forward/backward displacement

부모-자식 관절 사이의 변위를 나타내며 여러 사람의 관절을 한 pose로 조립할 때 사용한다. 현재 제품 decoder는 두 tensor를 읽지 않는다. 따라서 모델 artifact가 다인 추정을 지원한다는 사실만으로 현재 앱이 다인 분리나 대상 선택을 지원한다고 설명하면 안 된다.

## 4. 현재 단일 인물 decoding

1. 카메라 pixel buffer를 `CGImage`로 변환한다.
2. 이미지를 513×513 BGRA로 `scaleFill`한다.
3. Core ML `prediction(from:)`을 실행한다.
4. 각 관절 heatmap의 전역 최댓값 cell을 선택한다.
5. 해당 cell의 x/y offset을 더해 513 입력 기준 정규화 좌표를 만든다.
6. 17개 중 nose, eyes, ears, shoulders만 공통 `PoseLandmarks`에 전달한다.
7. 머리 anchor와 양쪽 어깨 추적 품질을 확인하고, 표준 어깨 기하 또는 명확한 머리 기준 측면 기하를 만들 수 있으면 PoseNet 결과를 사용한다.
8. 조건을 통과하지 못하거나 모델 실행이 실패하면 Apple Vision 2D로 fallback한다.

Apple 샘플이 설명하는 단일 인물 방식과 같은 핵심 원리지만, 샘플 전체 decoder를 그대로 사용한다고 간주하지 않는다. 특히 pose-level score, 다인 root 후보와 displacement 기반 조립은 현재 제품 경로에 없다.

## 5. 좌표계와 영상 변환

PoseNet 결과는 513×513 모델 입력의 좌상단 원점 정규화 좌표로 해석된다. Vision 2D는 원본 이미지의 좌하단 원점 정규화 좌표를 반환하므로 최소한 y축 원점 계약이 다르다.

현재 `scaleFill`은 crop 없이 원본을 정사각형으로 늘인다. 따라서 x·y 정규화 비율은 원본에 선형 대응하지만 모델이 보는 신체 비율이 달라져 landmark 자체가 편향될 수 있다. 아래를 각각 검증한다.

- 가로로 긴 카메라 프레임에서 머리·어깨 위치가 원본 프레임에 올바르게 대응하는가
- PoseNet anchor로 만든 ROI가 Depth Anything V2의 동일 인물 영역과 겹치는가
- orientation과 화면 미러링이 분석 좌표를 이중 반전하지 않는가
- PoseNet과 Vision fallback 전환 전후에 같은 공통 좌표 계약을 유지하는가

원점, orientation, 전처리와 모델 오차를 무시한 채 두 detector의 정규화 숫자만 같다고 보는 것은 안전하지 않다.

## 6. confidence와 품질 게이트

TensorFlow PoseNet 자료는 관절별 score가 해당 keypoint의 confidence를 나타낸다고 설명한다. 하지만 confidence는 모델 사이에 보정된 공통 확률이 아니다. PoseNet score와 Vision recognized point confidence에 같은 threshold를 적용하려면 제품 데이터 검증이 필요하다.

제품 경로는 단순한 score 하나가 아니라 다음 조건을 함께 사용한다.

- nose·eyes·ears 중 신뢰 가능한 머리 anchor가 하나 이상 존재
- left/right shoulder가 모두 신뢰 가능
- 어깨 폭이 최소값 이상
- 표준 입력은 어깨 기울기가 허용 범위 이내
- 한쪽 귀만 보이는 측면·3/4 입력은 머리 아래의 평가 가능한 어깨가 명확함

이 조건은 pose의 평가 가능성을 정한다. 자세가 바른지 여부를 정하지 않는다.

## 7. 실패 조건과 fallback 계약

다음 경우 PoseNet 결과를 사용하지 않고 같은 프레임의 Vision 2D 결과를 시도한다.

- 모델 파일을 찾거나 compile/load할 수 없음
- 입력 이미지를 만들 수 없음
- `heatmap` 또는 `offsets`가 없음
- 머리·양쪽 어깨 추적 품질이 부족하거나 표준·측면 상체 기하를 모두 만들 수 없음

fallback은 detector 교체이지 두 모델 관절의 혼합이 아니다. 한 프레임의 PoseNet 머리와 Vision 어깨를 합성하지 않는다. Vision도 후보를 내지 못하면 PoseNet의 부분 검출을 보존한다. 하류 분석은 신뢰할 수 있는 머리가 있으면 자세 기인 평가 불가 여부를 판단하고, 머리조차 없으면 `noEval`로 보낸다.

## 8. 제품 적용 경계

- PoseNet은 2D landmark·confidence를 제공한다.
- PoseNet은 깊이, 실제 거리, 임상 CVA, 자세 상태를 제공하지 않는다.
- 17개 관절을 모두 계산하더라도 현재 제품은 상체 ROI에 필요한 부분만 사용한다.
- displacement decoder를 구현하기 전에는 다인 pose를 지원한다고 표시하지 않는다.
- 모델이나 decoder를 바꾸면 좌표 정렬, threshold, 성능, 라이선스를 다시 검증한다.

전체 판정 순서는 [`../posture-analysis-workflow.md`](../posture-analysis-workflow.md), Vision fallback은 [`../apple-body-pose/analysis.md`](../apple-body-pose/analysis.md)를 따른다.
