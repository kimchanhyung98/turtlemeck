# 관련 연구 — 시계열·비디오 depth

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 시간 일관성 방식 조사 |
| 적용 상태 | 비디오 depth 모델 미채택 |
| 다루는 범위 | 단일 이미지 depth의 프레임 변동과 최소 대응 |
| 제품 내 역할 | 비디오 모델을 현재 플로우에 추가하지 않는 근거 기록 |

## 확인된 문제

단일 이미지 depth 모델을 영상의 각 프레임에 독립 적용하면 temporal flicker가 생길 수 있다. Video Depth Anything은 이 문제를 직접 다루며 긴 영상에서 일관된 relative depth를 만드는 것을 목표로 한다.

하지만 시간 일관성 개선은 다음을 보장하지 않는다.

- 절대 거리(cm) 정확도
- 머리-몸통 국소 차이 정확도
- 자세 판정 정확도
- Mac 온디바이스 전력·발열 적합성

Video Depth Anything의 기본 출력도 affine-invariant이므로 video 모델 하나로 절대 측정 문제가 해결되는 것은 아니다.

## 현재 결정

비디오 depth 모델과 별도 시간 필터는 사용하지 않는다. 우선 다음 최소 방식만 검증한다.

1. DA-V2 Small로 짧은 버스트의 각 프레임을 처리한다.
2. 품질을 통과한 relative-depth feature의 median을 대표값으로 쓴다.
3. 버스트 내 MAD/IQR로 불안정한 구간을 `noEval` 처리한다.
4. 지속된 `bad`만 상태 전이한다.

이 방식으로 반복성과 오경보 요구를 충족하지 못한 경우에만 video depth 또는 추가 필터를 별도 기획으로 검토한다.

## 검증 항목

- 고정 자세에서 프레임별 feature 분산
- 버스트 크기에 따른 분산 감소와 지연
- 움직임 직후 안정화 시간
- 전체 Mac 지연·발열·배터리

## 참고 자료

- Video Depth Anything 논문: <https://arxiv.org/abs/2501.12375>
- Video Depth Anything 공식 저장소: <https://github.com/DepthAnything/Video-Depth-Anything>
- 채택 DA-V2 분석: [../depth-anything-v2/analysis.md](../depth-anything-v2/analysis.md)
- 확정 워크플로우: [../../algorithm/posture-analysis-workflow.md](../../algorithm/posture-analysis-workflow.md)
