import SwiftUI
import FamilyControls

struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var screenTime: MobileScreenTimeController
    private let isAuthenticated: Bool
    @State private var isFamilyActivityPickerPresented = false
    @State private var isSyncingDeviceSettings = false
    @State private var deviceSettingsSyncGate = DeviceSettingsSyncGate()
    @State private var hasOpenUsageGrant = false
    @State private var deviceSyncError: String?

    init(screenTime: MobileScreenTimeController, isAuthenticated: Bool = true) {
        _screenTime = ObservedObject(wrappedValue: screenTime)
        self.isAuthenticated = isAuthenticated
    }

    var body: some View {
        ScreenContainer {
            AuthenticationSettingsSection(
                showsDeveloperConfiguration: true,
                allowsAutomaticAPISync: isAuthenticated
            ) {
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
                    if screenTime.hasUnsupportedTargets {
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
                sectionTitle("アプリ制限", icon: "slider.horizontal.3")
                Label("指定したアプリのみ制限", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)

                HStack {
                    Label("制限するアプリ", systemImage: "square.grid.2x2")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(screenTime.restrictedApplicationCount)個")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                }
                Button {
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

                Label(
                    hasOpenUsageGrant ? "利用枠のため一時解除中" : screenTime.hasAppliedRestriction ? "選択したアプリを制限中" : "作業中に自動で制限",
                    systemImage: hasOpenUsageGrant ? "lock.open" : screenTime.hasAppliedRestriction ? "lock.fill" : "lock.iphone"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(screenTime.hasAppliedRestriction ? AppTheme.teal : AppTheme.secondaryInk)

                if let reason = screenTime.applyRestrictionUnavailableReason {
                    Label(reason, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
            headerText: "制限するアプリを選択",
            footerText: nil,
            isPresented: $isFamilyActivityPickerPresented,
            selection: Binding(
                get: {
                    screenTime.selection
                },
                set: { newSelection in
                    screenTime.selection = newSelection
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
        let authenticatedUserID = MobileAppConfiguration.makeAuthService()?.authenticatedUserID
        let request = DeviceSettingsSyncRequestKey(
            isAuthenticated: isAuthenticated && authenticatedUserID != nil,
            authenticatedUserID: authenticatedUserID,
            settings: screenTime.backendRestrictionSettings
        )
        guard deviceSettingsSyncGate.begin(request) else { return }

        isSyncingDeviceSettings = true
        defer { isSyncingDeviceSettings = false }

        var requestToRun: DeviceSettingsSyncRequestKey? = request
        while let currentRequest = requestToRun {
            await performDeviceSettingsSync(for: currentRequest)
            requestToRun = deviceSettingsSyncGate.finish()
        }
    }

    @MainActor
    private func performDeviceSettingsSync(for request: DeviceSettingsSyncRequestKey) async {
        do {
            try await AuthenticatedAPISyncFlow.run(
                isAuthenticated: request.isAuthenticated
            ) {
                _ = try await ConfiguredDeviceSettingsRepository().sync(
                    settings: request.settings
                )
            }
            deviceSyncError = nil
        } catch DeviceSettingsRepositoryError.missingConfiguration {
            deviceSyncError = nil
        } catch DeviceSettingsRepositoryError.invalidConfiguration {
            deviceSyncError = "接続設定を確認してください。"
        } catch {
            deviceSyncError = DeviceSettingsSyncErrorMessage.describe(error)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { SettingsView(screenTime: MobileScreenTimeController()) }
    }
}
