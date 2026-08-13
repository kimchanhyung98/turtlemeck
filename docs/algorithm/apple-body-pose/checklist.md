# 자세 분석 목표 설계 적합성 체크리스트

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 비규범 검증 체크리스트 |
| 적용 상태 | 보조 |
| 다루는 범위 | 입력, 신체 추정, ROI, depth, 기준 자세, 판정 계약 |
| 제품 내 역할 | 구현이 목표 설계와 일치하는지 기록하며 설계 자체는 변경하지 않음 |

이 문서는 현재 구현이 [`posture-analysis-workflow.md`](../posture-analysis-workflow.md)의 상세 흐름과 채택·제외 범위를 지키는지 확인하는 비규범 체크리스트다.
체크리스트 자체가 상세 워크플로우의 계약을 바꾸지는 않는다.
[`../../workflow.md`](../../workflow.md)는 상위 개론으로만 사용한다.

API 사실은 Vision 2D [analysis.md](analysis.md), 목표 알고리즘은 [`posture-analysis-workflow.md`](../posture-analysis-workflow.md)를 기준으로 한다.
특정 코드 라인만으로 충족을 판정하지 않고 계약을 재현하는 테스트와 제품 데이터를 함께 확인한다.

## 요약 다이어그램

```mermaid
flowchart TD
    SPEC["목표 알고리즘"]
    SPEC --> INPUT["입력·orientation·대상 사람"]
    SPEC --> SIGNAL["2D 자세 관절점·ROI·품질<br/>DA-V2 상대 깊이 특성값"]
    SPEC --> QUALITY["실제 품질·ROI·시간 일관성"]
    SPEC --> DECISION["기준 자세·품질·시간 조건<br/>good/bad/noEval"]
    INPUT --> TEST["적합성 테스트"]
    SIGNAL --> TEST
    QUALITY --> TEST
    DECISION --> TEST
    TEST --> REPORT["충족·미충족·근거 부족"]
```

## 1. 입력 계약

- 프레임 orientation과 미러링 정보를 실제 입력과 일치시킨다.
- 분석 세션을 최소 15초 간격으로 실행한다.
- 한 번의 분석에서 최대 5장의 짧은 이미지 버스트를 사용하고, 유효 프레임이 2장 이상일 때 판정한다.
- 한 버스트 안에서 같은 대상 사람을 추적한다.
- 다인 장면에서는 `first` 같은 배열 순서가 아니라 명시적인 대상 선택 규칙을 사용한다.
- 사람 전체가 아닌 머리·어깨·상부 몸통이 필요한 비율로 보이는지 확인한다.
- 입력이 불충분하면 관절이나 ROI를 합성해 `good`을 만들지 않고 `noEval`로 보낸다.

## 2. PoseNet·Apple Vision 2D 신체 추정 계약

- Apple Core ML 샘플 PoseNet과 운영체제 Vision 2D API를 같은 기술로 설명하지 않는다.
- PoseNet 실행이 실패하거나 결과가 상체 품질 조건을 통과하지 못하면 같은 프레임에 Vision 2D를 실행한다.
- 한 프레임에서 두 detector의 부분 관절을 합성하지 않는다.
- PoseNet에는 `neck`이 없으므로 Vision의 `neck`을 공통 필수점으로 만들지 않는다.
- Vision의 좌하단 정규화 좌표를 제품 내부 좌표계로 명시적으로 변환한다.
- PoseNet의 `scaleFill` 좌표가 원본·depth 좌표와 일치하는지 별도로 검증한다.
- 관절별 confidence를 보존하고, 추적 가능 여부와 판정 적합 여부를 구분한다.
- 2D 관절 자체가 `good`·`bad`를 반환한다고 설명하지 않는다.
- PoseNet·Vision 2D 관절점은 DA-V2용 ROI, 입력 품질과 자세 기하 판단에 사용한다.
- 임상 C7·tragus가 없으므로 자체 머리-어깨 각을 CVA라고 표시하지 않는다.

## 3. ROI 계약

- 머리·몸통과 정규화 기준 ROI는 PoseNet·Vision 2D의 공통 body landmark로 정의한다.
- 얼굴 관찰·사람 마스크를 확정 흐름의 필수 입력으로 추가하지 않는다.
- ROI 경계 침식과 최소 픽셀 수를 검사한다.
- 화면 경계 접촉률과 유효 depth 비율을 품질 값으로 기록한다.
- 한쪽 어깨나 머리 anchor가 없을 때 고정 거리로 가짜 관절을 만들지 않는다.

## 4. Depth Anything V2 깊이 추정 계약

