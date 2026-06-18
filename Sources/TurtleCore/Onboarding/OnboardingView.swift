import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "tortoise.fill")
                    .font(.largeTitle)
                VStack(alignment: .leading) {
                    Text("turtlemeck")
                        .font(.title)
                    Text("메뉴 막대에서 자세 징후를 조용히 알려줍니다.")
                        .foregroundStyle(.secondary)
                }
            }

            Text("약 1분마다 짧게 카메라가 켜져 자세를 추정합니다. 영상은 저장·전송되지 않고 기기 안에서만 처리됩니다.")
                .fixedSize(horizontal: false, vertical: true)

            Picker("카메라 위치", selection: Binding(
                get: { model.settings.cameraPlacement },
                set: { model.setCameraPlacement($0) }
            )) {
                Text("정면").tag(CameraPlacement.center)
                Text("왼쪽").tag(CameraPlacement.left)
                Text("오른쪽").tag(CameraPlacement.right)
            }
            .pickerStyle(.segmented)

            Button("기준자세 보정") {
                model.recalibrateFromCurrentGoodSignal()
            }

            Picker("민감도", selection: Binding(
                get: { model.settings.sensitivity },
                set: { model.setSensitivity($0) }
            )) {
                Text("낮음").tag(Sensitivity.low)
                Text("보통").tag(Sensitivity.medium)
                Text("높음").tag(Sensitivity.high)
            }
            .pickerStyle(.segmented)

            Text(Disclaimer.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Button("카메라 권한 요청") {
                    model.requestCameraPermission()
                }
                Button("시스템 설정") {
                    model.openCameraPrivacySettings()
                }
                Spacer()
                Button("시작") {
                    model.markOnboardingComplete()
                    model.start()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 460)
    }
}
