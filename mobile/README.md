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
| 08 作業中ホーム | `Features/Home/HomeView.swift`, `Data/APIHomeRepository.swift`。`GetCurrentSession`、`GetBalance`、`GetRestrictionState`から計測時間、残高、制限要求と適用状態を取得。ホームタブを表示したアプリのforeground中は30秒ごとに再取得し、Desktopでの作業開始・一時停止・再開・終了を同期。アプリ復帰時にも即時取得し、画面を離れている間はポーリングしない。設定タブとScreen Time選択を共有し、端末に保存したApplicationTokenを表示。API再取得に失敗したときは前回表示値を残して古い情報だと警告し、古い制限状態をiOSへ再適用しない。小休憩へ進めるのは一時停止中だけ |
| 09 Shield | `Features/Restriction/RestrictionShieldPreview.swift`は画面案の静的プレビュー。実際のShieldはFamilyControlsの選択をManagedSettingsへ適用するとiOSが対象アプリ上に表示する。セッション状態との同期コードも実装済みだが、実機での表示確認は未完了 |
| 10 残高を使う | `Features/Usage/UsageReservationView.swift`。一時停止中の作業セッションに対して`ReserveUsageGrant`を呼び、利用枠を確保する。選択アプリのみを対象とし、通信失敗時は同じoperation IDで再試行する |
| 11 利用中 | 同ファイルの `ActiveUsageView`。DeviceActivityの1分単位イベントをApp Group経由で受け取り、`GetUsageGrant`／`ReportUsage`と制限状態報告で同期する。Monitor extensionとApp Groupsの署名・実機動作確認は未完了 |
| 12 設定 | `Features/Settings/SettingsView.swift`, `Data/MobileScreenTimeController.swift`, `Data/DeviceSettingsRepository.swift`。制限モードは「標準アプリ以外を制限」「指定したアプリのみ制限」の2つ。FamilyControlsの本人認可とFamilyActivityPickerによる制限対象・常時許可アプリ選択、制限モードの端末内保存、iPhoneの`RegisterDevice`と`GetRestrictionPolicy`／`UpdateRestrictionPolicy`同期を実装。Safariを常時許可に含めない案内があり、opaque tokenのため選択内容の名前はアプリ側で検証できない。実機動作は未確認。Debug接続設定は折りたたみ表示 |
| 13 グループ | `Features/Groups/GroupView.swift`, `Data/GroupRepository.swift`。認証付き`ListGroups`／`CreateGroup`／`CreateInvitation`／`AcceptInvitation`／`LeaveGroup`に接続。メンバー全員が7日・1回限りの招待リンクを共有でき、最終メンバー退出時はグループを削除する。招待は`rewardtime://invite?token=...`のアプリリンク。複数グループを切替表示し、メンバーの公開表示名とプロフィールアイコンを表示。作業開始の事実・時刻をグループ画面で30秒ごとに取得。APNs通知はbackendのOutboxから送信する |
| 履歴 | `Features/History/HistoryView.swift`, `Data/HistoryRepository.swift`。`ListSessions`で終了・中止済み作業と報酬要約を、`ListTransactions`で獲得・利用・破棄の台帳をページング表示 |
| 14 通知 | `Features/Notifications/NotificationSettingsView.swift`, `Data/NotificationEndpointRepository.swift`。各タブのヘッダー右上のベルから開く。iOS通知許可の実状態を取得し、APNs tokenを認証付きAPIへ登録・解除する。通知先登録の前に同一registration IDのiPhone Device登録を保証する。グループ作業開始の事実だけをbackend Outbox経由で配信する。実機配信にはApple Push entitlement・backendのAPNs資格情報が必要 |

