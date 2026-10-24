import SwiftUI

struct BackendHealthCheckView: View {
    private enum CheckState {
        case idle
        case checking
        case succeeded
        case failed(String)
    }

    @State private var baseURLText = ProcessInfo.processInfo.environment["TKB_API_BASE_URL"] ?? "http://127.0.0.1:8080"
    @State private var checkState: CheckState = .idle

    var body: some View {
        ScreenContainer {
            SampleNotice(title: "Debug・API接続確認")

            SurfaceCard {
                Text("backendの生存確認")
                    .font(.headline)
                Text("GET /healthz のみを確認します。認証やデータベース、業務APIの状態は確認しません。")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.secondaryInk)

                TextField("http://127.0.0.1:8080", text: $baseURLText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("apiBaseURL")

                Button {
                    Task { await checkHealth() }
                } label: {
                    Label(buttonTitle, systemImage: "network")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .disabled(isChecking)

                statusView
            }
        }
        .navigationTitle("API接続確認")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var buttonTitle: String {
        isChecking ? "確認中…" : "接続を確認"
    }

    private var isChecking: Bool {
        if case .checking = checkState { return true }
        return false
    }

    @ViewBuilder
    private var statusView: some View {
        switch checkState {
        case .idle:
            Text("まだ確認していません。")
                .font(.footnote)
                .foregroundStyle(AppTheme.secondaryInk)
        case .checking:
            ProgressView("接続を確認中…")
                .font(.footnote)
        case .succeeded:
            Label("接続成功（status: ok）", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.teal)
                .accessibilityIdentifier("apiHealthSuccess")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("apiHealthFailure")
        }
    }

    @MainActor
    private func checkHealth() async {
        guard let baseURL = URL(string: baseURLText),
              ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""),
              baseURL.host != nil else {
            checkState = .failed("URLを確認してください。例: http://127.0.0.1:8080")
            return
        }

        checkState = .checking
        do {
            let client = ConnectJSONClient(baseURL: baseURL, tokenProvider: NoAccessTokenProvider())
            _ = try await client.checkHealth()
            checkState = .succeeded
        } catch let error as ConnectJSONClient.ClientError {
            switch error {
            case .httpStatus(let code):
                checkState = .failed("HTTPエラー（\(code)）。URLとbackendの起動状態を確認してください。")
            case .unexpectedHealthStatus:
                checkState = .failed("backendから正常なhealth応答がありませんでした。")
            case .missingAccessToken, .invalidResponse, .connect:
                checkState = .failed("backendから正常なhealth応答がありませんでした。")
            }
        } catch {
            checkState = .failed("接続できませんでした。URL、ネットワーク、backendの起動状態を確認してください。")
        }
    }
}

private struct NoAccessTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String? { nil }
}
