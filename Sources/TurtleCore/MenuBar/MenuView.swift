import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel
    @State private var isAdvancedExpanded = false
    @State private var isPrivacyExpanded = false

    private enum Layout {
        static let trailingControlWidth: CGFloat = 172
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                statusPanel
                quickActionsPanel
                todayPanel
                settingsPanel
                advancedPanel
                privacyPanel
                footerActions
            }
            .padding(14)
        }
        .frame(width: 360)
    }

    private var statusPanel: some View {
        MenuPanel {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(stateTint.opacity(0.14))
                    Image(systemName: symbolName)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(stateTint)
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.statusText)
                        .font(.headline)
                        .lineLimit(2)
                    Text(model.nextCheckDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.diagnosticText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var quickActionsPanel: some View {
        MenuPanel {
            HStack(spacing: 8) {
                Button {
                    model.checkNow()
                } label: {
                    Label("지금 점검", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isPaused)

                Button {
                    if model.isPaused {
                        model.resume()
                    } else {
                        model.pause()
                    }
                } label: {
                    Label(model.isPaused ? "재개" : "일시정지", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    model.recalibrateFromCurrentGoodSignal()
                } label: {
                    Label("재보정", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.isPaused)
            }
            .controlSize(.regular)
        }
    }

    private var todayPanel: some View {
        MenuPanel {
            VStack(alignment: .leading, spacing: 9) {
                sectionTitle("오늘 요약")

                VStack(spacing: 7) {
                    TodayDurationRow(
                        title: "바른 자세 시간",
                        value: formatDuration(model.todayStats.goodSeconds),
                        systemImage: "checkmark.circle.fill",
                        tint: .green
                    )
                    TodayDurationRow(
                        title: "주의 자세 시간",
                        value: formatDuration(model.todayStats.badSeconds),
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .orange
                    )
                }

                Divider()

                HStack(spacing: 8) {
                    MiniMetric(title: "주의 전환", value: "\(model.todayStats.cautionTransitions)회")
                    MiniMetric(title: "회복 횟수", value: "\(model.todayStats.recoveries)회")
                    MiniMetric(title: "보낸 알림", value: "\(model.todayStats.notificationsSent)회")
                }
            }
        }
    }

    private var settingsPanel: some View {
        MenuPanel {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("설정")

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label("민감도", systemImage: "slider.horizontal.3")
                            .font(.callout)
                        Spacer()
                        Picker("민감도", selection: Binding(
                            get: { model.settings.sensitivity },
                            set: { model.setSensitivity($0) }
                        )) {
                            ForEach(Sensitivity.allCases, id: \.self) { sensitivity in
                                Text(sensitivity.title).tag(sensitivity)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: Layout.trailingControlWidth, alignment: .trailing)
                    }
                    Text(model.settings.sensitivity.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label("점검 주기", systemImage: "clock")
                            .font(.callout)
                        Spacer()
                        Picker("점검 주기", selection: Binding(
                            get: { model.settings.checkIntervalSeconds },
                            set: { model.setCheckInterval(Double($0)) }
                        )) {
                            ForEach(stride(from: 10, through: 180, by: 10).map { $0 }, id: \.self) { seconds in
                                Text("\(seconds)초").tag(seconds)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: Layout.trailingControlWidth, alignment: .trailing)
                    }
                }

                Toggle(isOn: Binding(
                    get: { model.settings.bannerNotificationsEnabled },
                    set: { model.setBannerNotifications($0) }
                )) {
                    Label("배너 알림", systemImage: "bell")
                        .font(.callout)
                }

                Toggle(isOn: Binding(
                    get: { model.settings.notificationSoundEnabled },
                    set: { model.setNotificationSound($0) }
                )) {
                    Label("알림 소리", systemImage: "speaker.wave.2")
                        .font(.callout)
                }
                .disabled(!model.settings.bannerNotificationsEnabled)

                Toggle(isOn: Binding(
                    get: { model.settings.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )) {
                    Label("로그인 시 자동 실행", systemImage: "power.circle")
                        .font(.callout)
                }

                HStack {
                    Label("알림 쉬기", systemImage: "moon.zzz")
                        .font(.callout)
                    Spacer()
                    Button {
                        model.snoozeNotifications()
                    } label: {
                        Text("20분 스누즈")
                    }
                    .disabled(!model.settings.bannerNotificationsEnabled)
                    .help("20분 스누즈")
                }
            }
        }
    }

    private var advancedPanel: some View {
        MenuPanel {
            MenuDisclosureRow(title: "고급 설정", isExpanded: $isAdvancedExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    if model.settings.debugEnabled {
                        HStack {
                            Label("AI/ML 분석 방식", systemImage: "function")
                                .font(.callout)
                            Spacer()
                            Picker("AI/ML 분석 방식", selection: Binding(
                                get: { model.settings.postureAlgorithm },
                                set: { model.setPostureAlgorithm($0) }
                            )) {
                                ForEach(PostureAlgorithmID.debugSelectableMethods, id: \.self) { algorithm in
                                    Text(algorithm.title).tag(algorithm)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: Layout.trailingControlWidth, alignment: .trailing)
                        }

                        Text(model.settings.postureAlgorithm.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("분석 방식: 자동 (시점 인식)")
                                .font(.callout)
                            Text("정면=깊이 · 측면/3-4=2D 시상 기하를 자동 선택")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle(isOn: Binding(
                        get: { model.settings.debugEnabled },
                        set: { model.setDebugEnabled($0) }
                    )) {
                        Label("디버그 모드", systemImage: "stethoscope")
                            .font(.callout)
                    }

                    Text(model.settings.debugEnabled
                        ? "웹캠 캡처와 분석 JSON이 로컬 디버그 폴더에 저장됩니다. 끄면 최근 캡처가 삭제됩니다."
                        : "켜면 수동 분석 방식 선택과 로컬 디버그 캡처 저장이 활성화됩니다.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.settings.debugEnabled {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("디버그 측정")
                                .font(.caption.weight(.semibold))
                            ForEach(Array(model.debugLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if model.debugArtifactPath != nil {
                                Button("디버그 폴더 열기") {
                                    model.openDebugArtifacts()
                                }
                                .font(.caption)
                                .padding(.top, 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var privacyPanel: some View {
        MenuPanel {
            MenuDisclosureRow(title: "개인정보 · 비의료 안내", isExpanded: $isPrivacyExpanded) {
                Text(Disclaimer.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footerActions: some View {
        HStack {
            Button {
                model.openCameraPrivacySettings()
            } label: {
                Label("카메라 권한 설정", systemImage: "video")
            }

            Spacer()

            Button(role: .destructive) {
                model.quit()
            } label: {
                Label("종료", systemImage: "power")
            }
        }
        .controlSize(.small)
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

    private var stateTint: Color {
        switch model.postureState {
        case .good:
            return .green
        case .bad:
            return .orange
        case .paused:
            return .secondary
        case .blocked, .needsCalibration:
            return .red
        case .calibrating:
            return .blue
        case .noEval:
            return .accentColor
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)분"
        }
        return "\(minutes / 60)시간 \(minutes % 60)분"
    }
}

private struct MenuPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
    }
}

private struct MenuDisclosureRow<Content: View>: View {
    var title: String
    @Binding var isExpanded: Bool
    private let content: () -> Content

    init(title: String, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 13, height: 18)
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.top, 10)
            }
        }
    }
}

private struct TodayDurationRow: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
                .font(.callout)
            Spacer()
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MiniMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
