import SwiftUI

struct RunningJobsPage: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var runner: TaskRunner
    var onGoTech: () -> Void

    private var kinds: [String] { runner.runningKinds.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("进行中")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            if kinds.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Text("暂无运行任务")
                        .font(Typo.body)
                        .foregroundStyle(Palette.textSecondary)
                    Button("去科技") {
                        Haptics.tap()
                        onGoTech()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 40)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(kinds, id: \.self) { k in
                            HStack {
                                Circle()
                                    .fill(Palette.liveAmber)
                                    .frame(width: 8, height: 8)
                                Text(FeatureCatalog.labelOf(k).ifEmpty(k))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Palette.textPrimary)
                                Spacer()
                                Button("停止") {
                                    Haptics.warn()
                                    if let kind = TaskKind(rawValue: k) { vm.stopTask(kind) }
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.danger)
                            }
                            .padding(14)
                            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        Button("全部停止") {
                            Haptics.warn()
                            vm.stopAllTasks()
                        }
                        .buttonStyle(DangerButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
