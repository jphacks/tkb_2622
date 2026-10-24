import AppKit
import CoreGraphics
import Foundation

private struct CaptureRecord: Encodable {
    let schemaVersion = "1"
    let source = "macos-native"
    let sampleStartedAt: String
    let observedAt: String
    let idleObservedAt: String
    let appID: String?
    let appName: String?
    let idleSeconds: Double?
    let browserName: String?
    let browserDomain: String?
    let tabID: String?
    let browserStatus: String
    let audible: Bool? = nil
    let lockState: Bool? = nil
    let sleepState: Bool? = nil
    let reasons: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case source
        case sampleStartedAt = "sample_started_at"
        case observedAt = "observed_at"
        case idleObservedAt = "idle_observed_at"
        case appID = "app_id"
        case appName = "app_name"
        case idleSeconds = "idle_seconds"
        case browserName = "browser_name"
        case browserDomain = "browser_domain"
        case tabID = "tab_id"
        case browserStatus = "browser_status"
        case audible
        case lockState = "lock_state"
        case sleepState = "sleep_state"
        case reasons
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(source, forKey: .source)
        try container.encode(sampleStartedAt, forKey: .sampleStartedAt)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(idleObservedAt, forKey: .idleObservedAt)
        try container.encode(appID, forKey: .appID)
        try container.encode(appName, forKey: .appName)
        try container.encode(idleSeconds, forKey: .idleSeconds)
        try container.encode(browserName, forKey: .browserName)
        try container.encode(browserDomain, forKey: .browserDomain)
        try container.encode(tabID, forKey: .tabID)
        try container.encode(browserStatus, forKey: .browserStatus)
        try container.encode(audible, forKey: .audible)
        try container.encode(lockState, forKey: .lockState)
        try container.encode(sleepState, forKey: .sleepState)
        try container.encode(reasons, forKey: .reasons)
    }
}

private enum BrowserKind {
    case chrome
    case safari

    var name: String {
        switch self {
        case .chrome:
            return "Chrome"
        case .safari:
            return "Safari"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .chrome:
            return "com.google.Chrome"
        case .safari:
            return "com.apple.Safari"
        }
    }

    var tabReference: String {
        switch self {
        case .chrome:
            return "active tab"
        case .safari:
            return "current tab"
        }
    }
}

private struct BrowserReadOutcome {
    let status: String
    let domain: String?
    let tabID: String?
    let reason: String?

    static func failure(status: String, reason: String) -> BrowserReadOutcome {
        BrowserReadOutcome(status: status, domain: nil, tabID: nil, reason: reason)
    }
}

private enum CollectorError: Error {
    case invalidArguments
}

private func timestampString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func captureIdleSeconds() -> (seconds: Double?, observedAt: String) {
    let anyInputEvent = CGEventType(rawValue: UInt32.max)!
    let rawSeconds = CGEventSource.secondsSinceLastEventType(
        .combinedSessionState,
        eventType: anyInputEvent
    )
    let observedAt = timestampString(Date())

    guard rawSeconds.isFinite, rawSeconds >= 0 else {
        return (nil, observedAt)
    }
    return (rawSeconds, observedAt)
}

private func supportedBrowser(for bundleIdentifier: String?) -> BrowserKind? {
    switch bundleIdentifier {
    case "com.google.Chrome":
        return .chrome
    case "com.apple.Safari":
        return .safari
    default:
        return nil
    }
}

private func isBrowserApplication(_ application: NSRunningApplication) -> Bool {
    let bundleIdentifier = application.bundleIdentifier?.lowercased() ?? ""
    let localizedName = application.localizedName?.lowercased() ?? ""
    let identity = "\(bundleIdentifier) \(localizedName)"

    let browserMarkers = [
        "browser",
        "chrome",
        "chromium",
        "safari",
        "firefox",
        "mozilla",
        "edge",
        "brave",
        "vivaldi",
        "opera",
        "orion",
        "duckduckgo",
        "zen",
        "waterfox",
        "floorp",
        "librewolf",
        "yandex",
        "sidekick",
        "sigmaos",
        "comet"
    ]
    if browserMarkers.contains(where: identity.contains) {
        return true
    }

    let isArcBrowser = localizedName == "arc"
        || localizedName.contains("arc browser")
        || bundleIdentifier.contains(".arc.")
        || bundleIdentifier.hasSuffix(".arc")
    return isArcBrowser
}

private func browserStatusForAppleScriptError(_ errorCode: Int?) -> BrowserReadOutcome {
    switch errorCode {
    case -1743:
        return .failure(status: "permission_denied", reason: "browser_automation_permission_denied")
    case -1712:
        return .failure(status: "timeout", reason: "browser_automation_timeout")
    case -1728:
        return .failure(status: "no_window", reason: "browser_no_window")
    default:
        return .failure(status: "unknown_error", reason: "browser_automation_unknown_error")
    }
}

