# macOS 단일 RGB 깊이 경로 — 로직 분석

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | Apple 플랫폼 경로 로직 분석·설명 |
| 적용 상태 | Vision 2D body pose는 채택, Core ML은 실행 형식, hardware depth·Vision 3D는 제외 |
| 입력 | Mac 내장 카메라의 단일 RGB 프레임 |
| 출력 | Vision 2D 신체 정보와 Core ML 단안 relative depth |
| 다루는 범위 | 카메라 depth 지원, Vision 분석, Core ML 단안 depth와 통합 경계 |
| 제품 내 역할 | [README.md](README.md)의 플랫폼 경로 판단을 뒷받침하는 기술 상세 |

## 1. 목표 입력에서 하드웨어 depth를 사용하지 않는 이유

목표 자세 feature 후보는 머리와 몸통의 상대적인 전후 차이를 사용한다. Apple의 measured-depth 캡처는 호환 장치와 지원 depth format을 요구하지만, 제품 입력 계약은 별도 depth 장치를 전제하지 않는 Mac 내장 RGB 카메라다. 따라서 제품은 Apple 하드웨어 depth 경로를 사용하지 않는다.

### 1-1. `AVCaptureDepthDataOutput` — 목표 카메라에서 사용 불가

- Apple 정의: "A capture output that records scene depth information on compatible camera devices." 즉 깊이 출력은 호환 카메라 기기가 있어야 동작한다.
- 가용성(Apple 공식): iOS 11.0+, iPadOS, Mac Catalyst 14.0+, tvOS 17.0+ — 네이티브 macOS는 가용 플랫폼에 없다. 즉 Catalyst가 아닌 일반 macOS 앱에서는 장치 호환성 이전에 이 출력 클래스 자체가 제공되지 않는다.
- Apple 문서가 요구하는 핵심 조건은 compatible camera device와 해당 format의 `supportedDepthDataFormats`다. 목표 제품의 입력 계약은 Mac 내장 RGB 카메라이며 호환 depth format을 전제하지 않으므로 이 경로를 사용하지 않는다. 이 판단은 별도 외장 depth 장치나 vendor API의 가능성까지 부정하는 결론은 아니다.

### 1-2. `AVDepthData` 컨테이너는 macOS에 있으나 — "측정"이 아니라 "컨테이너"일 뿐

혼동 주의: `AVDepthData`(깊이 데이터 컨테이너 클래스)는 macOS 10.13+에도 존재한다. 그러나 이는 깊이를 만드는 게 아니라 담는 그릇이다.

- Apple 정의: "A container for per-pixel distance or disparity information captured by compatible camera devices."
- macOS의 `AVDepthData`는 depth가 포함된 미디어나 별도 depth source에서 읽거나 구성할 수 있다. 클래스가 macOS에 있다는 사실만으로 목표 RGB 입력이 measured depth를 제공한다고 볼 수 없다.

### 1-3. `builtInTrueDepthCamera` — macOS 미지원, iPhone·iPad TrueDepth 경로

- Apple은 `builtInTrueDepthCamera`를 infrared camera와 YUV camera로 구성된 장치로 정의한다. 이 경로는 iPhone·iPad의 TrueDepth 카메라용이다.
- 플랫폼 가용성(Apple 공식): iOS 11.1 / iPadOS 11.1 / Mac Catalyst 14.0 / tvOS 17.0 → 네이티브 macOS 없음.
- 목표 입력은 `builtInTrueDepthCamera`로 선택하는 iPhone·iPad TrueDepth 캡처 경로가 아니다.

### 1-4. ARKit / RoomPlan — 목표 Mac RGB 경로가 아님

- ARKit 플랫폼 가용성(Apple 공식): iOS 11.0 / iPadOS 11.0 / Mac Catalyst 14.0 / visionOS 1.0 → 네이티브 macOS 없음. ARKit 전체가 항상 LiDAR를 요구하는 것은 아니지만, 목표 Mac 내장 RGB 캡처의 depth API는 아니다.
- RoomPlan과 LiDAR 기반 scene reconstruction은 지원 센서가 있는 iPhone·iPad 경로다. 목표 입력과 무관하다.

목표 제품 계약은 Apple 네이티브 하드웨어 깊이 경로(`AVCaptureDepthDataOutput`, TrueDepth, 듀얼카메라, LiDAR/ARKit)를 사용하지 않는다. 단일 RGB 입력의 깊이는 측정이 아니라 모델로 추정한다.

### 1-5. `VNDetectHumanBodyPose3DRequest` — 실행 가능하지만 depth 대체 불가

- macOS 14+에서 RGB 이미지로 17-joint 3D skeleton을 추정할 수 있다.
- 결과는 hip-rooted skeleton이고 관절별 confidence가 없으며, DA-V2 같은 조밀한 pixel depth map이 아니다.
- Apple은 호환 `AVDepthData`가 있으면 정확도와 scale을 보강할 수 있다고 설명한다. 목표 Mac 내장 카메라에는 이 입력이 없다.
- 호환 depth가 없으면 `bodyHeight`는 measured height가 아니라 WWDC23이 설명한 기준 신장 1.8m에 기반한다.

