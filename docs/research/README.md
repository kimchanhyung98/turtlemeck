# 리서치 보관소

현재 코드에 채택되지 않았거나 조사 단계에서 종료한 자료를 보관한다.
이 디렉터리의 문서는 현재 제품 동작이나 구현의 정본이 아니다.
현재 기준은 [`algorithm/`](../algorithm/README.md), [`depth-estimation/`](../depth-estimation/README.md), [자세 분석 상세 워크플로우](../algorithm/posture-analysis-workflow.md)에서 확인한다.

## 분류 기준

- 조사 종료 자료: 현재 실행 경로와 리소스에 포함되지 않은 기술 조사
- 과거 검토 기록: 2026-07-21 당시 문서·코드를 대조한 검토 스냅샷
- 채택 자료: 현재 코드와 직접 연결되므로 이 디렉터리가 아닌 `docs/algorithm` 또는 `docs/depth-estimation`에서 관리

## 조사 종료 자료

| 자료 | 조사 결과 | 현재 코드 관계 | 현재 기준 |
|---|---|---|---|
| [Face observation과 person instance mask](algorithm/apple-body-pose/related-person-observations.md) | 미채택 | 실행 경로에서 사용하지 않음 | [Apple Vision 2D fallback](../algorithm/apple-body-pose/analysis.md) |
| [Apple Vision 3D body pose](algorithm/apple-body-pose/related-vision-3d.md) | 제외 | 3D 요청과 관절을 사용하지 않음 | [자세 추정 분석](../algorithm/pose-estimation/analysis.md) |
| [Apple Depth Pro](depth-estimation/apple-depth-pro/README.md) | 미채택 | 모델·런타임·리소스 없음 | [Depth Anything V2](../depth-estimation/depth-anything-v2/README.md) |
| [Metric depth 모델군](depth-estimation/metric-depth-models/README.md) | 미채택 | 모델·런타임·리소스 없음 | [Depth Anything V2](../depth-estimation/depth-anything-v2/README.md) |
| [시계열·비디오 depth](depth-estimation/etc/related-temporal-video-depth.md) | 미채택 | 비디오 depth 모델과 시간 필터를 사용하지 않음 | [자세 분석 상세 워크플로우](../algorithm/posture-analysis-workflow.md) |

## 과거 검토 기록

다음 문서는 2026-07-21 당시 경로와 행 번호를 기준으로 작성한 역사 기록이다.
현재 문서와 코드의 정확성을 판단하는 정본으로 사용하지 않는다.

| 대상 | 검토 기록 | 현재 문서 |
|---|---|---|
| 알고리즘 인덱스와 상세 워크플로우 | [검토 기록](reviews/algorithm/review.md) | [알고리즘 문서](../algorithm/README.md) |
| Apple Vision body pose | [검토 기록](reviews/algorithm/apple-body-pose/review.md) | [Apple Vision 문서](../algorithm/apple-body-pose/README.md) |
| Apple Core ML 샘플 PoseNet | [검토 기록](reviews/algorithm/apple-posenet/review.md) | [PoseNet 문서](../algorithm/apple-posenet/README.md) |
| 자세 추정 방식 | [검토 기록](reviews/algorithm/pose-estimation/review.md) | [자세 추정 문서](../algorithm/pose-estimation/README.md) |
| 깊이 추정 인덱스 | [검토 기록](reviews/depth-estimation/review.md) | [깊이 추정 문서](../depth-estimation/README.md) |
| Apple Depth Pro | [검토 기록](reviews/depth-estimation/apple-depth-pro/review.md) | [조사 종료 자료](depth-estimation/apple-depth-pro/README.md) |
| Apple Vision과 플랫폼 depth | [검토 기록](reviews/depth-estimation/apple-vision-depth/review.md) | [Apple 플랫폼 depth 문서](../depth-estimation/apple-vision-depth/README.md) |
| Depth Anything V2 | [검토 기록](reviews/depth-estimation/depth-anything-v2/review.md) | [Depth Anything V2 문서](../depth-estimation/depth-anything-v2/README.md) |
| Depth 교차 연구 | [검토 기록](reviews/depth-estimation/etc/review.md) | [현재 feature 설계](../depth-estimation/etc/related-feature-design.md) |
| Metric depth 모델군 | [검토 기록](reviews/depth-estimation/metric-depth-models/review.md) | [조사 종료 자료](depth-estimation/metric-depth-models/README.md) |
