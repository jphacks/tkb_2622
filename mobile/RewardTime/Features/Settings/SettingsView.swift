import SwiftUI
import FamilyControls

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var screenTime: MobileScreenTimeController
    @State private var isFamilyActivityPickerPresented = false
    @State private var isSyncingDeviceSettings = false
    @State private var deviceSyncStatus = "未同期"
    @State private var deviceSyncError: String?

    var body: some View {
        ScreenContainer {
            #if DEBUG
            AuthenticationSettingsSection {
                Task { await syncDeviceSettings() }
            }
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

                HStack {
                    Label("backend設定同期", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text(deviceSyncStatus)
                        .font(.caption)
                        .foregroundStyle(deviceSyncError == nil ? AppTheme.secondaryInk : .red)
                }
                if let deviceSyncError {
                    Text(deviceSyncError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    Task { await syncDeviceSettings() }
                } label: {
                    Label(
                        isSyncingDeviceSettings ? "端末・設定を同期中…" : "端末と制限設定をbackendへ同期",
                        systemImage: "arrow.up.circle"
                    )
                    .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.bordered)
                .disabled(isSyncingDeviceSettings)
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
                deviceRow(name: "この iPhone", state: deviceSyncStatus)
                Divider()
                deviceRow(name: "MacBook Air", state: "このiPhoneからは未取得")
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
        .task { await syncDeviceSettings() }
        .onChange(of: screenTime.deviceConfigVersion) { _ in
            Task { await syncDeviceSettings() }
        }
        .onChange(of: screenTime.authorizationStatusLabel) { _ in
            Task { await syncDeviceSettings() }
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.bold))
    }

    @MainActor
    private func syncDeviceSettings() async {
        guard !isSyncingDeviceSettings else { return }
        isSyncingDeviceSettings = true
        defer { isSyncingDeviceSettings = false }
        do {
            let synced = try await ConfiguredDeviceSettingsRepository().sync(
                settings: screenTime.backendRestrictionSettings
            )
            deviceSyncStatus = "登録済み・設定 v\(synced.policyVersion)・\(policyStatusLabel(synced.policyStatus))"
            deviceSyncError = nil
        } catch DeviceSettingsRepositoryError.missingConfiguration {
            deviceSyncStatus = "未ログイン"
            deviceSyncError = "アカウント接続後に同期できます。"
        } catch DeviceSettingsRepositoryError.invalidConfiguration {
            deviceSyncStatus = "設定エラー"
            deviceSyncError = "Supabase URL・公開用キー・API URLを確認してください。"
        } catch let error as LocalizedError {
            deviceSyncStatus = "同期できません"
            deviceSyncError = error.errorDescription ?? "API接続とログイン状態を確認してください。"
        } catch {
            deviceSyncStatus = "同期できません"
            deviceSyncError = "API接続とログイン状態を確認してください。"
        }
    }

    private func policyStatusLabel(_ status: String) -> String {
        switch status {
        case "POLICY_STATUS_ENABLED": "有効"
        case "POLICY_STATUS_DISABLED": "無効"
        case "POLICY_STATUS_PERMISSION_REQUIRED": "端末の権限報告待ち"
        default: "状態未確定"
        }
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
