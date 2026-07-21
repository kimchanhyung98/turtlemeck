# 리뷰: 깊이 추정 리서치 인덱스 (docs/depth-estimation/README.md)

- 리뷰 일자: 2026-07-21
- 대상 문서: `docs/depth-estimation/README.md`
- 종합 판정: 문제 없음

## 요약

문서의 사실 주장을 원출처(모델 카드, 논문, Apple 문서)와 실제 코드로 대조한 결과 수정이 필요한 오류는 발견되지 않았다. "공식 자료로 확인한 사실"의 수치·라이선스·API 가용성 서술이 모두 원출처와 일치하고, 기술별 적용 상태 표는 7개 하위 문서의 자체 상태와 일치한다. 요약 플로우는 규범 문서(`docs/algorithm/posture-analysis-workflow.md`) 및 실제 코드와 정합한다. 상태 라벨 표현에 관한 참고 사항 1건만 기록한다.

## 확인된 사항

| 문서 주장 | 확인 결과 | 근거 |
|---|---|---|
| Apple Core ML 모델 카드 기준 DA-V2 Small F16은 24.8M parameters, 49.8MB | 일치 | <https://huggingface.co/apple/coreml-depth-anything-v2-small> 모델 카드 변형 표 (DepthAnythingV2SmallF16 = 24.8M params, 49.8MB) |
| M1 Max 32.80ms, M3 Max 24.58ms — "모델 단독·해당 기기의 수치" | 일치 | 같은 모델 카드 벤치마크 표 (M1 Max/macOS 15.0: 32.80ms, M3 Max/macOS 15.0: 24.58ms, Neural Engine 지배적 연산 장치) |
| Small은 Apache-2.0, Base/Large/Giant는 CC-BY-NC-4.0 | 일치 | <https://github.com/DepthAnything/Depth-Anything-V2> README 라이선스 절 |
| 핵심 자료의 논문 링크가 DA-V2 논문 | 일치 | <https://arxiv.org/abs/2406.09414> (Lihe Yang 외, Depth Anything V2) |
| DA-V2 기본 모델은 affine-invariant inverse depth 출력, metric 출력은 별도 checkpoint | 일치 | 논문 §5.2 "our models produce affine-invariant inverse depth", §7.3 metric fine-tuning; GitHub 저장소의 별도 metric_depth 모델 |
| `AVCaptureDepthDataOutput`은 네이티브 macOS 가용 API가 아니고 `AVDepthData` 컨테이너는 macOS에도 존재 | 일치 | Apple 문서 platforms: AVCaptureDepthDataOutput은 iOS 11+/iPadOS 11+/Mac Catalyst 14+/tvOS 17+만 표기, AVDepthData는 macOS 10.13+ |
| Vision 3D는 RGB에서 실행 가능하나 dense/measured depth가 아니어서 제외 | 일치 | <https://developer.apple.com/videos/play/wwdc2023/111241/> (Explore 3D body pose and person segmentation in Vision) |
| 요약 플로우의 PoseNet 우선·Vision fallback | 코드와 일치 | `Sources/TurtleCore/Camera/PoseDetector.swift:17-21` (PoseNet 후보가 유효 상체를 못 만들 때만 Vision fallback) |
| 최종 판정 `good`·`bad`·`noEval` | 코드와 일치 | `Sources/TurtleCore/Detection/Models.swift:3-7` (PostureAssessment) |
| Apple 배포 Core ML Small 모델로 relative depth 생성 (채택) | 코드·번들과 일치 | `Resources/DepthAnythingV2SmallF16.mlpackage`; `Sources/TurtleCore/Camera/CoreMLRelativeDepthProvider.swift` (기본 모델명 `DepthAnythingV2SmallF16`) |
| 기술별 적용 상태 표 7개 항목 | 하위 문서 자체 상태와 일치 | `depth-anything-v2/README.md:8`, `apple-depth-pro/README.md:11`, `metric-depth-models/README.md:10`, `etc/related-feature-design.md:8`, `etc/related-posture-feasibility.md:8`, `etc/related-temporal-video-depth.md:8` |
| Vision 3D·하드웨어 depth·Depth Pro·metric·video depth 미사용 | 규범 문서와 일치 | `docs/algorithm/posture-analysis-workflow.md:339-348`, `docs/workflow.md:166-173` |
| 적용 상태 용어 사용 | 문서 규칙의 용어 표 정의 값만 사용 | `docs/algorithm/README.md:84-92` |
| 핵심 자료 절의 외부 URL 5개 | 전부 접속 가능, 내용 일치 | `docs/depth-estimation/README.md:78-82` |

## 발견된 문제

### 수정 필요 (major)

없음.

### 권장 (minor)

없음.

## 참고 (info)

- 파일: `docs/depth-estimation/README.md:42`
- 문서 서술: `| [apple-vision-depth/](apple-vision-depth/README.md) | 근거 문서 | Vision 2D는 pose fallback, Core ML은 모델 실행 형식, measured depth·Vision 3D 제외 |`
- 내용: 상태 열의 문서 단위 라벨 "근거 문서"는 용어 정의상 "런타임 로직이 아니라 채택 범위·한계·용어를 뒷받침"(`docs/algorithm/README.md:91`)인데, 해당 하위 문서가 다루는 Vision 2D fallback은 실제 런타임 채택 경로다. 하위 문서 자체의 적용 상태도 "근거 문서"가 아니라 기술별 상태(fallback/실행 형식/제외)로 적혀 있어(`docs/depth-estimation/apple-vision-depth/README.md:8`) 두 문서의 상태 표기가 문자 그대로는 일치하지 않는다. 결론 열이 기술별 상태를 나눠 적고 있어 실질적 오해 위험은 낮다.

## 결론

`docs/depth-estimation/README.md`는 수치·라이선스·API 가용성·적용 상태·요약 플로우가 모두 원출처 및 코드와 일치하는 정확한 인덱스 문서다. 수정이 필요한 사실 오류는 없으며, apple-vision-depth 행의 상태 라벨 표기만 참고 사항으로 남긴다.
