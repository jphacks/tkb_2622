# iOSアプリ開発

## 位置づけ

このディレクトリを本番向けiOSアプリのSwift / SwiftUI実装場所とする。画面のHTMLモックは [`docs/UI/`](../docs/UI/) にあり、実機での技術検証用アプリは [`poc/ios-reward-time/`](../poc/ios-reward-time/) に分けて置く。

画面の見た目はモックを参考にするが、残高・セッション・利用枠などの業務動作は [`docs/spec/3.API仕様書.md`](../docs/spec/3.API仕様書.md) と [`docs/spec/4.ドメインモデル定義.md`](../docs/spec/4.ドメインモデル定義.md) を正とする。モックと仕様に食い違いがある場合、実装側で解釈して埋めず、モックまたは仕様を更新してから着手する。

バックエンドAPI完成後の接続順、開始条件、mobile・backend間の未決事項は [`docs/spec/6.iOSクライアント開発フロー.md`](../docs/spec/6.iOSクライアント開発フロー.md) を参照する。

## 進め方

一度に全画面を作らず、動作を確認できる小さな縦切りで進める。

1. **モック・仕様の対応を確認する**：対象画面、対応要件、状態ごとの表示、未決事項を [`docs/UI/README.md`](../docs/UI/README.md) で確認する。
2. **アプリの土台を作る**：SwiftUIの起動・画面遷移と、画面が依存する状態・データの境界を用意する。
3. **ホーム画面を仮データで表示する**：セッション状態、残高、制限状態を読み取り専用で表示する。仮データはリポジトリ経由で渡し、後から通信実装に置き換えられるようにする。
4. **API契約が確定した範囲を接続する**：`APIHomeRepository` は現行proto案の読み取りAPIを呼び、session IDの食い違いを検出する。Connect DTOとstagingの実データ確認、版の整合規則は引き続き確認する。
5. **小休憩の利用フローを接続する**：PAUSED中の利用枠確保、利用状態表示、実利用の報告をAPI契約に沿って扱う。終了・中止時は未使用残高を破棄する。
6. **制限機能を独立して検証・接続する**：制限の要求状態とiPhoneでの適用確認を区別する。設定画面で本人認可・対象アプリ選択を行い、制限ポリシーをbackendと同期する。利用枠APIとDeviceActivity monitor extensionも接続済みだが、Screen Timeの許可、App Groupsの署名設定、実機での監視・期限動作は別途確認する。

## 依存の境界

標準のSwift / SwiftUIとFoundationを基本にする。iOS段階1のメールOTP認証にはSupabase公式Swift SDKを使う。その他のAPI通信は引き続き`URLSession + Codable`とし、追加パッケージを増やさない。

```text
SwiftUI画面
  ↓
画面状態・ユースケース
  ↓
HomeRepository（ホーム情報取得の境界）
  ├─ API実装（通常起動）
  └─ 仮データ実装（SwiftUI Previewのみ）

Screen Time → MobileScreenTimeController / DeviceActivityMonitorExtension
```

画面はHTTP通信やOS制限APIを直接呼ばない。APIのDTOと画面表示用モデルを分け、サーバー残高をiPhoneから直接書き換えない。仮データ実装は実APIの結果を偽装せず、開発用であることが分かる形にする。

## 現在の実装

`ios-reward-time.xcodeproj` にSwiftUIアプリを作成し、モック08〜14を参照する画面を配置した。通常起動はAPIへ接続し、設定がない場合や接続失敗時はエラーを表示する。サンプルRepositoryはSwiftUI Preview専用で、アプリ画面から切り替える操作はない。

