import Combine
import Foundation

private struct RewardSnapshotPayload: Codable, Sendable {
    let balanceMinutes: Int
    let unlockEndsAt: String?

    init(snapshot: RewardSnapshot) {
        balanceMinutes = snapshot.balanceMinutes
        if let unlockEndsAt = snapshot.unlockEndsAt {
            self.unlockEndsAt = ISO8601DateFormatter().string(from: unlockEndsAt)
        } else {
            self.unlockEndsAt = nil
        }
    }

    func makeSnapshot() throws -> RewardSnapshot {
        let endsAt: Date?
        if let unlockEndsAt {
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let parsedDate = fractionalFormatter.date(from: unlockEndsAt)
                ?? ISO8601DateFormatter().date(from: unlockEndsAt)
            guard let parsedDate else {
                throw RewardSyncError.invalidResponse
            }
            endsAt = parsedDate
        } else {
            endsAt = nil
        }
        return RewardSnapshot(balanceMinutes: balanceMinutes, unlockEndsAt: endsAt)
    }
}

private enum RewardSyncError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "MacのAPIアドレスを http://ホスト名:8787 の形式で入力してください。"
        case .invalidResponse:
            return "APIから受け取った報酬データを読み取れませんでした。"
        case .httpStatus(let statusCode):
            return "APIがHTTP \(statusCode) を返しました。Mac側のAPI起動状態を確認してください。"
        }
    }
}

@MainActor
final class RewardSyncPrototype: ObservableObject {
    @Published var serverAddress = ""
    @Published private(set) var receivedSnapshot: RewardSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    func fetchSnapshot() async {
        guard let url = snapshotURL() else {
            errorMessage = RewardSyncError.invalidAddress.localizedDescription
            statusMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer { isLoading = false }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 8

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw RewardSyncError.invalidResponse
            }
            guard response.statusCode == 200 else {
                throw RewardSyncError.httpStatus(response.statusCode)
            }

            let payload = try JSONDecoder().decode(RewardSnapshotPayload.self, from: data)
            receivedSnapshot = try payload.makeSnapshot()
            statusMessage = "Mac/APIから報酬状態を取得しました。"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func snapshotURL() -> URL? {
        let address = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: address),
              baseURL.scheme == "http",
              baseURL.host != nil,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, "v1/reward-snapshot"].filter { !$0.isEmpty }.joined(separator: "/")
        return components.url
    }
}