따라서 Vision 3D는 “기술적으로 실행 불가”가 아니라 이 제품의 머리-몸통 깊이 판정 근거로 사용할 수 없어 제외하는 경로다.

## 2. Apple Vision 2D 분석 API — 깊이는 못 주지만 영역 분리 보조

Vision의 사람 분석 API는 깊이를 추정하지 않는다. 확정 흐름에서는 body pose landmark로 depth map에서 비교할 머리·몸통 ROI와 품질 조건을 정한다.

| Vision 요청 | 산출물 | macOS 가용 | 거북목 활용 |
|---|---|---|---|
| `VNGeneratePersonSegmentationRequest` | 프레임의 모든 사람을 합친 단일 semantic matte | macOS 12.0+ | 미채택 보조 후보 |
| `VNGeneratePersonInstanceMaskRequest` | 개인별 instance mask | macOS 14.0+ | 미채택 보조 후보 |
| `VNGenerateForegroundInstanceMaskRequest` | 두드러진 전경 객체 instance mask | macOS 14.0+ | 미채택 보조 후보 |
| `VNDetectHumanBodyPoseRequest` | 2D 관절 keypoint + confidence | iOS 14 / macOS 11+ | 머리·목·어깨 ROI anchor |

(위 가용성은 모두 Apple 공식 문서로 확인.)

한계 명시: 이들 마스크는 2D 픽셀 영역일 뿐 z 값이 없다. Person/instance mask는 사람 전체를 분리할 뿐 머리·몸통 부위를 나누지 않는다. 현재 확정 흐름에는 추가하지 않고 Vision 2D body landmark만으로 ROI를 만든다. 깊이 값은 절 3의 Core ML 모델이 제공한다.

## 3. Depth Anything V2 + Core ML — 목표 설계의 정면 depth 경로

단일 RGB에서 깊이를 얻으려면 학습된 단안 깊이 추정(monocular depth estimation) 모델을 실행해야 한다. 목표 모델은 Depth Anything V2 Small이고, Core ML은 이를 macOS에서 실행·배포하는 형식이다.

### 3-1. Core ML 실행 경로

- Apple은 DA-V2 Small의 `.mlpackage`와 Swift 예제를 제공한다. 따라서 별도 PyTorch·ONNX 런타임 없이 Core ML로 실행할 수 있다.
- `VNCoreMLRequest`는 Core ML 모델을 Vision 이미지 요청으로 실행할 수 있는 API다. 다만 실제 observation 유형은 모델의 출력 feature type에 따라 달라지므로 특정 결과 타입을 문서에서 고정하지 않는다.
- 실제 compute unit 선택과 fallback은 대상 기기에서 확인해야 한다.

### 3-2. Apple 공식 제공 모델: Depth Anything V2 Small (Core ML)

Apple이 Hugging Face `apple/` 조직에서 직접 Core ML 변환본을 배포한다(2024-06-25 Apple Core ML Models 라이브러리 편입).

- 모델: `apple/coreml-depth-anything-v2-small` (`.mlpackage`)
- 번들 크기: F16 = 49.8 MB, F32 = 99.2 MB. 제품 번들 예산에 수용 가능한지는 배포 정책으로 결정한다.
- 온디바이스 성능(Apple 측정): F16 모델이 MacBook Pro M1 Max에서 32.80ms, M3 Max에서 24.58ms였고 dominant compute unit은 Neural Engine이었다. 이 수치는 해당 기기·OS의 단일 모델 벤치이며 전체 pose+depth 파이프라인 지연을 뜻하지 않는다.
- 평가 입력: Apple 모델 카드는 4:3에 가까운 COCO 이미지 512장을 518×396으로 늘려 PyTorch F32 출력과의 변환 오차를 평가했다. 이는 근거리 상반신 자세 feature에 해상도가 충분하다는 검증이 아니다.
- 아키텍처: DPT + DINOv2 백본.
- 변환 도구: Apple `coremltools`로 변환·압축(Apple ML이 공식 지원).

이는 별도 변환 없이 평가할 수 있는 Apple 배포 Core ML 자산이다. 근거리 상반신 적합성은 별도 제품 검증 항목이다. 상세 검토는 [Depth Anything V2 문서](../depth-anything-v2/README.md)를 참조한다.

### 3-3. 출력 해석 — 상대 깊이이며 절대 거리가 아님

거북목 판정에 직결되는 한계다.

- Depth Anything V2는 affine-invariant inverse depth(=상대 깊이) 를 출력한다. 조밀한 상대 구조를 제공하지만 scale·shift가 정해지지 않는다.
- 즉 모델은 "머리가 몸통보다 N cm 앞" 같은 metric 값을 주지 않는다. 한 이미지 안의 머리·몸통 상대값을 견고하게 집계하고 전역 affine 성분을 정규화해야 한다.
- metric으로 바꾸려면 외부 기준과의 scale/shift 정합이 필요하다. 목표 웹캠 경로에는 그 기준이 없으므로 절대 전방 차이(cm)로 해석하지 않는다.