08・09モックは、報酬を同じ作業セッションの小休憩に使い、終了・中止時に未使用分を破棄する仕様に更新した。FamilyControlsの認可・アプリ選択・Shield、iPhone登録、制限ポリシー同期、利用枠API、DeviceActivity monitor extensionを本番アプリ側に追加した。OSの監視イベントによる計測は1分単位。backendへは利用中画面を表示中に1分おき、アプリがforegroundへ戻った際にも同期する。設定タブへ戻った際は権限状態を更新し、端末設定をbackendへ再同期する。設定同期中に選択が変わった場合は最新設定も後続同期し、policy revision競合時は再取得して最大3回試行する。背景中の計測と期限後Shieldはextensionが行う。iOS Simulator向けDebugビルドは確認済み。App Groups共有、監視イベント、期限後の自動Shieldは未検証であり、実機受け入れが必要。履歴タブは作業と報酬のAPI履歴へ接続した。

backendには業務RPCのprotoとGo handlerがある。mobileは`URLSession + Codable`でConnect JSONを扱い、Supabase公式Swift SDKでメールOTPとKeychain管理のAuthセッションを扱う。初回未認証時はログイン画面を表示し、ログインを後回しにした場合も端末内設定を利用できる。起動時に保存済みAuth sessionがあれば`EnsureUser`／`GetMe`でbackend上の業務Userを確認し、成功するまでログイン済みAPI画面へ進まない。同期失敗時はエラー・再試行・端末内利用・別アカウントでのログインを表示する。ホーム・グループ・履歴では必要に応じてログインへ案内する。Debugではログイン画面・設定画面からSupabase Project URL、publishable/anon key、Connect API URLを入力する。Releaseではログイン／ログアウトを使い、接続値は`Info-Release.plist`へビルド時に組み込む。`Release.xcconfig`、git ignore対象の`Release.local.xcconfig`、接続値検証とSimulator Release build／Info.plist照合を行う`build-release-simulator.sh`を追加した。通常利用者にURLやキーを入力させる画面はReleaseに表示しない。値はアプリへ組み込まれるため、publishable/anon keyと公開可能なHTTPS API URLだけを設定する。secret keyやservice_role keyは設定しない。実際のProject値を含むlocal config、CI注入、実機Archive／署名・接続確認は未実施。Desktop・iPhoneは同じSupabase project／メールアカウント／backend環境で同じ業務Userへ対応する設計で、ペアリングコードは不要。iPhoneにbackend端末IDが保存されている場合、ログアウト時は`ListDevices`／`RevokeDevice`で端末を失効し、`DeleteNotificationEndpoint`で通知先を解除してregistration IDを破棄した後にAuthセッションを消す。通信失敗時はoperation ID・端末ID・versionを保存し、同一操作を再試行できる状態を保つため、ログアウトは中断する。実環境の新規・既存アカウントE2E、端末失効付きログアウト、Release値を使った認証・接続は未確認。`MockHomeRepository`はSwiftUI Preview専用。APNs token登録・解除、作業開始通知のOutbox・配信コードは実装済み。PC表示連携、Apple Push署名設定を伴う実機配信、本番の永続workerは未確認。

認証の確認は初回起動時のログイン画面、または設定タブの「アカウント接続」から行う。Debugでは開発者がProject URL、公開用キー、Connect API URLを入力する。Release値は`mobile/Release.local.xcconfig`へ設定し、`mobile/build-release-simulator.sh`でRelease Simulator buildと生成Info.plistの値を確認する。このlocal configはgit ignore対象である。実機Archiveでは同じRelease.xcconfigを使い、チーム署名を別途設定する。一般利用者向けの入力画面はReleaseに表示しない。Supabase URLとAPI URLにはHTTPSを指定する（Release build scriptはHTTPを拒否）。メールアドレスへ届いた数字コードを入力すると、Authセッション取得後に業務User登録・取得を試みる。iOS段階1では未登録メールからのAuthユーザー新規登録も許可し、登録済みメールも同じOTP導線を使う。Simulator testでは共通OTP routeと`create_user: true`、期限切れsessionのSupabase SDK自動refresh・新token保存をstub通信で確認した。Supabaseのメールテンプレートは数字OTP（`{{ .Token }}`）を送信する設定が必要。セッションはSupabase SDKのApple向け既定保存先で管理する。起動時にAuth sessionがある場合も`EnsureUser`／`GetMe`が成功するまでAPI利用画面へ進まず、失敗時は再試行・端末内利用・別アカウントでのログインを選べる。ログインを後回しにした後は、グループ・履歴・ホームのログイン案内から再開できる。実機でMac上のAPIに接続する場合は、Debug API URLへMacのLAN IPを指定し、backend側もLANから到達可能な設定で起動する必要がある。サービスロールキーやsecret keyは入力しない。

