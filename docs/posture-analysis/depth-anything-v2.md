# Depth Anything V2 Small

## 채택 상태

목바로는 Apple이 배포한 Depth Anything V2 Small의 Core ML 변환본을 상대 깊이 생성 모델로 사용한다.
이 모델은 한 RGB 이미지 안의 픽셀별 상대적인 앞뒤 구조를 제공하며 자세, 신체 부위, 실제 거리를 직접 출력하지 않는다.

## 모델과 라이선스

| 항목 | 현재 계약 |
|---|---|
| 모델 리소스 | `Resources/DepthAnythingV2SmallF16.mlpackage` |
| 출처 | [Apple `coreml-depth-anything-v2-small`](https://huggingface.co/apple/coreml-depth-anything-v2-small) |
| 변형 | Depth Anything V2 Small F16 |
| 라이선스 | Apache-2.0 |
| 실행 위치 | 기기 내부 Core ML·Vision, 사용 가능한 모든 compute unit |

라이선스와 배포 출처는 [ThirdPartyNotices.md](../../Resources/ThirdPartyNotices.md)와 [Apache-2.0.txt](../../Resources/Apache-2.0.txt)에서 관리한다.
패키징 시 `coremlcompiler`를 사용할 수 있으면 모델을 컴파일하고, 사용할 수 없으면 원본 패키지를 앱에 포함해 실행 시 로드한다.

## 런타임 계약

1. PoseNet과 같은 RGB 프레임을 `VNCoreMLRequest`에 전달하고 입력을 `scaleFill`로 맞춘다.
2. 모델 출력을 단일 채널 pixel buffer 또는 `MLMultiArray`에서 읽는다.
3. 출력값과 명시된 near/far 방향을 가진 `RelativeDepthMap`으로 변환한다.
4. 머리·몸통 ROI의 중앙값 차이를 프레임 reference ROI의 IQR로 정규화한다.
5. 정규화한 프레임 특성값을 버스트 중앙값·MAD와 개인 기준 자세 비교에 사용한다.

기본 방향은 값이 클수록 가까운 `largerIsNear`다.
디버그 PNG는 한 프레임의 최솟값과 최댓값으로 정규화한 시각화이며 원시 출력이나 실제 거리 데이터가 아니다.

## 제품 경계와 실패 처리

- 출력은 cm 단위 절대 거리나 임상 CVA 측정값이 아니다.
- 서로 다른 프레임의 원시 depth scale·offset이 같다고 가정하지 않는다.
- 자세 판정은 모델 출력 자체가 아니라 ROI 차이를 reference IQR로 정규화한 특성값을 사용한다.
- 모델 리소스 누락이나 로드 실패는 캐시하고 이후 추론도 실패로 닫는다.
- 출력 형식이 지원되지 않거나 depth map을 만들 수 없으면 해당 프레임을 유효 자세 증거로 사용하지 않는다.
- 로컬 AI CLI 결과는 이 모델의 출력이나 공통 자세 판정으로 되돌아오지 않는다.

## 구현 대응

- 모델 로딩과 상대 깊이 변환: [`CoreMLRelativeDepthProvider.swift`](../../Sources/TurtleCore/Inference/CoreMLRelativeDepthProvider.swift)
- ROI와 정규화 특성값: [`PostureAnalyzer.swift`](../../Sources/TurtleCore/Detection/PostureAnalyzer.swift)
- 모델 패키징: [`package.sh`](../../package.sh)
- 전체 판정 순서: [상세 판정 알고리즘](algorithm.md)