### 3-4. 더 무거운 대안: Apple Depth Pro — 미채택

- `apple/ml-depth-pro`: zero-shot metric 단안 깊이(절대 스케일·카메라 메타데이터 불요).
- 논문은 2.25MP 깊이맵을 표준 GPU에서 0.3초에 생성한다고 보고한다. Apple 제공 Core ML 변환본은 확인되지 않았다.
- Hugging Face `apple/DepthPro` 체크포인트는 `apple-amlr`로 Research Purposes 전용이다. 반면 공식 GitHub 다운로드 스크립트는 Apple CDN checkpoint에 저장소의 동봉 LICENSE를 안내하며, 저장소 LICENSE는 Apple Software의 사용·수정·재배포를 허용한다.
- 공식 GitHub README는 저장소가 내려받는 model weights도 저장소 LICENSE 조건으로 배포한다고 명시한다. 반면 Hugging Face `apple/DepthPro` artifact는 `apple-amlr` 연구용 조건이다. 어느 경로도 현재 제품 플로우에는 사용하지 않는다.

## 4. 경로별 macOS 가용성·성능·번들 함의 요약

| 경로 | macOS 네이티브 | 깊이 종류 | 번들 | 온디바이스 | turtlemeck 적합성 |
|---|---|---|---|---|---|
| `AVCaptureDepthDataOutput` (HW) | 네이티브 macOS 미지원 | metric | 0 | 해당 없음 | 지원 플랫폼도 호환 장치·format 필요 |
| TrueDepth / 듀얼 / LiDAR / ARKit | 목표 네이티브 Mac RGB 경로 아님 | metric 또는 공간 추적 | 0 | 해당 없음 | 플랫폼·센서 조건 불일치 |
| Vision 3D body pose | macOS 14+ | 17-joint skeleton 추정 | 0(내장) | 온디바이스 | dense/measured depth가 아니므로 판정 제외 |
| Vision Person Segmentation/InstanceMask | 12/14+ | 깊이 없음(2D 마스크) | 0(내장) | 별도 검증 필요 | 현재 미채택 |
| Depth Anything V2 Small / Core ML | VNCoreMLRequest로 실행 | 상대(affine-invariant) | 49.8 MB F16 | M1 Max 32.80ms / M3 Max 24.58ms, 모델 단독 | 목표 정면 depth |
| Depth Pro 변환 | 이론상 가능·공식 변환본 없음 | metric | 별도 모델 | 0.3s는 논문 GPU 조건, Mac 미검증 | 미채택·리서치 참고 |

## 5. turtlemeck 적용 범위

1. 목표 제품 경로. Mac 단일 RGB에서 하드웨어 깊이를 전제하지 않고, Depth Anything V2 Small을 정면 depth estimator로 사용한다. Core ML은 실행 형식이다. Vision 2D body pose가 신체 관절·정면 ROI와 품질 정보를 제공하고, 프로젝트 자세 분석기가 최종 판정한다. Vision 3D는 제외한다.

2. Vision segmentation은 깊이 제공자나 신체 부위 분류기가 아니다. 현재 흐름에는 넣지 않는다. body pose landmark가 머리·몸통 ROI를 정의하고 영역 depth는 median 같은 견고한 통계로 집계한다.

3. 제품 데이터 검증 전에는 단일 정면 웹캠과 상대 깊이만으로 95% 정확도를 주장하지 않는다. 근거는 다음과 같다.
   - Core ML depth 출력은 상대(scale/shift 미지) 깊이라 절대 전방 차이(cm)를 제공하지 못한다(3-3).
   - 일부 단안 3D pose 연구에서 depth축 오류가 in-plane보다 크게 보고됐지만, 그 배율을 turtlemeck의 Core ML depth ROI 오류에 그대로 적용할 수 없다.
   - 정면 단독 FHP 정량화는 검증된 고정확 선례가 없고 표준화된 측면 CVA를 대체하지 못한다([단안 한계](../../algorithm/pose-estimation/related-monocular-limits.md)).
   - 결론: "단일 정면 웹캠 + AI로 거북목을 95% 정확도로 측정"은 현재 근거로 뒷받침되지 않는다. 목표는 개인 baseline 대비 상대 악화 탐지다. 실제 분류 성능은 사전 정의한 라벨과 coverage를 포함해 측정한다.

4. 확정 통합 흐름. ① DA-V2 Small로 inverse-depth map 산출 ② 2D body pose anchor로 head/torso와 reference ROI 정의 ③ affine-invariant 상대 feature 검증 ④ 개인 baseline·버스트 품질·지속성 적용 ⑤ 절대 cm가 아닌 지속적인 상대 변화만 판정. 후보 식은 [relative depth feature 설계](../etc/related-feature-design.md) 한 곳에서 관리하고, 최종 식과 임계는 제품 데이터로 검증한다.

## 관련 문서

- 공식·관련 자료: [references.md](references.md)
- Apple Vision 자세 입력: [../../algorithm/apple-body-pose/README.md](../../algorithm/apple-body-pose/README.md)
- relative depth feature 설계: [../etc/related-feature-design.md](../etc/related-feature-design.md)
