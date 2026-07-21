# Apple Depth Pro — 로직 분석

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | metric depth 모델 로직 분석 |
| 적용 상태 | 미채택, 리서치 참고 자료 |
| 입력 | 단일 RGB 이미지 |
| 출력 | meter 단위 depth와 추정 focal length |
| 제품 내 역할 | metric depth 대안을 사용하지 않는 근거 설명 |

## 1. 모델이 제공하는 것

Depth Pro는 단일 이미지에서 absolute-scale metric depth를 추정하고, camera intrinsic metadata가 없을 때 focal length도 이미지에서 추정한다. 공식 구현의 출력 예제는 depth를 meter, focal length를 pixel 단위로 설명한다.

이 점은 scale·shift가 정해지지 않은 기본 DA-V2와 다르다. 다만 “metric 출력”은 모델의 모든 픽셀이 실제 거리와 충분히 가깝거나, 자세 분류가 정확하다는 뜻은 아니다.

## 2. 성능 수치의 범위

논문은 2.25MP depth map을 표준 GPU에서 0.3초에 생성한다고 보고한다. 논문 본문의 실험 하드웨어 조건은 NVIDIA V100이다. 따라서 이 수치를 Apple Silicon, Neural Engine 또는 전체 자세 분석 파이프라인의 속도로 전용하지 않는다.

공식 저장소는 재학습한 reference implementation이 논문 모델과 가까운 성능을 보이지만 정확히 일치하지는 않는다고 명시한다. 목표 Mac용 Apple 공식 Core ML 패키지와 지연·메모리·발열 수치는 확인되지 않았다.

## 3. 자세 적용 한계

Depth Pro 논문은 일반 장면의 metric depth와 경계 품질을 평가한다. 현재 필요한 것은 같은 이미지의 머리 ROI와 몸통 ROI 사이 깊이 차이가 반복 자세에서 얼마나 안정적인지다. 이 국소 차이의 오차와 FHP 분류 성능은 공개 자료에서 직접 확인되지 않는다.

따라서 다음 추론은 하지 않는다.

- 일반 장면 δ1·AbsRel → 거북목 판정 정확도
- meter 출력 → 머리 전방 거리의 신뢰 가능한 cm 측정
- V100 속도 → Mac 온디바이스 속도

## 4. 라이선스 경계

공식 GitHub README는 sample code와 model weights가 모두 저장소 LICENSE 조건으로 배포된다고 명시한다. 해당 LICENSE는 Apple Software의 사용·수정·재배포 조건을 규정한다.

Hugging Face의 `apple/DepthPro` artifact는 별도의 Apple Machine Learning Research Model License를 사용하며, research purposes로 제한한다. 같은 이름의 artifact라도 배포 위치와 license text를 구분해야 한다.

이 문서는 법률 판단을 내리지 않는다. 현재 제품은 어느 Depth Pro artifact도 사용하지 않는다.

## 5. 결론

Depth Pro는 metric depth 연구의 유효한 사례지만 현재 제품에 추가하지 않는다. 확정 플로우의 DA-V2 Small을 변경할 근거가 아니며, 자세 판정은 계속 2D body-pose ROI + DA-V2 relative depth + 개인 baseline으로 수행한다.

## 관련 문서

- 공식 자료: [references.md](references.md)
- 현재 채택 모델: [../depth-anything-v2/README.md](../depth-anything-v2/README.md)
