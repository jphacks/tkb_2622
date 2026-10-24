import SwiftUI
import FamilyControls

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var screenTime = MobileScreenTimeController()
    @State private var isFamilyActivityPickerPresented = false

    var body: some View {
        ScreenContainer {
            SampleNotice(title: "設定画面案・端末設定未接続")

            #if DEBUG
            AuthenticationSettingsSection()
            #endif

            SurfaceCard {
                sectionTitle("スクリーンタイム", icon: "hourglass")
                HStack {
                    Text("本人の許可")
                    Spacer()
                    Text(screenTime.authorizationStatusLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(screenTime.isAuthorized ? AppTheme.teal : AppTheme.secondaryInk)
                }

                if screenTime.isAuthorized {
                    Text("許可後は下の「アプリ」から制限対象を選べます。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)

                    if screenTime.hasUnsupportedTargets {
                        Text("現在はアプリだけを制限できます。選択画面でカテゴリとWebサイトを外してください。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Button {
                        Task { await screenTime.requestAuthorization() }
                    } label: {
                        Label(
                            screenTime.isRequestingAuthorization ? "許可を確認中…" : "本人利用の許可を求める",
                            systemImage: "hand.raised")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                    .disabled(screenTime.isRequestingAuthorization)
                }

#if DEBUG
                Divider()
                Text("実機確認用")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.secondaryInk)
                Button("選択したアプリを制限") {
                    screenTime.applySelectedAppsForDebug()
                }
                .disabled(!screenTime.canApplySelectedApps)
                Button("このアプリの制限を解除", role: .destructive) {
                    screenTime.clearShieldForDebug()
                }
                .disabled(!screenTime.isAuthorized)
#endif

                if let statusMessage = screenTime.statusMessage {
                    Label(statusMessage, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let errorMessage = screenTime.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("アプリの選択はこの端末内に保存します。Shieldの自動適用はセッション状態APIとの接続後に有効になります。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            SurfaceCard {
                HStack {
                    sectionTitle("制限のしかた", icon: "slider.horizontal.3")
                    Spacer()
                    Text("仕様未確定")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(AppTheme.background, in: Capsule())
                }
                modeOption(
                    title: "選んだアプリを制限",
                    detail: "登録したアプリを対象にする案",
                    isSelected: true
                )
                modeOption(
                    title: "スマホ全体を制限",
                    detail: "対象範囲は仕様確定後に反映",
                    isSelected: false
                )
            }

            SurfaceCard {
                sectionTitle("アプリ", icon: "square.grid.2x2")
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("制限するアプリ")
                            .font(.subheadline.weight(.semibold))
                        Text(screenTime.isAuthorized ? "FamilyActivityPickerで選択したアプリ" : "スクリーンタイムの許可後に選べます")
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text("\(screenTime.selectedApplicationCount)個")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                }
                Button("アプリを選ぶ") {
                    isFamilyActivityPickerPresented = true
                }
                    .buttonStyle(.bordered)
                    .disabled(!screenTime.isAuthorized)
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Text("いつでも使えるアプリ")
                        .font(.subheadline.weight(.semibold))
                    Text("iPhoneの標準アプリ（Safariを除く）")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)
                    Text("仕様案・端末には未適用")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }

            SurfaceCard {
                sectionTitle("通知", icon: "bell")
                NavigationLink {
                    NotificationExamplesView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("通知の動作")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Text("報酬通知の抑制・グループ開始通知")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        Spacer()
                    }
                }
                .accessibilityIdentifier("notificationExamplesLink")
                Text("通知配信は未接続です。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            SurfaceCard {
                sectionTitle("端末", icon: "iphone.and.arrow.forward")
                deviceRow(name: "この iPhone", state: "端末登録未接続")
                Divider()
                deviceRow(name: "MacBook Air", state: "登録状態は未取得")
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { screenTime.refreshAuthorizationStatus() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { screenTime.refreshAuthorizationStatus() }
        }
        .familyActivityPicker(
            isPresented: $isFamilyActivityPickerPresented,
            selection: $screenTime.selection
        )
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.bold))
    }

    private func modeOption(title: String, detail: String, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? AppTheme.primary : AppTheme.secondaryInk)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? AppTheme.lavender : AppTheme.background, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func deviceRow(name: String, state: String) -> some View {
        HStack {
            Label(name, systemImage: name.contains("iPhone") ? "iphone" : "laptopcomputer")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(state)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryInk)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { SettingsView() }
    }
}
