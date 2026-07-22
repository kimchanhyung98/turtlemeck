# 상체 중심 자세 추정 — 로직 분석

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 로직 분석·설명 |
| 적용 상태 | PoseNet 우선 채택, Vision 2D fallback, Vision 3D 제외 |
| 입력 | RGB 프레임, 2D body-pose landmark, DA-V2 relative depth |
| 출력 | 머리·몸통 relative-depth feature와 품질 상태 |
| 제품 내 역할 | 확정 워크플로우의 자세 분석 원리와 경계 설명 |

## 1. 확정 역할

자세 분석은 모델 하나가 직접 수행하지 않는다.

| 단계 | 입력 | 출력 |
|---|---|---|
| PoseNet·Vision 2D | RGB 프레임 | 2D 관절과 관절별 confidence |
| DA-V2 Small | 같은 RGB 프레임 | relative inverse-depth map |
| 프로젝트 자세 분석기 | landmark, depth map, baseline | `good`·`bad`·`noEval` |

PoseNet을 우선 사용하고 상체 품질 게이트를 통과하지 못하면 Vision 2D로 fallback하여 머리·몸통 ROI를 정한다. DA-V2는 각 픽셀의 상대 깊이를 제공한다. 어느 모델도 자체적으로 거북목 여부를 판정하지 않는다.

## 2. 필요한 2D body-pose 정보

Apple 공식 샘플의 PoseNet은 17개 body keypoint를, Vision의 `VNDetectHumanBodyPoseRequest`는 최대 19개 body point를 정규화된 2D 좌표와 confidence로 반환한다. 현재 경로의 필수점은 nose·eyes·ears 중 신뢰 가능한 머리 anchor와 left/right shoulder다. neck은 Vision에서 제공될 때 진단 정보로 보존하지만 필수점은 아니다.

- 머리 anchor: nose·eyes·ears 중 품질을 충족하는 점
- 몸통 anchor: 양쪽 shoulder의 중점
- 품질 확인: 필수점 confidence, 화면 경계 접촉, ROI 유효 면적

face observation과 person instance mask도 조사했지만 확정 흐름에는 넣지 않는다. PoseNet과 Vision은 공통 `PoseLandmarks` 계약으로 합쳐지고, 모델별 자동 판정 분기는 만들지 않는다.

## 3. relative depth feature

DA-V2 기본 모델의 출력은 affine-invariant inverse depth다. 출력에 전역 변환 `d' = a·d + b`가 적용될 수 있으므로 raw 값이나 raw ROI 차이를 프레임 간 절대량으로 비교하지 않는다.

검증 대상 표현은 머리·몸통 ROI의 견고한 대표값 차이를 landmark 기반 reference ROI의 견고한 scale로 정규화한다. 정확한 후보 식과 품질 조건은 한 곳에서 관리하도록 [relative depth feature 설계](../../depth-estimation/etc/related-feature-design.md)에 정의한다. 이 표현은 전역 scale·shift의 영향은 제거하지만 모델의 국소 왜곡, 머리카락·의복 경계, 가림, ROI 누출까지 제거하지는 못한다. 따라서 문헌이 보장한 완성 지표가 아니라 제품 데이터로 확인할 설계 가설이다.

near/far 방향은 고정 fixture로 확인한다. reference ROI의 변동 범위나 유효 픽셀 수가 부족하면 `noEval`이다.

## 4. baseline과 시간 처리

앱의 값은 임상 CVA가 아니고 카메라 배치와 개인 체형의 영향을 받으므로, 사용자가 명시적으로 저장할 기준 자세에서 여러 프레임을 모아 개인 baseline을 만든다. UI는 중립 자세를 안내하지만 알고리즘은 그 기준의 객관적 바름을 별도로 판정하지 않는다.

1. 사용자가 명시적으로 시작한 보정에서 품질을 통과한 기준 자세 프레임만 사용한다.
2. median과 MAD/IQR 같은 견고한 통계로 baseline과 변동 범위를 기록한다.
3. 일상 판정 결과를 baseline에 자동 흡수하지 않는다.
4. 짧은 버스트의 대표값을 baseline과 비교한다.
5. 한 번의 나쁜 값이 아니라 지속된 변화만 `bad`로 확정한다.

분석 세션은 최소 20초 간격으로 실행하고 버스트는 3~5장으로 제한한다. 이 범위에서 사용할 프레임 수, 판정 임계와 상태 전이 지속 시간은 자체 데이터의 오경보·미탐·지연으로 결정한다.

## 5. 실패 조건

다음 기술적 조건에서는 정상으로 추정하지 않고 프레임을 제외하며, 유효 프레임이 부족하면 버스트를 `noEval`로 반환한다.

- 신뢰할 수 있는 머리 landmark가 없거나 대상을 구분할 수 없음
- 모델·depth 실행 실패 또는 ROI 기하 불일치
- depth ROI의 유효 픽셀이나 reference ROI 변동 범위가 부족함

유효 프레임이 충분해도 버스트 내 feature 분산이 허용 범위를 넘으면 버스트 전체를 `noEval`로 반환한다.

반면 신뢰할 수 있는 머리는 감지됐지만 어깨 가림·상체 잘림·큰 회전·머리 처짐 때문에 정상 자세를 확인할 수 없는 프레임이 과반이면 `noEval`이 아니라 비정상 증거로 처리한다.

## 6. 사용하지 않는 방식

- Vision 3D: RGB에서 실행 가능하지만 hip-rooted 17-joint skeleton 추정이며 dense/measured depth가 아니다. 관절별 confidence도 없으므로 목표 판정 경로에서 제외한다.
- MediaPipe·MoveNet·OpenPose·YOLO-Pose: 유효한 대안이지만 현재 역할을 PoseNet·Vision 조합이 충족하므로 추가 런타임과 모델을 넣지 않는다.
- 시점별 알고리즘 라우팅: 정면·측면·3/4마다 별도 feature와 baseline을 운영하지 않는다.
- 임상 CVA·절대 cm: C7/tragus와 측면 표준 촬영이 없고 DA-V2도 metric depth가 아니므로 출력하지 않는다.
- 자동 baseline 적응: 나쁜 자세를 정상 기준에 흡수할 위험이 있어 사용하지 않는다.

## 7. 검증 범위

채택 모델은 확정됐지만 다음 수치는 아직 확정되지 않았다.

- PoseNet·Vision ROI의 반복성과 fallback 안정성
- relative-depth feature의 정상·악화 자세 분리도
- 3~5장 범위의 프레임 수와 품질 임계
- baseline 대비 판정 임계와 지속 시간
- 최종 오경보율·미탐률·coverage

이 항목은 모델 재선정 문제가 아니라 확정 플로우의 제품 검증 문제다. 전체 기준은 [`../posture-analysis-workflow.md`](../posture-analysis-workflow.md)를 따른다.

## 관련 문서

- 공식 문서와 1차 연구: [references.md](references.md)
- 대안 모델 조사: [comparison.md](comparison.md)
- CVA와 의료 표현 경계: [related-cva-metrics.md](related-cva-metrics.md)
- 단안 한계: [related-monocular-limits.md](related-monocular-limits.md)
- baseline: [related-baseline-calibration.md](related-baseline-calibration.md)