| モック | 実装場所・現在の動作 |
| --- | --- |
| 08 作業中ホーム | `Features/Home/HomeView.swift`, `Data/APIHomeRepository.swift`。`GetCurrentSession`、`GetBalance`、`GetRestrictionState`から計測時間、残高、制限要求と適用状態を取得。設定タブとScreen Time選択を共有し、端末に保存したApplicationTokenを表示。API接続失敗時はエラーと再読み込みを表示。小休憩へ進めるのは一時停止中だけ |
| 09 Shield | `Features/Restriction/RestrictionShieldPreview.swift`は画面案の静的プレビュー。実際のShieldはFamilyControlsの選択をManagedSettingsへ適用するとiOSが対象アプリ上に表示する。セッション状態との同期コードも実装済みだが、実機での表示確認は未完了 |
| 10 残高を使う | `Features/Usage/UsageReservationView.swift`。一時停止中の作業セッションに対して`ReserveUsageGrant`を呼び、利用枠を確保する。選択アプリのみを対象とし、通信失敗時は同じoperation IDで再試行する |
| 11 利用中 | 同ファイルの `ActiveUsageView`。DeviceActivityの1分単位イベントをApp Group経由で受け取り、`GetUsageGrant`／`ReportUsage`と制限状態報告で同期する。Monitor extensionとApp Groupsの署名・実機動作確認は未完了 |
| 12 設定 | `Features/Settings/SettingsView.swift`, `Data/MobileScreenTimeController.swift`, `Data/DeviceSettingsRepository.swift`。FamilyControlsの本人認可とFamilyActivityPickerによる制限対象・常時許可アプリ選択、制限モードの端末内保存、iPhoneの`RegisterDevice`と`GetRestrictionPolicy`／`UpdateRestrictionPolicy`同期を実装。常時許可アプリは両モードのShield・利用時間計測対象から除外する。Safariを選ばないよう案内するが、opaque tokenのため選択内容の名前はアプリ側で検証できない。実機動作は未確認 |
| 13 グループ | `Features/Groups/GroupView.swift`, `Data/GroupRepository.swift`。認証付き`ListGroups`／`CreateGroup`／`CreateInvitation`／`AcceptInvitation`／`LeaveGroup`に接続。メンバー全員が7日・1回限りの招待リンクを共有でき、最終メンバー退出時はグループを削除する。招待は`rewardtime://invite?token=...`のアプリリンク。複数グループを切替表示し、本人の公開表示名を表示。作業開始の事実・時刻をグループ画面で30秒ごとに取得。PC表示・APNs配信は未接続 |
| 履歴 | `Features/History/HistoryView.swift`, `Data/HistoryRepository.swift`。`ListSessions`で終了・中止済み作業と報酬要約を、`ListTransactions`で獲得・利用・破棄の台帳をページング表示 |
| 14 通知設定 | `Features/Notifications/NotificationSettingsView.swift`。iOS通知許可の実状態を取得し、未決定時の許可要求・拒否後の設定画面への誘導を行う。APNs登録・配信は未接続 |

08・09モックは、報酬を同じ作業セッションの小休憩に使い、終了・中止時に未使用分を破棄する仕様に更新した。FamilyControlsの認可・アプリ選択・Shield、iPhone登録、制限ポリシー同期、利用枠API、DeviceActivity monitor extensionを本番アプリ側に追加した。OSの監視イベントによる計測は1分単位。backendへは利用中画面を表示中に1分おき、アプリがforegroundへ戻った際にも同期する。設定タブへ戻った際は権限状態を更新し、端末設定をbackendへ再同期する。設定同期中に選択が変わった場合は最新設定も後続同期し、policy revision競合時は再取得して最大3回試行する。背景中の計測と期限後Shieldはextensionが行う。iOS Simulator向けDebugビルドは確認済み。App Groups共有、監視イベント、期限後の自動Shieldは未検証であり、実機受け入れが必要。履歴タブは作業と報酬のAPI履歴へ接続した。

backendには業務RPCのprotoとGo handlerがある。mobileは`URLSession + Codable`でConnect JSONを扱い、Supabase公式Swift SDKでメールOTPとKeychain管理のAuthセッションを扱う。初回未認証時はログイン画面を表示し、ログインを後回しにした場合も端末内設定を利用できる。ホーム・グループ・履歴では必要に応じてログインへ案内する。Debugではログイン画面・設定画面からSupabase Project URL、publishable/anon key、Connect API URLを入力する。Releaseではログイン／ログアウトを使い、接続先は`Info-Release.plist`が参照する`SUPABASE_PROJECT_URL`、`SUPABASE_PUBLISHABLE_KEY`、`CONNECT_API_BASE_URL`のBuild Settings値から読む。すべてのAPI repositoryがこの共通設定を使う。値はアプリへ組み込まれるため、publishable/anon keyと公開可能なHTTPS API URLだけを設定する。secret keyやservice_role keyは設定しない。Supabase URL・キー・OTPメール設定、staging JWT検証は利用者のプロジェクト設定が必要で、Release環境の接続確認は未完了。`MockHomeRepository`はSwiftUI Preview専用。グループ開始フィードAPIはbackendに追加済みで、PC画面表示・iPhoneのAPNs通知は未接続。

