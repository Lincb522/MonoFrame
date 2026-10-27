import SwiftUI
import UIKit

struct PermissionSetupView: View {
    let completion: () -> Void

    @StateObject private var permissions = PermissionCenter()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 42)

            ZStack(alignment: .topTrailing) {
                HStack(spacing: 16) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 32, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 68, height: 68)
                        .background(SignalColor.acid)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("你说了算")
                            .font(.system(.title2, design: .rounded, weight: .black))
                        Text("权限不多要，数据不外传")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 148)
                .background(SignalColor.stage)
                .clipShape(YouthNotchedPanelShape(cornerRadius: 34, notchWidth: 92, notchDepth: 60))

                YouthStatusBubble(value: "2", symbol: "checkmark.shield.fill")
                    .padding(8)
            }
            .padding(.horizontal, 22)

            Text("权限")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .tracking(-0.8)
                .padding(.top, 24)
            Text("只在你使用对应功能时申请")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(SignalColor.secondary(scheme))
                .padding(.top, 7)

            VStack(spacing: 0) {
                permissionRow(
                    title: "照片",
                    detail: "视频与 Live Photo",
                    symbol: "photo.on.rectangle",
                    state: permissions.photo
                )
                Divider().padding(.leading, 58)
                permissionRow(
                    title: "麦克风",
                    detail: "录音",
                    symbol: "mic.fill",
                    state: permissions.microphone
                )
            }
            .padding(.horizontal, 16)
            .background(SignalColor.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 22)
            .padding(.top, 34)

            Spacer(minLength: 28)

            VStack(spacing: 10) {
                Button { primaryAction() } label: {
                    Group {
                        if permissions.isRequesting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(primaryTitle)
                        }
                    }
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(SignalPrimaryButtonStyle(tint: SignalColor.ink(scheme)))
                .disabled(permissions.isRequesting)

                Button(permissions.hasDeniedAccess ? "完成" : "稍后") {
                    completion()
                }
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(SignalColor.secondary(scheme))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
        .foregroundStyle(SignalColor.ink(scheme))
        .background { SignalPageBackground() }
        .interactiveDismissDisabled()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { permissions.refresh() }
        }
    }

    private var primaryTitle: String {
        if permissions.hasDeniedAccess { return "打开系统设置" }
        if permissions.hasUndeterminedAccess { return "继续" }
        return "进入 MonoFrame"
    }

    private func permissionRow(
        title: String,
        detail: String,
        symbol: String,
        state: PermissionCenter.AccessState
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .black))
                .frame(width: 42, height: 42)
                .foregroundStyle(.white)
                .background(SignalColor.ink(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .black))
                Text(detail)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(SignalColor.secondary(scheme))
            }
            Spacer()
            Image(systemName: state.symbol)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(state == .allowed ? SignalColor.success : SignalColor.secondary(scheme))
                .accessibilityLabel(state.title)
        }
        .frame(minHeight: 76)
    }

    private func primaryAction() {
        if permissions.hasDeniedAccess {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(url)
            return
        }
        if !permissions.hasUndeterminedAccess {
            completion()
            return
        }
        Task {
            await permissions.requestAccess()
            if !permissions.hasDeniedAccess, !permissions.hasUndeterminedAccess {
                completion()
            }
        }
    }
}
