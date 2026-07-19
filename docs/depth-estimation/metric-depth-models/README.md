# Metric depth 모델군 — 미채택 리서치

> 이 문서는 참고용 리서치이며, 현재 확정된 제품 플로우를 직접 정의하거나 구현 기준으로 활용하지 않습니다.

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | metric depth 모델군 비교 |
| 적용 상태 | 미채택, 리서치 참고 자료 |
| 입력 | 단일 RGB 이미지와 모델별 카메라 정보 |
| 출력 | metric depth 또는 metric 3D geometry 추정 |
| 제품 내 역할 | 현재 사용하지 않는 metric 대안과 이유 기록 |

## 제품 적용 판단

현재 정면 depth는 DA-V2 Small로 확정했다. Metric3D, UniDepth, ZoeDepth 같은 모델은 절대 scale을 다루는 방식이 서로 다르고 별도 런타임·라이선스·카메라 조건을 추가한다. 머리-몸통 국소 차이에 대한 직접 검증도 없으므로 제품 플로우에 넣지 않는다.

## 핵심 차이

| 모델 | metric scale 처리 | 현재 미채택 이유 |
|---|---|---|
| ZoeDepth | 학습된 metric bins로 depth 회귀 | 공식 저장소가 보관 상태이며 카메라·도메인 변화와 Mac 배포 경로를 별도 검증해야 함 |
| Metric3D v2 | canonical camera space와 focal length로 scale 복원 | focal length 입력·추정 경로와 Mac 배포를 별도 검증해야 함 |
| UniDepth | camera module이 intrinsic을 함께 추정 | scale 실패 가능성, 비상업 라이선스, 별도 런타임 |

공개 장면 벤치마크의 AbsRel·δ1은 머리-몸통 국소 깊이 차이나 자세 분류 정확도가 아니다. 모델 간 수치도 평가 조건이 달라 현재 문서에서 순위로 사용하지 않는다.

## 문서 구성

| 문서 | 역할 |
|---|---|
| 본 README | 상태·요약·미채택 판단 |
| [analysis.md](analysis.md) | metric scale·intrinsic·라이선스 차이 |
| [references.md](references.md) | 공식 저장소·논문·라이선스 |
