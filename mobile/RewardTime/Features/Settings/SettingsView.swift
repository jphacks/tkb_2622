import SwiftUI
import FamilyControls

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var screenTime: MobileScreenTimeController
    @State private var isFamilyActivityPickerPresented = false

    var body: some View {
        ScreenContainer {
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
                    Label("スクリーンタイムを利用できます", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.teal)

                    if screenTime.restrictionMode == .selectedApplications && screenTime.hasUnsupportedTargets {
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

                Text("選択したアプリはこのiPhoneに保存します。セッションに応じた自動制限は、バックエンド連携後に有効になります。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
            }

            SurfaceCard {
                HStack {
                    sectionTitle("制限のしかた", icon: "slider.horizontal.3")
                    Spacer(minLength: 0)
                }
                modeButton(.selectedApplications)

                if screenTime.restrictionMode == .selectedApplications {
                    Divider()
                    sectionTitle("制限するアプリ", icon: "square.grid.2x2")
                    HStack {
                        Text("選択中のアプリ")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(screenTime.selectedApplicationCount)個")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)
                    }
                    Button {
                        isFamilyActivityPickerPresented = true
                    } label: {
                        Label("アプリを選ぶ", systemImage: "plus.app")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!screenTime.isAuthorized)

                    if !screenTime.selection.applicationTokens.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                            ForEach(Array(screenTime.selection.applicationTokens), id: \.self) { token in
                                Label(token)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    } else {
                        Text("制限するアプリを選んでください。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                }
                modeButton(.entireDevice)

                Label(screenTime.appliedRestrictionLabel, systemImage: screenTime.appliedRestrictionMode == nil ? "lock.open" : "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(screenTime.appliedRestrictionMode == nil ? AppTheme.secondaryInk : AppTheme.teal)

                Button {
                    screenTime.applyRestriction()
                } label: {
                    Label(
                        screenTime.appliedRestrictionMode == nil ? "この設定を適用" : "選択した設定を再適用",
                        systemImage: "lock.iphone")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)

                if let reason = screenTime.applyRestrictionUnavailableReason {
                    Label(reason, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("このアプリの制限を解除", role: .destructive) {
                    screenTime.clearRestriction()
                }
                .disabled(screenTime.appliedRestrictionMode == nil)

                Text("適用後、対象アプリを開いてiOSのShield画面が出ることを確認してください。解除ボタンからいつでも戻せます。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryInk)
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

    private func modeButton(_ mode: LocalRestrictionMode) -> some View {
        Button {
            screenTime.restrictionMode = mode
        } label: {
            modeOption(title: mode.title, detail: mode.detail, isSelected: screenTime.restrictionMode == mode)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("restrictionMode_\(mode.rawValue)")
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
        NavigationStack { SettingsView(screenTime: MobileScreenTimeController()) }
    }
}
