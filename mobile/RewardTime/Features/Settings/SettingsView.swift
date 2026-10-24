import SwiftUI
import FamilyControls

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var screenTime: MobileScreenTimeController
    private let isAuthenticated: Bool
    @State private var isFamilyActivityPickerPresented = false
    @State private var isPickingAlwaysAllowedApps = false
    @State private var isSyncingDeviceSettings = false
    @State private var needsDeviceSettingsSync = false
    @State private var hasOpenUsageGrant = false
    @State private var deviceSyncError: String?

    init(screenTime: MobileScreenTimeController, isAuthenticated: Bool = true) {
        _screenTime = ObservedObject(wrappedValue: screenTime)
        self.isAuthenticated = isAuthenticated
    }

    var body: some View {
        ScreenContainer {
            AuthenticationSettingsSection(showsDeveloperConfiguration: true) {
                NotificationCenter.default.post(name: .mobileAuthenticationChanged, object: nil)
                Task { await syncDeviceSettings() }
            }

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
                    if screenTime.restrictionMode == .selectedApplications && screenTime.hasUnsupportedTargets {
                        Text("カテゴリとWebサイトは制限できません。")
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

                if let deviceSyncError {
                    HStack {
                        Text(deviceSyncError)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("再試行") { Task { await syncDeviceSettings() } }
                            .font(.caption.weight(.semibold))
                            .disabled(isSyncingDeviceSettings)
                    }
                }
            }

            SurfaceCard {
                sectionTitle("制限モード", icon: "slider.horizontal.3")
                VStack(spacing: 8) {
                    ForEach([LocalRestrictionMode.entireDevice, .selectedApplications]) { mode in
                        Button {
                            screenTime.restrictionMode = mode
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: screenTime.restrictionMode == mode ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(screenTime.restrictionMode == mode ? AppTheme.primary : AppTheme.secondaryInk)
                                Text(mode.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(
                                screenTime.restrictionMode == mode ? AppTheme.lavender : AppTheme.background,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(hasOpenUsageGrant)
                    }
                }

                if screenTime.restrictionMode == .selectedApplications {
                    HStack {
                        Label("制限するアプリ", systemImage: "square.grid.2x2")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(screenTime.restrictedApplicationCount)個")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)
                    }
                    Button {
                        isPickingAlwaysAllowedApps = false
                        isFamilyActivityPickerPresented = true
                    } label: {
                        Label("アプリを選択", systemImage: "plus.app")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!screenTime.isAuthorized || hasOpenUsageGrant)

                    if !screenTime.restrictedApplicationTokens.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                            ForEach(Array(screenTime.restrictedApplicationTokens), id: \.self) { token in
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

                DisclosureGroup {
                    Text("標準アプリを選びます。Safariは含めないでください。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                    Button {
                        isPickingAlwaysAllowedApps = true
                        isFamilyActivityPickerPresented = true
                    } label: {
                        Label("アプリを選択", systemImage: "checkmark.app")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!screenTime.isAuthorized || hasOpenUsageGrant)
                } label: {
                    Label(
                        "常に許可するアプリ · \(screenTime.alwaysAllowedSelection.applicationTokens.count)",
                        systemImage: "checkmark.shield"
                    )
                    .font(.subheadline.weight(.medium))
                }

                Label(screenTime.appliedRestrictionLabel, systemImage: screenTime.appliedRestrictionMode == nil ? "lock.open" : "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(screenTime.appliedRestrictionMode == nil ? AppTheme.secondaryInk : AppTheme.teal)

                Button {
                    screenTime.applyRestriction()
                } label: {
                    Label(
                        screenTime.appliedRestrictionMode == nil ? "制限を適用" : "制限を再適用",
                        systemImage: "lock.iphone")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .disabled(!screenTime.isAuthorized || hasOpenUsageGrant)

                if hasOpenUsageGrant {
                    Text("利用枠を閉じると変更できます。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                }

                if let reason = screenTime.applyRestrictionUnavailableReason {
                    Label(reason, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("このアプリの制限を解除", role: .destructive) {
                    screenTime.clearRestriction()
                }
                .disabled(screenTime.appliedRestrictionMode == nil || hasOpenUsageGrant)

            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            screenTime.refreshAuthorizationStatus()
            refreshOpenUsageGrant()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                screenTime.refreshAuthorizationStatus()
                refreshOpenUsageGrant()
                Task { await syncDeviceSettings() }
            }
        }
        .onChange(of: isAuthenticated) { _, authenticated in
            if authenticated { Task { await syncDeviceSettings() } }
        }
        .familyActivityPicker(
            headerText: isPickingAlwaysAllowedApps ? "常時許可するアプリを選択" : "制限するアプリを選択",
            footerText: isPickingAlwaysAllowedApps ? "常時許可するApple標準アプリを選びます。Safariは選択しないでください。" : nil,
            isPresented: $isFamilyActivityPickerPresented,
            selection: Binding(
                get: {
                    isPickingAlwaysAllowedApps ? screenTime.alwaysAllowedSelection : screenTime.selection
                },
                set: { newSelection in
                    if isPickingAlwaysAllowedApps {
                        screenTime.alwaysAllowedSelection = newSelection
                    } else {
                        screenTime.selection = newSelection
                    }
                }
            )
        )
        .task { await syncDeviceSettings() }
        .onChange(of: screenTime.deviceConfigVersion) { _, _ in
            Task { await syncDeviceSettings() }
        }
        .onChange(of: screenTime.authorizationStatusLabel) { _, _ in
            Task { await syncDeviceSettings() }
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.bold))
    }

    private func refreshOpenUsageGrant() {
        hasOpenUsageGrant = ScreenTimeSharedStorage.defaults
            .string(forKey: "mobile.usage.activeGrantID") != nil
    }

    @MainActor
    private func syncDeviceSettings() async {
        guard !isSyncingDeviceSettings else {
            needsDeviceSettingsSync = true
            return
        }
        isSyncingDeviceSettings = true
        defer { isSyncingDeviceSettings = false }

        repeat {
            needsDeviceSettingsSync = false
            await performDeviceSettingsSync()
        } while needsDeviceSettingsSync
    }

    @MainActor
    private func performDeviceSettingsSync() async {
        let hasCurrentAuthUser = MobileAppConfiguration.makeAuthService()?.authenticatedUserID != nil
        do {
            try await AuthenticatedAPISyncFlow.run(
                isAuthenticated: isAuthenticated && hasCurrentAuthUser
            ) {
                _ = try await ConfiguredDeviceSettingsRepository().sync(
                    settings: screenTime.backendRestrictionSettings
                )
            }
            deviceSyncError = nil
        } catch DeviceSettingsRepositoryError.missingConfiguration {
            deviceSyncError = nil
        } catch DeviceSettingsRepositoryError.invalidConfiguration {
            deviceSyncError = "接続設定を確認してください。"
        } catch {
            deviceSyncError = "端末設定を同期できません。"
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { SettingsView(screenTime: MobileScreenTimeController()) }
    }
}