- 기본 depth 모델은 Depth Anything V2 Small이며, Core ML은 해당 모델의 실행·배포 형식임을 구분한다.
- DA-V2가 자세·관절이나 `good`·`bad`를 직접 출력한다고 설명하지 않는다.
- DA-V2 출력이 affine-invariant inverse depth임을 전제로 한다.
- 절대 cm, 카메라와의 실제 거리, 임상 심각도 점수로 변환하지 않는다.
- 단순 ROI 평균 차이나 비율만을 최종 feature로 확정하지 않는다.
- 현재 특성값은 관절점 기반 reference ROI의 견고한 스케일로 정규화한 머리-몸통 대비다.
- 출력 near/far 방향은 고정 fixture로 확인한다.
- reference ROI의 IQR이 너무 작거나 depth가 유효하지 않으면 해당 프레임을 제외하고, 유효 프레임이 부족하면 버스트를 `noEval`로 처리한다.

## 5. 미사용 API 경계

- Vision 3D, 얼굴 관찰과 사람 마스크 출력을 판정 특성값·기준 자세·융합 입력에 넣지 않는다.
- 호환 센서 depth가 없는 3D skeleton을 실제 머리 전방 거리로 해석하지 않는다.

## 6. baseline·시간 처리 계약

- baseline은 첫 실행 자동 보정이나 사용자가 시작한 기준 자세 보정의 여러 프레임 분포로 만든다.
- 저장한 기준 자세의 객관적 바름은 별도로 판정하지 않는다.
- 일상 판정 결과나 고분산 구간을 사용자가 저장한 baseline에 자동 흡수하지 않는다.
- 프레임 feature는 reference ROI의 IQR로 정규화한다.
- 버스트 대표값은 중앙값, 버스트 분산은 MAD로 계산한다.
- 기준 자세 중심은 유효 버스트 중앙값의 중앙값으로 저장한다.
- 기준 자세 분산은 각 유효 버스트 MAD의 중앙값과 버스트 중심 간 MAD 중 큰 값으로 저장한다.
- 단일 프레임의 강한 값만으로 `bad` 알림을 확정하지 않는다.

## 7. 판정 계약

- 필수 입력과 품질 조건을 충족하고 기준 자세 범위 안에 있을 때 정상 증거를 생성한다.
- 저장된 baseline에서 충분히 이탈하거나 자세 때문에 정상을 확인할 수 없는 패턴이 우세할 때 악화 증거를 생성한다.
- 상태 머신이 정상·악화·불충분·`noEval` 증거의 시간 연속성을 적용해 `good`·`bad`·`noEval`을 결정한다.
- 사람 없음·대상 모호성·모델 또는 depth 품질 실패는 악화 증거로 사용하지 않고, 남은 유효 프레임이 부족하면 `noEval`로 처리한다.
- 높은 버스트 분산은 `noEval`로 처리한다.
- 신뢰할 수 있는 머리가 있는 상태의 어깨 가림·상체 잘림·머리 기준 측면 기하로도 해소되지 않는 큰 회전·머리 처짐이 프레임의 과반이면 자세 기인 악화 증거로 처리한다.
- `noEval`을 정상으로 표시하거나 정상 증거 연속 횟수에 합산하지 않는다.
- 판정 결과와 함께 사용한 특성값, 기준 자세 차이, 품질 값과 제외 사유를 남긴다.

## 8. 검증 결과 기록 형식

구현 단계에서는 각 항목을 다음 세 상태로만 기록한다.

| 상태 | 의미 |
|---|---|
| 충족 | 사전 정의한 테스트와 데이터로 목표 계약을 확인함 |
| 미충족 | 목표와 다른 동작을 재현함 |
| 근거 부족 | 테스트·데이터가 없어 판단할 수 없음 |

“현재 코드와 동일함”이나 “수정 완료”는 충족의 근거가 아니다.
문서의 입력·feature·품질·판정 계약을 재현하는 테스트 결과가 있어야 한다.

## 참고 자료

- 상위 개론: [`../../workflow.md`](../../workflow.md)
- 상세 목표 알고리즘과 채택·제외 범위: [`../posture-analysis-workflow.md`](../posture-analysis-workflow.md)
- Apple Core ML 샘플 PoseNet: [`../apple-posenet/analysis.md`](../apple-posenet/analysis.md)
- Apple Vision 2D API: [analysis.md](analysis.md)
- depth feature: [`../../depth-estimation/etc/related-feature-design.md`](../../depth-estimation/etc/related-feature-design.md)
- 기준 자세: [`../pose-estimation/related-baseline-calibration.md`](../pose-estimation/related-baseline-calibration.md)
