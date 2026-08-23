# 리서치 보관소

채택 여부와 관계없이 리서치 과정에서 만든 기술 자료와 과거 검토 기록을 보관한다.
이 디렉터리의 문서는 현재 제품 동작이나 구현의 정본이 아니다.
다른 문서는 이 디렉터리에 의존하지 않으며, 현재 동작은 코드, `docs/*.md`, `docs/posture-analysis/*.md`를 기준으로 확인한다.

## 분류 기준

- 기술 조사 자료: 채택 여부와 관계없이 조사 과정과 판단 근거를 기록한 문서
- 조사 종료 자료: 현재 실행 경로와 리소스에 포함되지 않은 기술 조사
- 과거 검토 기록: 2026-07-21 당시 문서·코드를 대조한 검토 스냅샷
- 과거 채택 검토: 구현 선택을 마친 뒤 코드와 대조한 결과를 역사 기록으로 보관

## 조사 종료 자료

| 자료 | 조사 결과 | 현재 코드 관계 |
|---|---|---|
| [Face observation과 person instance mask](algorithm/apple-body-pose/related-person-observations.md) | 미채택 | 실행 경로에서 사용하지 않음 |
| [Apple Vision 3D body pose](algorithm/apple-body-pose/related-vision-3d.md) | 제외 | 3D 요청과 관절을 사용하지 않음 |
| [Apple Depth Pro](depth-estimation/apple-depth-pro/README.md) | 미채택 | 모델·런타임·리소스 없음 |
| [Metric depth 모델군](depth-estimation/metric-depth-models/README.md) | 미채택 | 모델·런타임·리소스 없음 |
| [시계열·비디오 depth](depth-estimation/etc/related-temporal-video-depth.md) | 미채택 | 비디오 depth 모델과 시간 필터를 사용하지 않음 |

## 과거 검토 기록

다음 문서는 2026-07-21 당시 경로와 행 번호를 기준으로 작성한 역사 기록이다.
현재 문서와 코드의 정확성을 판단하는 정본으로 사용하지 않는다.

| 대상 | 검토 기록 |
|---|---|
| 알고리즘 인덱스와 상세 워크플로우 | [검토 기록](reviews/algorithm/review.md) |
| Apple Vision body pose | [검토 기록](reviews/algorithm/apple-body-pose/review.md) |
| Apple Core ML 샘플 PoseNet | [검토 기록](reviews/algorithm/apple-posenet/review.md) |
| 자세 추정 방식 | [검토 기록](reviews/algorithm/pose-estimation/review.md) |
| 깊이 추정 인덱스 | [검토 기록](reviews/depth-estimation/review.md) |
| Apple Depth Pro | [검토 기록](reviews/depth-estimation/apple-depth-pro/review.md) |
| Apple Vision과 플랫폼 depth | [검토 기록](reviews/depth-estimation/apple-vision-depth/review.md) |
| Depth Anything V2 | [검토 기록](reviews/depth-estimation/depth-anything-v2/review.md) |
| Depth 교차 연구 | [검토 기록](reviews/depth-estimation/etc/review.md) |
| Metric depth 모델군 | [검토 기록](reviews/depth-estimation/metric-depth-models/review.md) |
