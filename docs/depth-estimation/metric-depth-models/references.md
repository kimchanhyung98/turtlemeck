# Metric depth 모델군 — 참고 자료

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 공식 자료·1차 연구 목록 |
| 적용 상태 | 근거 문서 |
| 제품 내 역할 | [analysis.md](analysis.md)의 scale·intrinsic·라이선스 주장 추적 |

## 핵심 근거

| 주장 | 근거 수준 | 대표 출처 |
|---|---|---|
| ZoeDepth·Metric3D·UniDepth는 metric depth를 목표로 하지만 scale 복원 방식이 다름 | 1차 연구·공식 자료 | 각 모델의 논문·공식 저장소 |
| camera intrinsic을 다루는 방식과 알려진 scale 한계가 모델마다 다름 | 1차 연구·공식 자료 | Metric3D·UniDepth 논문과 저장소 |
| 라이선스와 실행 경로가 달라 현재 Mac 제품 경로에 바로 추가할 수 없음 | 공식 자료 기반 제품 판단 | 각 모델의 공식 저장소·라이선스 |

## 공식 문서와 1차 자료

- ZoeDepth 논문: <https://arxiv.org/abs/2302.12288>
- ZoeDepth 공식 저장소(2025년 5월 보관, MIT): <https://github.com/isl-org/ZoeDepth>
- Metric3D v2 논문: <https://arxiv.org/abs/2404.15506>
- Metric3D 공식 저장소(BSD-2-Clause): <https://github.com/YvanYin/Metric3D>
- UniDepth 논문: <https://arxiv.org/abs/2403.18913>
- UniDepth V2 논문: <https://arxiv.org/abs/2502.20110>
- UniDepth 공식 저장소(CC BY-NC 4.0): <https://github.com/lpiccinelli-eth/UniDepth>

## 추가·관련 자료

- 현재 채택 모델: [../depth-anything-v2/README.md](../depth-anything-v2/README.md)
- Apple metric depth 모델: [../apple-depth-pro/README.md](../apple-depth-pro/README.md)
- 확정 워크플로우: [../../algorithm/posture-analysis-workflow.md](../../algorithm/posture-analysis-workflow.md)

## 직접 적용하지 않는 범위

- 서로 다른 데이터셋의 AbsRel·δ1을 모델 순위로 사용하지 않는다.
- unknown-intrinsics 지원만으로 근거리 상체의 절대 scale 정확도를 확정하지 않는다.
- 별도 런타임·라이선스·제품 실측 없이 현재 DA-V2 Small 경로를 교체하지 않는다.
