# Depth Anything V2 — 참고 자료

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | 공식 자료·1차 연구·관련 연구 목록 |
| 적용 상태 | 근거 문서 |
| 다루는 범위 | DA-V2 논문·저장소·Core ML 모델, relative depth 한계, 시간 일관성 |
| 제품 내 역할 | [analysis.md](analysis.md)의 모델·라이선스·정확도 주장을 추적할 출처 제공 |

## 핵심 근거

| 주장 | 근거 수준 | 대표 출처 |
|---|---|---|
| 기본 DA-V2는 affine-invariant relative depth를 출력 | 1차 연구·공식 저장소 | DA-V2 논문·저장소 |
| Small과 대형 변형은 크기와 라이선스 조건이 다름 | 공식 저장소 | Depth Anything V2 LICENSE |
| Apple 배포 DA-V2 Small Core ML 패키지가 존재 | Apple 모델 배포 | Apple Hugging Face 모델 카드 |
| 단일 이미지 depth의 시간 일관성은 별도 문제 | 1차 연구 | Video Depth Anything·StableDPT |

## 공식 문서와 1차 자료

- Depth Anything V2 논문 (NeurIPS 2024, arXiv:2406.09414): <https://arxiv.org/abs/2406.09414> / HTML: <https://arxiv.org/html/2406.09414v1>
- 공식 GitHub (모델 크기·라이선스·Coming soon): <https://github.com/DepthAnything/Depth-Anything-V2>
- Metric depth README (실내 20m / 실외 80m, meters 출력): <https://github.com/DepthAnything/Depth-Anything-V2/blob/main/metric_depth/README.md>
- 프로젝트 페이지: <https://depth-anything-v2.github.io/>
- Hugging Face Metric Indoor Large (Hypersim fine-tune): <https://huggingface.co/depth-anything/Depth-Anything-V2-Metric-Indoor-Large-hf>
- 공식 Core ML 모델 (Apple, Apache-2.0, M-series ANE 약 25~33ms): <https://huggingface.co/apple/coreml-depth-anything-v2-small>
- Hugging Face Core ML 예제 (Swift): <https://github.com/huggingface/coreml-examples/blob/main/depth-anything-example/README.md>
- 커뮤니티 Large Core ML(비공식): <https://huggingface.co/LloydAI/DepthAnything_v2-Large-CoreML>

## 추가·관련 자료
- affine-invariant 출력의 scale·shift 정렬 개념 — Zero-shot Depth Completion (arXiv:2502.06338): <https://arxiv.org/html/2502.06338v1>
- 단일 이미지 depth의 temporal flicker (i.i.d. 가정) — Video Depth Anything (CVPR 2025, arXiv:2501.12375): <https://arxiv.org/abs/2501.12375>
- temporal stability — StableDPT (arXiv:2601.02793): <https://arxiv.org/abs/2601.02793>
- 실내 단안 깊이 공간유형별 편차 — InSpaceType (arXiv:2408.13708): <https://arxiv.org/pdf/2408.13708>
- 단안 depth DNN의 이미지별 affine distortion·depth compression 분석 — Human-like monocular depth biases (PLOS Comput Biol 2025): <https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1013020>
- Hugging Face 강좌(metric vs relative 개념·Depth Anything V2 fine-tuning): <https://huggingface.co/learn/computer-vision-course/en/unit8/monocular_depth_estimation>

## 직접 적용하지 않는 범위

- NYU·KITTI 장면 평균 지표를 근거리 머리-몸통 국소 차이 정확도로 해석하지 않는다.
- relative depth 출력을 절대 cm로 표현하지 않는다.
- DA-V2 출력을 자세 landmark나 최종 `good`·`bad` 판정으로 해석하지 않는다.
