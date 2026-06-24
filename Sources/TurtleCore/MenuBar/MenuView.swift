import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    if let emoji = stateEmoji {
                        Text(emoji)
                            .font(.title2)
                    } else {
                        Image(systemName: symbolName)
                            .font(.title2)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.statusText)
                            .font(.headline)
                        Text(model.nextCheckDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(model.diagnosticText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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

                Picker("판정 알고리즘", selection: Binding(
                    get: { model.settings.postureAlgorithm },
                    set: { model.setPostureAlgorithm($0) }
                )) {
                    ForEach(PostureAlgorithmID.allCases, id: \.self) { algorithm in
                        Text(algorithm.title).tag(algorithm)
                    }
                }
                .pickerStyle(.menu)
                Text(model.settings.postureAlgorithm.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

                Toggle("디버그 모드", isOn: Binding(
                    get: { model.settings.debugEnabled },
                    set: { model.setDebugEnabled($0) }
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

                if model.settings.debugEnabled {
                    Divider()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("디버그 측정")
                            .font(.caption).bold()
                        ForEach(Array(model.debugLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .frame(width: 320)
    }

    private var symbolName: String {
        switch model.postureState {
        case .good:
            return "face.smiling"
        case .bad:
            return "tortoise.fill"
        case .paused:
            return "pause.circle.fill"
        case .blocked:
            return "video.slash.fill"
        case .calibrating:
            return "scope"
        case .noEval:
            return "figure.stand"
        case .needsCalibration:
            return "scope"
        }
    }

    private var stateEmoji: String? {
        switch model.postureState {
        case .noEval:
            return "🐢"
        case .good:
            return "🙂"
        case .bad:
            return "😢"
        case .paused:
            return "🫥"
        case .calibrating, .blocked, .needsCalibration:
            return nil
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
