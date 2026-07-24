# 관련 연구 — 단안 카메라의 한계와 대응

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 단안 자세·깊이 한계 조사 |
| 적용 상태 | 근거 문서 |
| 다루는 범위 | 정면 2D의 깊이 손실, 단안 추정값의 해석, 시간 처리 |
| 제품 내 역할 | 절대 거리·임상 측정 주장을 제한하고 제품 검증 범위를 정의 |

## 1. 정면 2D만으로 전방 거리를 직접 복원할 수 없다

3D 장면을 2D 이미지로 투영하면 깊이 정보가 소실된다. 같은 2D 위치가 카메라 광선 위 여러 3D 위치에 대응할 수 있으므로, 단일 RGB에서 얻는 3D pose와 depth는 센서 실측값이 아니라 학습된 모델의 추정값이다.

거북목의 핵심 변화인 머리의 전방 이동은 정면 카메라의 깊이축에 가깝다. 따라서 Vision 2D landmark만으로 실제 이동 거리(cm)를 계산하거나 임상 CVA를 복원하지 않는다.

## 2. 단안 depth도 절대 측정값은 아니다

채택한 DA-V2 Small 기본 모델은 affine-invariant inverse depth를 출력한다. 한 이미지 안의 상대 구조를 표현하지만 절대 scale과 shift가 정해지지 않는다. 자세 분석에서는 머리·몸통 ROI의 상대 표현과 개인 baseline을 사용하고, 실제 cm로 변환하지 않는다.

이 상대화도 다음 오류를 자동으로 없애지 못한다.

- 머리카락·옷·배경 경계의 국소 depth 오류
- 가림과 화면 잘림
- 프레임별 ROI 이동
- 조명·노출·초점 변화에 따른 출력 변동

따라서 모델의 일반 장면 벤치마크가 아니라 제품 촬영 조건에서 반복성과 자세 분리도를 측정해야 한다.

## 3. 현재 대응

- PoseNet을 우선 사용하고 필요할 때 Vision 2D로 fallback하며, 선택된 detector의 confidence로 평가 가능한 프레임만 고른다.
- pose anchor로 머리·몸통 ROI를 정하고 견고한 영역 통계를 사용한다.
- 전역 scale·shift에 불변인 relative-depth feature를 검증한다.
- 짧은 버스트의 대표값으로 단일 프레임 변동을 줄인다.
- 안내된 개인 baseline 대비 지속적인 변화만 판정한다.
- 품질이 부족하면 `noEval`로 처리한다.

One-Euro, Kalman, 비디오 depth, 3D pose prior 같은 추가 방식은 가능한 연구 대안이지만 현재 확정 플로우에 포함하지 않는다. 먼저 버스트 대표값만으로 필요한 안정성을 확보하는지 확인한다.

## 4. 적용 경계

- `good`·`bad`는 웰니스 알림 상태이며 의료 진단이 아니다.
- 95%라는 목표를 depth 논문의 δ1과 동일시하지 않는다.
- 제품 성능은 사전에 정의한 자세 라벨, 허용 오경보, 미탐, `noEval` 비율로 별도 평가한다.
- Vision 3D는 RGB에서 실행 가능하지만 dense/measured depth가 아니므로 fallback으로 사용하지 않는다.

## 참고 자료

- 단안 3D pose의 깊이 모호성 서베이: <https://pmc.ncbi.nlm.nih.gov/articles/PMC12031093/>
- Depth Anything V2 논문: <https://arxiv.org/abs/2406.09414>
- 정면 2D가 아닌 측면 landmark 기반 FHP 분류 사례: <https://link.springer.com/article/10.1186/s12911-023-02285-2>
- Apple Vision 3D body pose 설명: <https://developer.apple.com/videos/play/wwdc2023/111241/>
