# Apple Vision 2D body pose

## 문서 요약

| 항목 | 내용 |
|---|---|
| 문서 유형 | Apple Vision 2D API 리서치 |
| 적용 상태 | PoseNet 상체 품질 실패 시 fallback |
| 입력 | 이미지, pixel buffer 또는 sample buffer와 orientation |
| 출력 | 최대 19개 2D body point와 관절별 confidence |
| 제품 내 역할 | 머리·목·양쪽 어깨 landmark와 ROI 품질 입력 제공 |

## 1. API 계약

`VNDetectHumanBodyPoseRequest`는 iOS 14와 macOS 11부터 제공되는 Vision 요청이다. 요청 결과는 `VNHumanBodyPoseObservation` 배열이며 한 이미지의 여러 사람을 관찰할 수 있다.

Vision은 최대 19개 body point를 제공한다.

- 얼굴: nose, left/right eye, left/right ear
- 상체: neck, left/right shoulder, left/right elbow, left/right wrist
- 하체: root, left/right hip, left/right knee, left/right ankle

PoseNet의 17개 관절과 달리 `neck`과 `root`가 포함된다. 관절 이름과 수가 다르므로 두 detector의 index를 직접 공유하지 않고 공통 도메인 모델에 이름으로 매핑한다.

## 2. 실행과 출력 읽기

1. 입력 종류에 맞는 `VNImageRequestHandler`를 만든다.
2. 카메라 센서와 이미지 metadata에 맞는 orientation을 전달한다.
3. `VNDetectHumanBodyPoseRequest`를 수행한다.
4. observation별로 필요한 `recognizedPoint` 또는 point group을 읽는다.
5. confidence와 좌표 변환을 보존한 채 공통 `PoseLandmarks`로 변환한다.
6. 대상 사람과 상체 품질 조건을 확인한다.

Vision request가 성공했다는 사실과 유효한 상체 landmark가 있다는 사실은 다르다. 결과 배열이 비었거나 필수 관절 confidence가 낮으면 평가 가능한 pose가 아니다.

## 3. 좌표계

- recognized point 위치는 `[0, 1]` 범위의 정규화 좌표다.
- Vision 이미지 좌표 원점은 좌하단이다.
- 제품 내부 좌상단 원점으로 변환할 때 `y_internal = 1 - y_vision`을 적용한다.
- orientation, crop/scale, 화면 미러링은 각각 한 번만 적용한다.
- Depth Anything V2 ROI와 결합하기 전에 동일 원본 프레임 좌표로 정렬한다.

현재 제품 mapping은 nose, eyes, ears, neck, shoulders를 보존한다. Vision에서만 존재하는 `neck`은 선택적인 진단 정보이며 PoseNet 경로와의 공통 필수점으로 사용하지 않는다.

## 4. confidence와 품질

각 recognized point는 위치와 confidence를 제공한다. 낮은 confidence 점을 좌표가 존재한다는 이유만으로 사용하지 않는다. 제품 상체 품질 게이트는 다음을 별도로 확인한다.

- 신뢰 가능한 머리 anchor 존재
- 양쪽 어깨 존재와 confidence
- 최소 어깨 폭
- 허용 가능한 어깨 기울기
- 화면 경계·가림·ROI 유효 픽셀 조건

Vision confidence는 해당 관절 관측의 품질 정보다. 자세가 정상이라는 점수도 아니고 PoseNet heatmap score와 보정된 공통 확률도 아니다.

## 5. 공식적으로 알려진 실패 조건

Apple은 다음 조건에서 결과가 나빠질 수 있다고 설명한다.

- 사람이 몸을 크게 숙이거나 거꾸로 있는 비정형 자세
- 관절을 가리는 흐르는 옷
- 한 사람이 다른 사람을 부분적으로 가리는 장면
- 대상이 이미지 가장자리에 가까운 장면

따라서 observation의 첫 번째 사람을 무조건 선택하거나 누락 관절을 가상 좌표로 보완하지 않는다. 알려진 대상 영역이 있으면 region of interest가 정확도와 처리 범위를 개선할 수 있지만, 잘못된 ROI는 대상을 제외할 수 있으므로 별도 검증이 필요하다.

## 6. PoseNet과의 fallback 경계

현재 호출 순서는 다음과 같다.

1. 같은 RGB 프레임을 Apple Core ML 샘플 PoseNet으로 분석한다.
2. PoseNet 결과가 상체 품질 조건을 통과하면 그 결과만 사용한다.
3. PoseNet 실행 또는 상체 품질이 실패하면 같은 프레임에 Vision 2D 요청을 수행한다.
4. Vision도 후보를 내지 못하면 PoseNet의 부분 검출을 보존한다. 신뢰할 수 있는 머리가 있으면 하류에서 자세 기인 평가 불가 여부를 판단하고, 머리조차 없으면 `noEval`로 처리한다.

두 모델의 부분 관절을 합쳐 하나의 사람을 만들지 않는다. 자세 모델이 바뀌어도 이후의 대상 선택, ROI, depth, baseline, 시간 판정 계약은 동일해야 한다.

## 7. 제공하지 않는 정보

- 실제 카메라 거리나 z축 깊이
- 신체 부위별 segmentation mask
- 임상 C7·tragus 위치와 CVA
- `good`·`bad` 자세 상태
- 3D skeleton

3D body pose는 별도 API이며 [`related-vision-3d.md`](related-vision-3d.md)에서 관리한다. PoseNet 모델 계약은 [`../apple-posenet/analysis.md`](../apple-posenet/analysis.md)를 참조한다.

## 참고 자료

- Apple “Detecting Human Body Poses in Images”: <https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images>
- Apple `VNDetectHumanBodyPoseRequest`: <https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest>
- WWDC20 “Detect Body and Hand Pose with Vision”: <https://developer.apple.com/videos/play/wwdc2020/10653/>
- Apple body landmarks: <https://developer.apple.com/documentation/vision/body-landmarks>