未ログイン時はメールコードを送る前に、同梱の10種類からプロフィールアイコンを選べる。コード認証後に選択IDを本人のUserへ保存し、設定タブから変更できる。画像本体は`RewardTime/Avatars.xcassets`へ同梱し、DBにはカタログIDだけを保存する。

Debugビルドのホームから「backendヘルスチェック」を開くと、指定URLの`GET /healthz`を確認できる。SimulatorからMac上のローカルbackendを確認する場合は既定値`http://127.0.0.1:8080`を使用する。iPhone実機からは、backend READMEの手順でComposeの公開先をMacのLAN IPv4に設定し、アプリのConnect API URLへ`http://<MacのLAN IPv4>:8080`を入力する。Debug構成だけローカルネットワーク接続を許可し、Release構成のATS設定は変更していない。ヘルスチェックは認証や業務データの読み書きを行わず、実API疎通を完了したことにはならない。

### DesktopとiPhoneの作業状態を確認する

両アプリで同じSupabase project・メールアカウントを使い、同じbackend databaseへ接続する。Simulatorは`127.0.0.1`、実機iPhoneはMacのLAN IPv4をAPI URLに使うが、どちらも同じMac上のbackendへ到達させる。Mobileをログイン済みのままホーム表示にしておくと、Desktopで作業を開始した状態をforeground中に最大30秒程度で再取得する。iPhoneをbackgroundへ移すと定期取得は止まり、foreground復帰時にすぐ再取得する。メール表示が一致してもSupabase projectが異なると別Auth subjectになり、サーバー上の作業状態は共有されない。

受け入れ確認は、DesktopとiPhoneの両方で同じメールOTPアカウントへログインし、Desktopで作業を開始して、iPhoneのホームに作業中状態が反映されることを確認する。30秒経過しても反映されない場合は、両アプリのログイン状態、Supabase projectの一致、同じMac backendへの接続、backendログの`GetCurrentSession` statusを照合する。`/healthz`成功だけでは認証・同一User・作業同期の証明にならない。認証subjectやtokenは画面・ログへ出さない。実Supabaseを使う2アプリのE2Eは未確認。

API回帰テストは`swift test --package-path mobile/RewardTimeTests`でmacOS host上にて実行する。iOS Simulatorでは`RewardTimeSimulatorTests` schemeを使い、端末失効API、Group API error分類、認証入口状態resolver、EnsureUser／GetMe同期とUpdateDisplayName／UpdateAvatarのRepository要求・応答契約、利用枠再試行エラー分類、Reserve／GetGrant／ReportUsage／予約operation照合のRepository契約を確認する。

```sh
xcodebuild test \
  -project mobile/ios-reward-time.xcodeproj \
  -scheme RewardTimeSimulatorTests \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO
```

初回ログイン画面とReleaseでの開発者向け接続欄の非表示を確認するUI testは別schemeで実行する。

```sh
xcodebuild test \
  -configuration Release \
  -project mobile/ios-reward-time.xcodeproj \
  -scheme RewardTimeUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO
```

