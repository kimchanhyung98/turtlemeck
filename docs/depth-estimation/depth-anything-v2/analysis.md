# Depth Anything V2 — 로직 분석

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 단안 depth 모델 로직 분석 |
| 적용 상태 | DA-V2 Small 채택, 자세 feature는 제품 실측 필요 |
| 입력 | 단일 RGB 이미지 |
| 출력 | affine-invariant inverse-depth map |
| 제품 내 역할 | 정면 relative-depth 생성 모델의 원리·배포 조건·해석 경계 설명 |

## 1. 모델 개요

Depth Anything V2는 DPT 구조와 DINOv2 backbone을 사용하는 단안 깊이 추정 모델이다. 논문은 대형 teacher model을 합성 이미지로 학습하고, 약 6,200만 장의 레이블이 없는 실제 이미지에 pseudo depth를 만든 뒤 student model을 학습하는 절차를 설명한다.

공식 저장소가 안내하는 relative-depth 모델은 다음과 같다.

| 변형 | 파라미터 | 라이선스 |
|---|---:|---|
| Small | 24.8M | Apache-2.0 |
| Base | 97.5M | CC-BY-NC-4.0 |
| Large | 335.3M | CC-BY-NC-4.0 |
| Giant | 1.3B, 저장소 표기상 미공개 | CC-BY-NC-4.0 |

현재 제품은 Small만 사용한다.

## 2. relative와 metric의 구분

### 기본 모델

논문은 기본 모델의 출력을 affine-invariant inverse depth라고 설명한다. 예측값은 전역 scale과 shift가 정해지지 않은 동치류로 다뤄야 한다.

- 같은 이미지 안에서 가까운 영역과 먼 영역의 상대 구조를 비교할 수 있다.
- raw 숫자를 meter나 cm로 해석할 수 없다.
- raw 차이도 프레임마다 그대로 비교할 수 없다.
- ground-truth 또는 별도 기준 없이 합리적인 metric point cloud를 복원할 수 없다.

“순서만 제공한다”는 표현도 지나치게 축약될 수 있다. 모델은 조밀한 상대 구조를 출력하지만, 그 구조에 절대 scale·offset이 없다는 것이 정확한 한계다.

### 별도 metric 모델

공식 저장소는 Hypersim으로 fine-tune한 실내용 모델과 Virtual KITTI 2로 fine-tune한 실외용 모델을 제공한다. 예제 코드는 각각 최대 깊이 20m와 80m를 사용하며 출력 단위를 meter로 설명한다.

이 metric checkpoint는 Apple의 `coreml-depth-anything-v2-small` 패키지와 다른 모델이다. 현재 제품 플로우에는 사용하지 않는다.

## 3. Apple Core ML 패키지

Apple의 모델 카드가 제공하는 `DepthAnythingV2SmallF16.mlpackage`는 기본 relative-depth Small 모델의 Core ML 변환본이다.

| 항목 | Apple 모델 카드 값 |
|---|---:|
| Parameters | 24.8M |
| F16 크기 | 49.8MB |
| M1 Max | 32.80ms |
| M3 Max | 24.58ms |
| 주요 compute unit | Neural Engine |

속도는 해당 기기·OS에서 모델 하나만 측정한 값이다. Vision 요청, ROI 처리, 버스트 집계와 앱 전체 지연을 뜻하지 않는다. 모델 카드의 변환 오차 평가도 PyTorch F32 출력과 Core ML 출력의 일치도를 본 것이며, 자세 판정 정확도 평가가 아니다.

## 4. 자세 분석에서의 사용

DA-V2에는 신체 관절과 자세 상태의 개념이 없다. 처리 순서는 다음과 같다.

1. Vision 2D가 머리·목·어깨 landmark와 confidence를 제공한다.
2. 같은 이미지에서 DA-V2가 relative inverse-depth map을 만든다.
3. 자세 분석기가 landmark로 머리·몸통 ROI를 정의한다.
4. ROI의 median과 landmark 기반 reference ROI의 IQR 같은 견고한 통계로 전역 affine 변화에 불변인 후보 feature를 만든다.
5. 버스트 대표값을 안내된 개인 baseline과 비교한다.
6. 품질이 부족하면 `noEval`, 악화가 지속되면 `bad`로 처리한다.

후보 feature의 정확한 정의는 중복을 피하기 위해 [relative depth feature 설계](../etc/related-feature-design.md) 한 곳에서 관리한다. 전역 affine 불변성은 수학적으로 확인할 수 있지만, 자세 분리 성능은 모델 논문이 보장하지 않는다. 국소 왜곡·ROI 경계·가림은 제품 데이터로 검증해야 한다.

## 5. 공개 지표의 적용 한계

DA-V2 논문의 δ1·AbsRel은 NYU, KITTI 같은 장면 depth 데이터셋의 지표다. 다음을 직접 의미하지 않는다.

- 책상 거리 인물의 머리-몸통 깊이 차이 오차
- 거북목 분류 accuracy
- 개인 baseline 대비 변화의 반복성
- 전체 Mac 앱의 실시간 성능

따라서 일반 장면의 δ1이 0.95를 넘는다는 이유로 제품 정확도 95%를 주장하지 않는다.

## 6. 결론

DA-V2 Small은 정면 relative depth 생성기로 채택한다. 절대 cm나 자세 판정 모델로 사용하지 않는다. 채택 여부는 끝났고, 남은 일은 Vision ROI와 상대 feature가 실제 제품 데이터에서 반복성과 분리도를 확보하는지 검증하는 것이다.

## 관련 문서

- 공식·관련 자료: [references.md](references.md)
- feature 설계: [../etc/related-feature-design.md](../etc/related-feature-design.md)
- 확정 플로우: [../../algorithm/posture-analysis-workflow.md](../../algorithm/posture-analysis-workflow.md)
