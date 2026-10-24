import Foundation

enum DeviceSettingsSyncErrorMessage {
    static func describe(_ error: Error) -> String {
        guard let localizedError = error as? LocalizedError,
              let description = localizedError.errorDescription,
              !description.isEmpty
        else {
            return "端末設定を同期できません。時間をおいて再試行してください。"
        }
        return "端末設定を同期できませんでした: \(description)"
    }
}