認証の確認は初回起動時のログイン画面、または設定タブの「アカウント接続」から行う。DebugではProject URL、公開用キー、Connect API URLを入力する。ReleaseではXcodeのRewardTime targetのRelease Build Settingsへ`SUPABASE_PROJECT_URL`、`SUPABASE_PUBLISHABLE_KEY`、`CONNECT_API_BASE_URL`をUser-Defined設定として追加し、アプリをビルドする。Supabase URLとAPI URLにはHTTPSを指定する（ReleaseはHTTP接続を拒否）。メールアドレスへ届いた数字コードを入力すると、Authセッション取得後に業務User登録・取得を試みる。iOS段階1では未登録メールからのAuthユーザー新規登録も許可する。Supabaseのメールテンプレートは数字OTP（`{{ .Token }}`）を送信する設定が必要。セッションはSupabase SDKのApple向け既定保存先で管理する。ログインを後回しにした後は、グループ・履歴・ホームのログイン案内から再開できる。実機でMac上のAPIに接続する場合は、Debug API URLへMacのLAN IPを指定し、backend側もLANから到達可能な設定で起動する必要がある。サービスロールキーやsecret keyは入力しない。

Debugビルドのホームから「backendヘルスチェック」を開くと、指定URLの`GET /healthz`を確認できる。SimulatorからMac上のローカルbackendを確認する場合は既定値`http://127.0.0.1:8080`を使用する。iPhone実機からは、backend READMEの手順でComposeの公開先をMacのLAN IPv4に設定し、アプリのConnect API URLへ`http://<MacのLAN IPv4>:8080`を入力する。Debug構成だけローカルネットワーク接続を許可し、Release構成のATS設定は変更していない。ヘルスチェックは認証や業務データの読み書きを行わず、実API疎通を完了したことにはならない。

## ソース構成

```text
mobile/
├── ios-reward-time.xcodeproj/
└── RewardTime/
    ├── RewardTimeApp.swift
    ├── Domain/MobileHomeSnapshot.swift
    ├── Data/HomeRepository.swift
    └── Features/
        ├── RootTabView.swift
        ├── Shared/AppTheme.swift
        ├── Home/HomeView.swift, HomeViewModel.swift
        ├── Usage/UsageReservationView.swift
        ├── Restriction/RestrictionShieldPreview.swift
        ├── Settings/SettingsView.swift, AuthenticationSettingsSection.swift
        ├── Groups/GroupView.swift
        ├── Notifications/NotificationExamplesView.swift
        └── History/HistoryView.swift
```

## ビルドと起動

Schemeは `RewardTime`。Xcodeで `mobile/ios-reward-time.xcodeproj` を開き、iOS Simulatorを選んで実行する。CLIでは次のようにSimulator向けビルドを行える。

```sh
xcodebuild \
  -project mobile/ios-reward-time.xcodeproj \
  -scheme RewardTime \
  -destination 'generic/platform=iOS Simulator' \
  -clonedSourcePackagesDirPath /private/tmp/tkb2622-supabase-packages \
  -derivedDataPath /private/tmp/tkb2622-mobile-deriveddata \
  CODE_SIGNING_ALLOWED=NO \
  build
```

プロジェクトのiOS Deployment Targetは現時点で16.0に仮設定している。対応OSの正式決定時に見直す。Bundle Identifierも開発用の仮値であり、署名・実機配布前にチームの設定へ置き換える。

## 確認方法

- XcodeプロジェクトのSchemeとSimulatorを選び、ビルド・起動して対象画面を確認する。各画面のSwiftUI Previewでも状態を確認する。
- 変更に対応するユニットテストまたは手動確認を追加し、空状態・通信失敗・期限切れなど該当する状態を確認する。
- 実機制限の確認はシミュレータ画面確認と分け、[`poc/README.md`](../poc/README.md) の実機手順・記録に従う。

## 未決事項

認証はiOS段階1でメールOTP・Supabase公式Swift SDKを選択した。OTPテンプレート／SMTP、環境別プロジェクト設定、stagingでのJWT検証、401時の再認証と停止アカウント表示は未確認。利用時間の計測・同期、制限モード、解除失敗時の返還、対応OS・配布条件も [`docs/spec/3.API仕様書.md`](../docs/spec/3.API仕様書.md) と要件資料の未決事項に従う。これらをmobile側だけで確定しない。
