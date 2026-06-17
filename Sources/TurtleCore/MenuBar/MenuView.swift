import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: symbolName)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.statusText)
                        .font(.headline)
                    Text(model.nextCheckDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            HStack {
                Button(model.isPaused ? "재개" : "일시정지") {
                    model.isPaused ? model.resume() : model.pause()
                }
                Button("지금 점검") {
                    model.checkNow()
                }
                Button("재보정") {
                    model.recalibrateFromCurrentGoodSignal()
                }
            }

            VStack(alignment: .leading) {
                Text("점검 주기 \(model.settings.checkIntervalSeconds)초")
                    .font(.caption)
                Slider(
                    value: Binding(
                        get: { Double(model.settings.checkIntervalSeconds) },
                        set: { model.setCheckInterval($0) }
                    ),
                    in: 10...180,
                    step: 10
                )
            }

            Picker("민감도", selection: Binding(
                get: { model.settings.sensitivity },
                set: { model.setSensitivity($0) }
            )) {
                ForEach(Sensitivity.allCases, id: \.self) { sensitivity in
                    Text(sensitivity.title).tag(sensitivity)
                }
            }
            .pickerStyle(.segmented)
            Text(model.settings.sensitivity.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("카메라 위치", selection: Binding(
                get: { model.settings.cameraPlacement },
                set: { model.setCameraPlacement($0) }
            )) {
                Text("정면").tag(CameraPlacement.center)
                Text("왼쪽").tag(CameraPlacement.left)
                Text("오른쪽").tag(CameraPlacement.right)
            }
            .pickerStyle(.segmented)

            Toggle("배너 알림", isOn: Binding(
                get: { model.settings.bannerNotificationsEnabled },
                set: { model.setBannerNotifications($0) }
            ))

            Toggle("알림 소리", isOn: Binding(
                get: { model.settings.notificationSoundEnabled },
                set: { model.setNotificationSound($0) }
            ))
            .disabled(!model.settings.bannerNotificationsEnabled)

            Button("20분 스누즈") {
                model.snoozeNotifications()
            }
            .disabled(!model.settings.bannerNotificationsEnabled)

            Toggle("로그인 시 자동 실행", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            Button("카메라 권한 설정 열기") {
                model.openCameraPrivacySettings()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("오늘 정상 \(formatDuration(model.todayStats.goodSeconds)) · 주의 \(formatDuration(model.todayStats.badSeconds))")
                Text("전환 \(model.todayStats.cautionTransitions)회 · 회복 \(model.todayStats.recoveries)회 · 알림 \(model.todayStats.notificationsSent)회")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            DisclosureGroup("개인정보 · 비의료 안내") {
                Text(Disclaimer.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("종료") {
                model.quit()
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var symbolName: String {
        switch model.postureState {
        case .good:
            return "tortoise.fill"
        case .bad:
            return "exclamationmark.triangle.fill"
        case .paused:
            return "pause.circle.fill"
        case .blocked:
            return "video.slash.fill"
        case .calibrating:
            return "scope"
        case .noEval:
            return "questionmark.circle"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)분"
        }
        return "\(minutes / 60)시간 \(minutes % 60)분"
    }
}
