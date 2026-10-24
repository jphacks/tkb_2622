import Foundation

enum GroupAPIErrorMessage {
    enum Operation: String {
        case listGroups = "ListGroups"
        case workStartFeed = "GET /v1/group/work-starts"
        case createGroup = "CreateGroup"
        case createInvitation = "CreateInvitation"
        case acceptInvitation = "AcceptInvitation"
        case leaveGroup = "LeaveGroup"
    }

    static func describe(_ error: Error) -> String {
        if let clientError = error as? ConnectJSONClient.ClientError {
            return describe(clientError)
        }
        return (error as? LocalizedError)?.errorDescription
            ?? "グループAPIへ接続できません。API URLとbackendの稼働状態を確認してください。"
    }

    static func describe(_ error: Error, operation: Operation) -> String {
        let detail: String
        if operation == .acceptInvitation,
           let clientError = error as? ConnectJSONClient.ClientError,
           case .connect(code: "failed_precondition") = clientError {
            detail = "招待リンクは期限切れか、すでに使用されています。新しいリンクを発行してもらってください (failed_precondition)。"
        } else {
            detail = describe(error)
        }
        return "\(detail) (API: \(operation.rawValue))"
    }

    static func describe(_ error: ConnectJSONClient.ClientError) -> String {
        switch error {
        case .httpStatus(404), .connect(code: "unimplemented"):
            return "接続先backendにグループAPIがありません。backendを最新版に更新して再起動してください。"
        case .connect(code: "internal"):
            return "backend内部エラーです (internal)。APIログとmigration適用状況を確認してください。"
        case .connect(code: "failed_precondition"):
            return "業務User登録が未完了です。設定タブでアカウント接続を再確認してください。"
        case .connect(code: "unauthenticated"):
            return "ログインセッションが確認できません (unauthenticated)。設定タブから再ログインしてください。"
        case .connect(code: "not_found"):
            return "グループまたはユーザー情報が見つかりません (not_found)。ログイン状態とグループ一覧を再確認してください。"
        case .connect(code: "permission_denied"):
            return "このグループの情報を読み取る権限がありません (permission_denied)。参加状態を確認してください。"
        default:
            return error.errorDescription
                ?? "グループAPIへ接続できません。API URLとbackendの稼働状態を確認してください。"
        }
    }
}
