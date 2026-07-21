# 리뷰: Apple Depth Pro 리서치 (docs/depth-estimation/apple-depth-pro/)

- 리뷰 일자: 2026-07-21
- 대상 문서: [README.md](README.md), [analysis.md](analysis.md), [references.md](references.md)
- 종합 판정: 경미한 수정 권장

## 요약

Apple Depth Pro 문서군의 사실 정확도는 매우 높다. 논문 스펙(metric depth·focal length 추정, 2.25MP 0.3초, V100), GitHub·Hugging Face의 이원화된 라이선스 구조, 재학습 reference implementation 고지가 모두 1차 출처와 정확히 일치했고, references.md의 외부 URL 6개는 전부 접속·내용 확인에 성공했다. 미채택 상태도 규범 문서와 코드 실상태에 부합한다. 남은 지적은 공통 문서 형식 대비 README 섹션 구성의 경미한 편차뿐이며, major 사실 오류는 없다.

## 확인된 사항

| 문서 주장 | 확인 결과 | 근거 |
|---|---|---|
| metadata(camera intrinsics) 없이 단일 이미지에서 absolute-scale metric depth 추정 | 일치 | <https://arxiv.org/abs/2410.02073> abstract: "The predictions are metric, with absolute scale, without relying on the availability of metadata such as camera intrinsics." |
| 단일 이미지에서 focal length 추정 | 일치 | 같은 abstract: "state-of-the-art focal length estimation from a single image" (공식 GitHub README 동일) |
| 2.25MP depth map을 표준 GPU에서 0.3초에 생성 | 일치 | 같은 abstract: "producing a 2.25-megapixel depth map in 0.3 seconds on a standard GPU" |
| 논문 본문의 속도 측정 하드웨어는 NVIDIA V100 (analysis.md 2절) | 일치 | <https://arxiv.org/html/2410.02073v2>: "...at 2.25-megapixel native resolution in 0.3 seconds on a V100 GPU" |
| GitHub는 sample code·model weights를 저장소 LICENSE 조건으로 배포 | 일치 | <https://github.com/apple/ml-depth-pro> README: "This sample code is released under the LICENSE terms. The model weights are released under the LICENSE terms." |
| GitHub LICENSE는 사용·수정·재배포 조건을 규정하는 Apple 자체 라이선스 | 일치 | <https://github.com/apple/ml-depth-pro/blob/main/LICENSE>: "...to use, reproduce, modify and redistribute the Apple Software..." |
| 재학습 reference implementation은 논문 성능에 가깝지만 정확히 일치하지 않음 | 일치 | 공식 README: "Its performance is close to the model reported in the paper but does not match it exactly." |
| Hugging Face `apple/DepthPro`는 `apple-amlr` 연구용 라이선스(상업적 이용·제품 개발 금지) | 일치 | <https://huggingface.co/apple/DepthPro> license 태그, <https://huggingface.co/apple/DepthPro/blob/main/LICENSE>: "exclusively for Research Purposes... does not include any commercial exploitation, product development..." |
| checkpoint 다운로드 스크립트 실재 | 일치 | <https://github.com/apple/ml-depth-pro/blob/main/get_pretrained_models.sh> (ml-site.cdn-apple.com에서 depth_pro.pt 다운로드) |
| 출력 예제는 depth를 meter, focal length를 pixel 단위로 설명 (analysis.md 1절) | 일치 | 공식 README 코드 주석: "Depth in [m]." / "Focal length in pixels." |
| 목표 Mac용 Apple 공식 Core ML 패키지 미확인 | 일치 | Apple 공식 컬렉션 <https://huggingface.co/collections/apple/depthpro-models> 에 apple/DepthPro, DepthPro-hf, DepthPro-mixin만 있고 `.mlpackage` 배포 없음 |
| 제품은 Depth Pro artifact를 사용하지 않으며 depth는 DA-V2 Small로 수행 (analysis.md 5절) | 일치 | `Sources/TurtleCore/Camera/CoreMLRelativeDepthProvider.swift:16` (modelName `DepthAnythingV2SmallF16`), `Sources/TurtleCore/Camera/CameraManager.swift:19,403`; Sources/ 전체에 Depth Pro 참조 없음 |
| 미채택 상태가 규범 문서와 일치 | 일치 | `docs/algorithm/posture-analysis-workflow.md:342` "13. 현재 사용하지 않는 것"에 Depth Pro 명시, `docs/depth-estimation/README.md` 적용 상태 표 |
| references.md 내부 링크 3개 유효 | 일치 | `../depth-anything-v2/README.md`, `../metric-depth-models/README.md`, `../../algorithm/posture-analysis-workflow.md` 모두 실재 |

references.md의 외부 URL 6개는 전부 접속·내용 확인에 성공했다.

## 발견된 문제

### 수정 필요 (major)

없음.

### 권장 (minor)

- 파일: [README.md](README.md)
  - 문서 서술: 섹션 구성이 문서 요약 → 제품 적용 판단 → 확인된 사실 → 문서 구성.
  - 문제: `docs/algorithm/README.md` "공통 문서 형식"(49~57행)이 README.md 필수 구성으로 정의한 5개 항목 중 "2. 요약 플로우(입력→처리→출력)"가 없고, "4. 한계와 검증 상태" 대신 "확인된 사실" 제목을 사용한다. 채택 문서인 `depth-anything-v2/README.md`, `apple-vision-depth/README.md`는 "요약 다이어그램"·"한계와 검증 상태"를 갖추고 있어 형식이 갈린다.
  - 근거: `docs/algorithm/README.md` 49~57행 vs 본 README 전체. 다만 미채택 문서인 `metric-depth-models/README.md`도 같은 축약 형식이므로 미채택 문서군의 일관된 관행으로 보이나, 규칙상 미채택 문서에 대한 명시적 예외는 없다.

## 참고 (info)

- [analysis.md](analysis.md): 섹션 구성(모델이 제공하는 것 → 성능 수치의 범위 → 자세 적용 한계 → 라이선스 경계 → 결론)이 `docs/algorithm/README.md` 59~66행이 정의한 analysis.md 구성과 순서·항목이 다르고, 특히 "처리 단계별 로직 분석"(아키텍처·추론 단계)이 없다. 미채택 근거 설명에 집중한 구성이라 내용상 합리적이고 `metric-depth-models/analysis.md`도 같은 방식이지만, 규칙상 예외로 명시돼 있지는 않다.
- [README.md](README.md) "목표 Mac용 공식 Core ML 패키지·성능 자료도 확인되지 않았다"는 주장 자체는 정확하다. 다만 서드파티 변환인 `coreml-projects/DepthPro-coreml`의 `DepthPro.mlpackage`(약 1.9GB, 1536×1536, meter 단위)가 실재하므로, "Core ML 실행 경로 자체가 없다"로 오독되지 않게 비공식 변환의 존재와 크기·라이선스 미검증을 한 줄 병기하면 근거가 더 완결된다. 수정 필수 사항은 아니다.

## 결론

세 문서 모두 논문·공식 저장소·배포 라이선스라는 1차 출처와 사실 관계가 정확히 일치하고, 미채택 판단도 규범 문서·코드 실상태와 부합한다. 사실 오류는 없으며, 공통 문서 형식 대비 README 섹션 구성의 경미한 편차만 정리하면 된다.
