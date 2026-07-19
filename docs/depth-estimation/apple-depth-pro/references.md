# Apple Depth Pro — 참고 자료

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 공식 자료·1차 연구 목록 |
| 적용 상태 | 근거 문서 |
| 제품 내 역할 | [analysis.md](analysis.md)의 출력·성능·라이선스 주장 추적 |

## 핵심 근거

| 주장 | 근거 수준 | 대표 출처 |
|---|---|---|
| metric depth와 focal length를 단일 이미지에서 추정 | 1차 연구·공식 자료 | Depth Pro 논문·공식 저장소 |
| 2.25MP, 0.3초는 논문 조건이며 Mac 수치가 아님 | 1차 연구 | Depth Pro 논문 |
| GitHub code와 weights는 저장소 LICENSE 조건 | 공식 배포 자료 | 공식 저장소 README·LICENSE |
| Hugging Face artifact는 research-only | 공식 배포 라이선스 | Hugging Face LICENSE |

## 공식 문서와 1차 자료

- 논문: <https://arxiv.org/abs/2410.02073>
- 공식 GitHub: <https://github.com/apple/ml-depth-pro>
- GitHub LICENSE: <https://github.com/apple/ml-depth-pro/blob/main/LICENSE>
- GitHub checkpoint 다운로드 스크립트: <https://github.com/apple/ml-depth-pro/blob/main/get_pretrained_models.sh>
- Hugging Face `apple/DepthPro`: <https://huggingface.co/apple/DepthPro>
- Hugging Face LICENSE: <https://huggingface.co/apple/DepthPro/blob/main/LICENSE>

## 추가·관련 자료

- 현재 채택 모델: [../depth-anything-v2/README.md](../depth-anything-v2/README.md)
- metric depth 대안: [../metric-depth-models/README.md](../metric-depth-models/README.md)
- 확정 워크플로우: [../../algorithm/posture-analysis-workflow.md](../../algorithm/posture-analysis-workflow.md)

## 직접 적용하지 않는 범위

- V100 속도를 Mac Core ML 성능으로 전용하지 않는다.
- 장면 depth 지표를 머리-몸통 국소 차이 또는 자세 판정 정확도로 해석하지 않는다.
- 배포 위치가 다른 checkpoint의 라이선스를 하나로 합쳐 설명하지 않는다.
