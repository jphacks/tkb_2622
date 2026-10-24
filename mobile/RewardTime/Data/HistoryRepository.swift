import Foundation

struct WorkHistoryItem: Identifiable {
    let id: String
    let taskName: String
    let status: String
    let startedAt: Date
    let endedAt: Date?
    let activeSeconds: Int64
    let workSeconds: Int64
    let earnedSeconds: Int64
    let spentSeconds: Int64
    let discardedSeconds: Int64
}

struct RewardHistoryItem: Identifiable {
    let id: String
    let sessionID: String
    let type: String
    let amountSeconds: Int64
    let balanceAfterSeconds: Int64
    let occurredAt: Date
}

struct HistoryPage<Item> {
    let items: [Item]
    let nextPageToken: String
}

protocol HistoryRepository {
    func fetchWorkHistory(pageToken: String) async throws -> HistoryPage<WorkHistoryItem>
    func fetchRewardHistory(pageToken: String) async throws -> HistoryPage<RewardHistoryItem>
}

struct ConfiguredHistoryRepository: HistoryRepository {
    private struct PageRequest: Encodable {
        let pageSize = 20
        let pageToken: String
    }

    private struct WorkResponse: Decodable {
        let entries: [WorkEntryDTO]
        let nextPageToken: String

        private enum CodingKeys: String, CodingKey { case entries, nextPageToken }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            entries = try container.decodeIfPresent([WorkEntryDTO].self, forKey: .entries) ?? []
            nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken) ?? ""
        }
    }

    private struct WorkEntryDTO: Decodable {
        let session: SessionDTO
        let reward: RewardSummaryDTO?
    }

    private struct SessionDTO: Decodable {
        let id: String
        let status: String
        let startedAt: ProtoTimestamp
        let endedAt: ProtoTimestamp?
        let taskSnapshot: TaskSnapshotDTO?
        let durations: DurationsDTO?
    }

    private struct TaskSnapshotDTO: Decodable {
        let name: String
    }

    private struct DurationsDTO: Decodable {
        let activeMillis: ProtoJSONInt64?
        let workMillis: ProtoJSONInt64?
    }

    private struct RewardSummaryDTO: Decodable {
        let earnedSeconds: ProtoJSONInt64?
        let spentSeconds: ProtoJSONInt64?
        let discardedSeconds: ProtoJSONInt64?
    }

    private struct TransactionsResponse: Decodable {
        let transactions: [TransactionDTO]
        let nextPageToken: String

        private enum CodingKeys: String, CodingKey { case transactions, nextPageToken }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            transactions = try container.decodeIfPresent([TransactionDTO].self, forKey: .transactions) ?? []
            nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken) ?? ""
        }
    }

    private struct TransactionDTO: Decodable {
        let id: String
        let sessionId: String
        let type: String
        let amountSeconds: ProtoJSONInt64
        let balanceAfter: ProtoJSONInt64
        let occurredAt: ProtoTimestamp

        private enum CodingKeys: String, CodingKey { case id, sessionId, type, amountSeconds, balanceAfter, occurredAt }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            sessionId = try container.decode(String.self, forKey: .sessionId)
            type = try container.decode(String.self, forKey: .type)
            amountSeconds = try container.decode(ProtoJSONInt64.self, forKey: .amountSeconds)
            balanceAfter = try container.decodeIfPresent(ProtoJSONInt64.self, forKey: .balanceAfter)
                ?? ProtoJSONInt64(value: 0)
            occurredAt = try container.decode(ProtoTimestamp.self, forKey: .occurredAt)
        }
    }

    private let client: ConnectJSONClient

    init() throws {
        let projectURLText = MobileAppConfiguration.supabaseProjectURL ?? ""
        let publishableKey = MobileAppConfiguration.supabasePublishableKey ?? ""
        let apiBaseURLText = MobileAppConfiguration.connectAPIBaseURL ?? ""
        guard let projectURL = Self.validatedURL(projectURLText),
              !publishableKey.isEmpty,
              !publishableKey.localizedCaseInsensitiveContains("service_role"),
              !publishableKey.localizedCaseInsensitiveContains("secret"),
              let apiBaseURL = Self.validatedURL(apiBaseURLText) else {
            throw HistoryRepositoryError.invalidConfiguration
        }
        client = ConnectJSONClient(
            baseURL: apiBaseURL,
            tokenProvider: SupabaseAuthService(projectURL: projectURL, publishableKey: publishableKey)
        )
    }

    func fetchWorkHistory(pageToken: String = "") async throws -> HistoryPage<WorkHistoryItem> {
        let response: WorkResponse = try await client.call(
            service: "focus.v1.FocusService",
            method: "ListSessions",
            requestBody: PageRequest(pageToken: pageToken),
            responseType: WorkResponse.self
        )
        return HistoryPage(
            items: response.entries.map { entry in
                WorkHistoryItem(
                    id: entry.session.id,
                    taskName: entry.session.taskSnapshot?.name ?? "作業",
                    status: entry.session.status,
                    startedAt: entry.session.startedAt.date,
                    endedAt: entry.session.endedAt?.date,
                    activeSeconds: max(0, (entry.session.durations?.activeMillis?.value ?? 0) / 1000),
                    workSeconds: max(0, (entry.session.durations?.workMillis?.value ?? 0) / 1000),
                    earnedSeconds: entry.reward?.earnedSeconds?.value ?? 0,
                    spentSeconds: entry.reward?.spentSeconds?.value ?? 0,
                    discardedSeconds: entry.reward?.discardedSeconds?.value ?? 0
                )
            },
            nextPageToken: response.nextPageToken
        )
    }

    func fetchRewardHistory(pageToken: String = "") async throws -> HistoryPage<RewardHistoryItem> {
        let response: TransactionsResponse = try await client.call(
            service: "reward.v1.RewardService",
            method: "ListTransactions",
            requestBody: PageRequest(pageToken: pageToken),
            responseType: TransactionsResponse.self
        )
        return HistoryPage(
            items: response.transactions.map {
                RewardHistoryItem(
                    id: $0.id,
                    sessionID: $0.sessionId,
                    type: $0.type,
                    amountSeconds: $0.amountSeconds.value,
                    balanceAfterSeconds: $0.balanceAfter.value,
                    occurredAt: $0.occurredAt.date
                )
            },
            nextPageToken: response.nextPageToken
        )
    }

    private static func validatedURL(_ text: String) -> URL? {
        guard let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }
}

private struct ProtoJSONInt64: Decodable {
    let value: Int64

    init(value: Int64) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), let value = Int64(string) {
            self.value = value
        } else if let value = try? container.decode(Int64.self) {
            self.value = value
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a protobuf JSON int64")
        }
    }
}

private struct ProtoTimestamp: Decodable {
    let date: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) ?? Self.withoutFractionalSeconds.date(from: text) {
            self.date = date
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an RFC 3339 protobuf timestamp")
        }
    }

    private static let withoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum HistoryRepositoryError: Error, LocalizedError {
    case invalidConfiguration

    var errorDescription: String? {
        "Supabaseへのログイン状態とAPI設定を確認してください。"
    }
}
