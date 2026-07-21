import SwiftUI

struct MenuView: View {
    @ObservedObject var model: AppModel
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
                if model.settings.debugEnabled {
                    debugPanel
                }
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
                    Text(operationalStatusText)
                        .font(.caption2)
                        .foregroundStyle(operationalStatusTint)
                        .lineLimit(2)
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
                .disabled(model.isPaused || checksUnavailable)

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
                .disabled(checksUnavailable)

                Button {
                    model.recalibrateFromCurrentGoodSignal()
                } label: {
                    Label(model.settings.baseline == nil ? "기준자세 설정" : "재보정", systemImage: "scope")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.isPaused || model.postureState == .calibrating)
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
                        Label("점검 주기", systemImage: "clock")
                            .font(.callout)
                        Spacer()
                        Picker("점검 주기", selection: Binding(
                            get: { model.settings.checkIntervalSeconds },
                            set: { model.setCheckInterval(Double($0)) }
                        )) {
                            ForEach([15, 30, 60, 120, 180], id: \.self) { seconds in
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
                    .disabled(!model.settings.bannerNotificationsEnabled && !model.settings.notificationSoundEnabled)
                    .help("20분 스누즈")
                }
            }
        }
    }

    private var advancedPanel: some View {
        MenuPanel {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("분석")

                VStack(alignment: .leading, spacing: 2) {
                    Text("분석 방식: 공통 relative-depth 파이프라인")
                        .font(.callout)
                    Text(analysisDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: Binding(
                    get: { model.settings.debugEnabled },
                    set: { model.setDebugEnabled($0) }
                )) {
                    Label("디버그 모드", systemImage: "stethoscope")
                        .font(.callout)
                }
            }
        }
    }

    private var debugPanel: some View {
        MenuPanel {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("디버그")

                Text("디버그는 공통 판정 결과와 중간 품질 값만 추가로 표시합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 3) {
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

    /// baseline이 없거나 보정이 필요한 동안은 점검·일시정지를 쓸 수 없다.
    private var checksUnavailable: Bool {
        model.settings.baseline == nil || model.postureState == .needsCalibration
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

    private var analysisDescription: String {
        if model.settings.debugEnabled {
            return "같은 판정 경로의 landmark·ROI·depth·feature를 파일로 출력합니다."
        }
        return "2D 자세 ROI와 Depth Anything V2 상대 깊이를 개인 baseline과 비교합니다."
    }

    private var operationalStatusText: String {
        switch model.postureState {
        case .good:
            return model.settings.baseline == nil ? "기준자세 미보정" : "기준자세 저장됨"
        case .bad:
            return "잠시 자세를 펴고 다음 점검을 기다려 주세요"
        case .paused:
            return "측정과 알림이 멈춰 있습니다"
        case .blocked:
            return "카메라 권한 또는 장치 상태를 확인해 주세요"
        case .calibrating:
            return "움직이지 말고 좋은 자세를 유지해 주세요"
        case .noEval:
            return model.settings.baseline == nil ? "기준자세 보정이 필요합니다" : "측정 신호를 확인하는 중입니다"
        case .needsCalibration:
            return "바른 자세로 앉은 뒤 재보정을 실행해 주세요"
        }
    }

    private var operationalStatusTint: Color {
        switch model.postureState {
        case .blocked, .needsCalibration:
            return .red
        case .calibrating:
            return .blue
        case .bad:
            return .orange
        case .paused:
            return .secondary
        case .good, .noEval:
            return model.settings.baseline == nil ? .red : .secondary
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
