# Metric depth 모델군 — 로직 분석

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | metric depth 방식 비교 |
| 적용 상태 | 미채택, 리서치 참고 자료 |
| 다루는 범위 | 절대 scale 복원, intrinsic 의존성, 라이선스·배포 경계 |
| 제품 내 역할 | metric 모델을 현재 플로우에 추가하지 않는 근거 설명 |

## 1. 모델별 scale 복원 방식

### ZoeDepth

relative-depth backbone과 metric bins module을 결합해 metric depth를 예측한다. 추론 시 camera intrinsic을 명시적으로 입력하지 않고, 학습 데이터의 실내·실외 scale을 통해 metric 값을 회귀한다. 새로운 카메라와 근거리 상체에서 scale이 얼마나 안정적인지는 별도 검증이 필요하다. 공식 저장소는 2025년 5월부터 보관 상태이며 라이선스는 MIT다.

### Metric3D v2

서로 다른 카메라의 focal length 문제를 canonical camera space로 정규화한다. 예측을 원래 metric scale로 되돌릴 때 focal length가 중요하다고 논문과 공식 저장소가 설명한다. 공식 저장소는 intrinsic이 없을 때 여러 focal length 설정을 쓰는 경로도 제공하지만, 목표 카메라에서 scale이 안정적인지는 별도 검증해야 한다. 공식 저장소 라이선스는 BSD-2-Clause다.

### UniDepth

이미지에서 metric 3D와 camera 정보를 함께 추정해 추론 시 별도 intrinsic 입력을 요구하지 않는다. 저자들은 특정 장면 scale을 포착하지 못하는 사례와 제한된 camera diversity를 한계로 설명한다. 공식 저장소는 CC BY-NC 4.0이며 현재 제품 배포 경로에 맞지 않는다.

## 2. metric 출력이 자세 측정을 보장하지 않는 이유

metric 모델의 일반 장면 평가와 현재 과제는 다르다.

- 일반 벤치마크는 장면 전체 픽셀의 depth 오차를 측정한다.
- 제품은 근거리 인물의 머리 ROI와 몸통 ROI 사이 작은 차이를 사용한다.
- 두 영역의 오차는 상쇄될 수도, 경계·가림에서 커질 수도 있다.
- 자세 판정에는 depth 외에도 ROI 반복성, baseline, 시간 안정성이 필요하다.

따라서 meter 단위 출력이나 높은 δ1만으로 자세 정확도 95%를 주장하지 않는다.

## 3. 현재 결정

metric 모델은 모두 미채택이다. 현재 제품은 Apple Vision 2D로 ROI와 품질을 얻고, Apple 배포 Core ML DA-V2 Small로 relative depth를 생성한다. 이 경로의 제품 데이터 검증이 끝나기 전에 metric 모델, ONNX 런타임, 카메라 calibration을 추가하지 않는다.

재검토가 필요하다면 같은 Mac·같은 이미지·같은 ROI·같은 자세 라벨로 DA-V2 Small 대비 반복성과 분리도 향상을 먼저 비교해야 한다.

## 관련 문서

- 공식 자료: [references.md](references.md)
- 채택 모델: [../depth-anything-v2/README.md](../depth-anything-v2/README.md)