private func readActiveTab(from browser: BrowserKind) -> BrowserReadOutcome {
    // Safariの公開tab定義には永続IDがないため、取得できないIDを補完しない。
    let identifierExpression = browser == .chrome ? "id of activeTab as text" : "\"\""
    let scriptSource = """
    with timeout of 3 seconds
        tell application id "\(browser.bundleIdentifier)"
            set activeTab to \(browser.tabReference) of front window
            set tabURL to URL of activeTab as text
            set tabIdentifier to \(identifierExpression)
            return {tabURL, tabIdentifier}
        end tell
    end timeout
    """

    guard let script = NSAppleScript(source: scriptSource) else {
        return .failure(status: "unknown_error", reason: "browser_automation_unknown_error")
    }

    var errorDictionary: NSDictionary?
    let result = script.executeAndReturnError(&errorDictionary)
    if let errorDictionary {
        let errorCode = (errorDictionary["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue
        return browserStatusForAppleScriptError(errorCode)
    }

    guard result.numberOfItems >= 2,
          let rawURL = result.atIndex(1)?.stringValue else {
        return .failure(status: "unknown_error", reason: "browser_result_unavailable")
    }

    let rawTabID = result.atIndex(2)?.stringValue
    let components = URLComponents(string: rawURL)
    let scheme = components?.scheme?.lowercased()
    let parsedHost = (scheme == "http" || scheme == "https") ? components?.host?.lowercased() : nil
    let domain = parsedHost.flatMap { $0.isEmpty ? nil : $0 }
    return BrowserReadOutcome(
        status: "ok",
        domain: domain,
        tabID: rawTabID.flatMap { $0.isEmpty ? nil : $0 },
        reason: domain == nil ? "browser_domain_unavailable" : nil
    )
}

private func sameForegroundApplication(
    before: NSRunningApplication?,
    after: NSRunningApplication?
) -> Bool {
    guard let before, let after else {
        return before == nil && after == nil
    }
    return before.processIdentifier == after.processIdentifier
        && before.bundleIdentifier == after.bundleIdentifier
}

private func captureRecord() -> CaptureRecord {
    let sampleStartedAt = timestampString(Date())
    let foregroundBefore = NSWorkspace.shared.frontmostApplication
    let idle = captureIdleSeconds()
    var reasons = [
        "audible_not_exposed_by_standard_applescript",
        "lock_state_not_detected",
        "sleep_state_not_detected"
    ]

    if idle.seconds == nil {
        reasons.append("idle_unavailable")
    }
    if foregroundBefore == nil {
        reasons.append("foreground_unavailable")
    }

    let appID = foregroundBefore?.bundleIdentifier
    let appName = foregroundBefore?.localizedName
    var browserName: String?
    var browserDomain: String?
    var tabID: String?
    var browserStatus = "not_applicable"

    if let foregroundBefore {
        if let browser = supportedBrowser(for: appID) {
            browserName = browser.name
            let outcome = readActiveTab(from: browser)
            browserStatus = outcome.status
            browserDomain = outcome.domain
            tabID = outcome.tabID
            if let reason = outcome.reason {
                reasons.append(reason)
            }
        } else if isBrowserApplication(foregroundBefore) {
            browserName = appName ?? appID
            browserStatus = "unsupported"
            reasons.append("browser_unsupported")
        }
    }

    let foregroundAfter = NSWorkspace.shared.frontmostApplication
    if !sameForegroundApplication(before: foregroundBefore, after: foregroundAfter) {
        browserDomain = nil
        tabID = nil
        browserStatus = "foreground_changed"
        reasons.append("foreground_changed")
    }

    return CaptureRecord(
        sampleStartedAt: sampleStartedAt,
        observedAt: timestampString(Date()),
        idleObservedAt: idle.observedAt,
        appID: appID,
        appName: appName,
        idleSeconds: idle.seconds,
        browserName: browserName,
        browserDomain: browserDomain,
        tabID: tabID,
        browserStatus: browserStatus,
        reasons: reasons
    )
}

private func parseInterval(from arguments: [String]) throws -> TimeInterval? {
    guard arguments.count > 1 else {
        return nil
    }

    if arguments.count == 2, arguments[1] == "--once" {
        return nil
    }

    guard arguments.count == 3, arguments[1] == "--interval",
          let interval = Double(arguments[2]), interval.isFinite, interval > 0 else {
        throw CollectorError.invalidArguments
    }
    return interval
}

private func writeUsageError() {
    let message = "Usage: native-collector [--once | --interval <seconds>]\n"
    FileHandle.standardError.write(Data(message.utf8))
}

private func emitJSONLine(_ record: CaptureRecord) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

    do {
        var data = try encoder.encode(record)
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
        fflush(stdout)
    } catch {
        FileHandle.standardError.write(Data("JSON serialization failed\n".utf8))
    }
}

private func main() -> Int32 {
    let interval: TimeInterval?
    do {
        interval = try parseInterval(from: CommandLine.arguments)
    } catch {
        writeUsageError()
        return 2
    }

    repeat {
        emitJSONLine(captureRecord())
        guard let interval else {
            return 0
        }
        Thread.sleep(forTimeInterval: interval)
    } while true
}

exit(main())
