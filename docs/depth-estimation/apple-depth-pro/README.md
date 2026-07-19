# Apple Depth Pro — 미채택 리서치

> 이 문서는 참고용 리서치이며, 현재 확정된 제품 플로우를 직접 정의하거나 구현 기준으로 활용하지 않습니다.

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | metric depth 모델 조사 |
| 적용 상태 | 미채택, 리서치 참고 자료 |
| 입력 | 단일 RGB 이미지 |
| 출력 | metric depth와 focal length 추정 |
| 제품 내 역할 | DA-V2 Small 대신 사용하지 않는 metric 대안의 기록 |

## 제품 적용 판단

Depth Pro는 카메라 intrinsic metadata 없이 absolute-scale depth를 추정하는 Apple 연구 모델이다. 그러나 현재 제품 플로우는 DA-V2 Small로 확정됐고, Depth Pro의 목표 Mac용 공식 Core ML 패키지·성능 자료도 확인되지 않았다. 따라서 제품에 사용하지 않는다.

## 확인된 사실

- 논문은 2.25MP depth map을 표준 GPU에서 0.3초에 생성한다고 보고한다. 이 수치를 Mac 성능으로 해석하지 않는다.
- 공식 GitHub는 code와 model weights를 저장소 LICENSE 조건으로 배포한다고 명시한다.
- Hugging Face `apple/DepthPro` artifact는 별도의 `apple-amlr` 연구용 라이선스를 사용한다.
- 공개 장면 벤치마크는 근거리 상체의 머리-몸통 국소 깊이 차이나 자세 판정 정확도를 직접 검증하지 않는다.

## 문서 구성

| 문서 | 역할 |
|---|---|
| 본 README | 상태·요약·미채택 판단 |
| [analysis.md](analysis.md) | 모델 출력, 실행 조건, 라이선스 경계 |
| [references.md](references.md) | 공식 저장소·논문·라이선스 |
