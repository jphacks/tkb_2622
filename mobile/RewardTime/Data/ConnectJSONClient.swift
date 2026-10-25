import Foundation

protocol AccessTokenProviding {
    func accessToken() async throws -> String?
}

struct ConnectJSONClient {
    enum ClientError: Error {
        case missingAccessToken
        case tokenProviderFailed(Error)
        case invalidResponse
        case httpStatus(Int)
        case connect(code: String)
        case unexpectedHealthStatus(String)
    }

    private struct ConnectErrorResponse: Decodable {
        let code: String
    }

    private struct HealthResponse: Decodable {
        let status: String
    }

    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: any AccessTokenProviding

    init(
        baseURL: URL,
        session: URLSession = .shared,
        tokenProvider: any AccessTokenProviding
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func checkHealth() async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("healthz"))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ClientError.httpStatus(response.statusCode)
        }

        let health = try JSONDecoder().decode(HealthResponse.self, from: data)
        guard health.status == "ok" else {
            throw ClientError.unexpectedHealthStatus(health.status)
        }
        return health.status
    }

    func call<Request: Encodable, Response: Decodable>(
        service: String,
        method: String,
        requestBody: Request,
        responseType: Response.Type
    ) async throws -> Response {
        let accessToken: String?
        do {
            accessToken = try await tokenProvider.accessToken()
        } catch {
            throw ClientError.tokenProviderFailed(error)
        }
        guard let accessToken, !accessToken.isEmpty else {
            throw ClientError.missingAccessToken
        }

        let endpoint = baseURL
            .appendingPathComponent(service)
            .appendingPathComponent(method)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            if let connectError = try? JSONDecoder().decode(ConnectErrorResponse.self, from: data) {
                throw ClientError.connect(code: connectError.code)
            }
            throw ClientError.httpStatus(response.statusCode)
        }
        return try JSONDecoder().decode(responseType, from: data)
    }

    func get<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        responseType: Response.Type
    ) async throws -> Response {
        let accessToken: String?
        do {
            accessToken = try await tokenProvider.accessToken()
        } catch {
            throw ClientError.tokenProviderFailed(error)
        }
        guard let accessToken, !accessToken.isEmpty else {
            throw ClientError.missingAccessToken
        }

        let endpoint = path.split(separator: "/").reduce(baseURL) {
            $0.appendingPathComponent(String($1))
        }
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw ClientError.invalidResponse
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw ClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            if let connectError = try? JSONDecoder().decode(ConnectErrorResponse.self, from: data) {
                throw ClientError.connect(code: connectError.code)
            }
            throw ClientError.httpStatus(response.statusCode)
        }
        return try JSONDecoder().decode(responseType, from: data)
    }
}

extension ConnectJSONClient.ClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAccessToken:
            return "ログインセッションがありません。再ログインしてください。"
        case .tokenProviderFailed(let underlying):
            let detail = (underlying as? LocalizedError)?.errorDescription
                ?? underlying.localizedDescription
            return "ログインセッションを更新できません。Supabaseへの接続を確認してください。(アクセストークン取得: \(detail))"
        case .invalidResponse:
            return "APIから不正な応答を受け取りました。"
        case .httpStatus(let status):
            return "APIがHTTP \(status)を返しました。"
        case .connect(let code) where code == "unauthenticated":
            return "APIがアクセストークンを受け付けませんでした。APIのSUPABASE_JWT_ISSUERとアプリのProject URLが同じプロジェクトか確認してください。(unauthenticated)"
        case .connect(let code):
            return "APIがエラーを返しました。(\(code))"
        case .unexpectedHealthStatus(let status):
            return "APIの状態が想定外です。(\(status))"
        }
    }
}