Simulator `RewardTimeSimulatorTests`は`URLProtocol`による応答stubを使うため、local backend・Supabase・APNsの疎通確認とは別。iPhone 17 Simulator (iOS 27.0)で53件が通過し、Identity `EnsureUser`／`GetMe`／`UpdateAvatar`／`UpdateDisplayName`失敗時のRPC名とConnect code、Device登録・ポリシー読込／更新失敗時のRPC名表示とrevision競合再取得、サインアウト時の`ListDevices`／`RevokeDevice`／`DeleteNotificationEndpoint`失敗RPC名と同一operation再試行、端末失効、通知先登録／削除のAPI操作とエラー内のRPC名、operation IDを保持した応答喪失後の再試行、Homeの3 APIエラー時のRPC名表示とpartial snapshot抑止、Group API操作・作業開始フィードのerror案内と一覧refresh失敗後の前回データ保持、HistoryのRPC名付きエラー・一覧refresh失敗後の前回データ保持、初回未認証・同期失敗・認証済み・ローカル利用の入口状態、EnsureUser→GetMeの順序と失敗時の後続要求抑止、UpdateDisplayName／UpdateAvatarのpath／request field、利用枠API全5 RPCの失敗時RPC名表示と、予約結果不明時に同じoperation IDを保つ再試行、保存済みgrant同期またはbackground Home状態取得の失敗RPCをホームに表示し、再試行できること、OTPの`create_user: true`、OTP検証の`type: email`とsession保存、期限切れsession refresh、refresh通信断後のsession保持を検証する。別schemeの`RewardTimeUITests`は初回未ログイン画面のメール欄・ログイン後回し・接続未設定時のOTP送信無効状態と、Debug設定欄の表示（Debug）／非表示（Release）を確認する。2026-10-25にhost 45件、Simulator 53件、ログイン画面UI testをDebugで1件実行し、すべて通過した。OTP実送信・新規／既存ログイン・Desktop同一アカウントE2E、Release値を使った実機接続、端末失効付きログアウトは未確認。

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

### Release接続先

ReleaseアプリはURLやキーの入力画面を表示せず、ビルド時に`Info.plist`へ接続値を組み込む。環境値をソース管理へ入れないため、Releaseビルド前にローカル設定ファイルを作る。

```sh
cp mobile/Release.local.xcconfig.example mobile/Release.local.xcconfig
# Release.local.xcconfigを編集し、Supabase URL・publishable key・HTTPS Connect API URLを設定
mobile/build-release-simulator.sh
```

`Release.local.xcconfig`はgit ignore対象。xcconfigではURL中の`//`をコメントと誤認しないよう、雛形の`https:/$()/host`形式を保つ。publishable keyはアプリから取得可能な公開クライアント値で、service-role／secret keyは設定しない。`build-release-simulator.sh`は接続値の欠落・placeholder・HTTPS以外をビルド前に拒否し、Release Simulator appのInfo.plistに3値が正しく入ったことを値を表示せず確認する。この手順は接続設定のビルド検証で、実Supabase認証・backend接続やiPhone実機署名の確認ではない。実機Archiveでは同じ`mobile/Release.xcconfig`を使い、別途チームの署名設定を行う。

## 確認方法

- XcodeプロジェクトのSchemeとSimulatorを選び、ビルド・起動して対象画面を確認する。各画面のSwiftUI Previewでも状態を確認する。
- 変更に対応するユニットテストまたは手動確認を追加し、空状態・通信失敗・期限切れなど該当する状態を確認する。
- 実機制限の確認はシミュレータ画面確認と分け、[`poc/README.md`](../poc/README.md) の実機手順・記録に従う。
- Connect API transport、起動時認証分岐、APNs endpoint重複登録抑止の45件のユニットテストはSwift Packageで実行する。transport testsはBearer認証、Connect code、401／403、plain HTTP 404、REST Connect error、token欠落、通信断、timeout、JSON decode failureをmacOS host上で確認する。これらはiOS Simulator XCTestではなく、アプリのSimulator向けコンパイルは上の`xcodebuild`手順で別に確認する。Supabase SDK refresh testはSimulator上のstub応答を使用し、実Supabase接続は確認しない。

  ```sh
  swift test --package-path mobile/RewardTimeTests
  ```

## 未決事項

認証はiOS段階1でメールOTP・Supabase公式Swift SDKを選択した。OTPテンプレート／SMTP、環境別プロジェクト設定、stagingでのJWT検証、401時の再認証と停止アカウント表示は未確認。利用時間の計測・同期、制限モード、解除失敗時の返還、対応OS・配布条件も [`docs/spec/3.API仕様書.md`](../docs/spec/3.API仕様書.md) と要件資料の未決事項に従う。これらをmobile側だけで確定しない。
