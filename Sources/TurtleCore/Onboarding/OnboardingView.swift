import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            setupSteps
            sensitivityPanel
            privacyPanel
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 500, height: 500)
        .onAppear { model.checkCameraAvailability() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: "tortoise.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text("turtlemeck")
                    .font(.title2.weight(.semibold))
                Text("메뉴 막대에서 자세를 조용히 확인합니다.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var setupSteps: some View {
        OnboardingPanel {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingStep(
                    number: "1",
                    title: "카메라 권한 허용",
                    detail: "상태: \(model.statusText)"
                ) {
                    Button {
                        model.requestCameraPermission()
                    } label: {
                        Label("권한 요청", systemImage: "camera")
                    }
                }

                Divider()

                OnboardingStep(
                    number: "2",
                    title: "기준자세 보정",
                    detail: "좋은 자세로 앉은 뒤 한 번 저장합니다."
                ) {
                    Button {
                        model.recalibrateFromCurrentGoodSignal()
                    } label: {
                        Label("보정", systemImage: "scope")
                    }
                }

                Divider()

                OnboardingStep(
                    number: "3",
                    title: "시작",
                    detail: "이후에는 메뉴 막대에서 상태를 확인합니다."
                ) {
                    Button {
                        model.markOnboardingComplete()
                        model.start()
                        onStart()
                    } label: {
                        Label("시작", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }

                HStack {
                    Spacer()
                    Button {
                        model.openCameraPrivacySettings()
                    } label: {
                        Label("시스템 설정", systemImage: "gearshape")
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private var sensitivityPanel: some View {
        OnboardingPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("민감도")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

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

                Text(model.settings.sensitivity.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privacyPanel: some View {
        OnboardingPanel {
            DisclosureGroup {
                Text(Disclaimer.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            } label: {
                Label("개인정보 · 비의료 안내", systemImage: "lock.shield")
                    .font(.subheadline)
            }
        }
    }
}

private struct OnboardingPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
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

private struct OnboardingStep<Action: View>: View {
    var number: String
    var title: String
    var detail: String
    private let action: Action

    init(
        number: String,
        title: String,
        detail: String,
        @ViewBuilder action: () -> Action
    ) {
        self.number = number
        self.title = title
        self.detail = detail
        self.action = action()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
            action
        }
    }
}
