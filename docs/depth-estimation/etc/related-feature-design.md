# 관련 연구 — relative depth feature 설계

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | depth feature·측정 방식 조사 |
| 적용 상태 | 검증 필요 |
| 다루는 범위 | 2D body-pose ROI, relative depth 집계, affine-invariant 표현 |
| 제품 내 역할 | DA-V2 출력에서 자세 분석용 신호를 만드는 최소 설계 정의 |

## 입력과 역할

- PoseNet·Vision 2D: 머리·어깨 landmark와 confidence
- DA-V2 Small: relative inverse-depth map
- 프로젝트 자세 분석기: ROI 집계, baseline 비교, 최종 판정

depth map에는 신체 부위 라벨이 없고, Vision landmark에는 깊이가 없다. 따라서 두 출력을 같은 원본 이미지 좌표로 정렬해 사용한다.

## 최소 처리 흐름

1. 2D body-pose 품질을 확인한다.
2. landmark로 머리 ROI와 몸통 ROI를 정한다.
3. landmark 기반 reference ROI를 만들고 경계 픽셀을 제외한다.
4. 각 ROI의 median depth를 계산한다.
5. reference ROI의 IQR로 머리-몸통 차이를 정규화한다.
6. 버스트의 대표값을 개인 baseline과 비교한다.

후보 식은 다음과 같다.

```text
head    = median(depth in valid head ROI)
torso   = median(depth in valid torso ROI)
scale   = IQR(depth in landmark-based reference ROI)
feature = direction * (head - torso) / scale
```

`scale`이 최소 품질 조건을 충족할 때만 feature를 계산한다. `d' = a·d + b`, `a > 0`인 전역 affine 변환에서는 분자와 IQR이 같은 scale을 받으므로 feature가 보존된다. 단, 이것은 전역 scale·shift만 제거하며 국소 depth 왜곡과 ROI 오류는 제거하지 못한다.

## 품질 조건

다음 중 하나라도 만족하지 못하면 `noEval`이다.

- 필수 landmark confidence
- 머리·몸통 ROI의 최소 유효 픽셀 수
- ROI가 화면 경계 또는 배경에 과도하게 닿지 않음
- reference ROI IQR이 수치적으로 충분함
- 버스트 내 feature 분산이 허용 범위 이내

고정 pixel 크기, 최소 면적과 분산 임계는 제품 해상도와 데이터로 정한다.

## 검증 항목

- 고정 fixture에서 near/far 방향과 전처리 후 좌표 정렬
- 같은 자세 반복 시 feature 분산
- 중립·악화 자세의 개인 내 분리도
- median과 IQR 기반 표현의 반복성
- 3~5장 범위의 프레임 수에 따른 분산 감소와 지연
- 전체 처리 지연·발열·배터리

Sapiens, human matting, 별도 segmentation·depth 모델, 시점별 feature는 현재 설계에 추가하지 않는다. 먼저 위 최소 경로의 유효성을 확인한다.

## 참고 자료

- Depth Anything V2 논문: <https://arxiv.org/abs/2406.09414>
- Apple Vision 2D body pose: <https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images>
- Apple Core ML 샘플 PoseNet 분석: [../../algorithm/apple-posenet/analysis.md](../../algorithm/apple-posenet/analysis.md)
- Apple Vision 2D 분석: [../../algorithm/apple-body-pose/analysis.md](../../algorithm/apple-body-pose/analysis.md)
- 채택 모델 분석: [../depth-anything-v2/analysis.md](../depth-anything-v2/analysis.md)
- 확정 워크플로우: [../../algorithm/posture-analysis-workflow.md](../../algorithm/posture-analysis-workflow.md)
