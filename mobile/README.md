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
4. **API契約が確定した範囲を接続する**：APIクライアントとリポジトリを実装し、通信中・失敗・未同期を画面で区別する。認証方式など未決の契約をアプリ内で決めない。
5. **小休憩の利用フローを接続する**：PAUSED中の利用枠確保、利用状態表示、実利用の報告をAPI契約に沿って扱う。終了・中止時は未使用残高を破棄する。
6. **制限機能を独立して検証・接続する**：制限の要求状態とiPhoneでの適用確認を区別する。FamilyControls / ManagedSettings の実装・権限追加は、必要なPoCと配布条件を確認し、対象作業として合意してから行う。

## 依存の境界

標準のSwift / SwiftUIとFoundationを基本にする。iOS段階1のメールOTP認証にはSupabase公式Swift SDKを使う。その他のAPI通信は引き続き`URLSession + Codable`とし、追加パッケージを増やさない。

```text
SwiftUI画面
  ↓
画面状態・ユースケース
  ↓
HomeRepository（ホーム情報取得の境界）
  ├─ 仮データ実装（画面開発用）
  └─ API実装（契約確定後）

制限操作 → RestrictionController（境界のみ。OS連携はPoC後）
```

画面はHTTP通信やOS制限APIを直接呼ばない。APIのDTOと画面表示用モデルを分け、サーバー残高をiPhoneから直接書き換えない。仮データ実装は実APIの結果を偽装せず、開発用であることが分かる形にする。

## 現在の実装

`ios-reward-time.xcodeproj` にSwiftUIアプリを作成し、モック08〜14に対応する画面を配置した。値は仮データで、画面にはサンプルであることを表示する。

| モック | 実装場所・現在の動作 |
| --- | --- |
| 08 作業中ホーム | `Features/Home/HomeView.swift`。計測時間、最小時間までの残り、報酬残高、制限対象アプリ、適用状態を表示。小休憩へ進めるのは一時停止中だけ |
| 09 Shield | `Features/Restriction/RestrictionShieldPreview.swift`。見た目の静的プレビューのみ。OSのShield表示・アプリ制限は行わない。Debugビルドのホームから開ける |
| 10 残高を使う | `Features/Usage/UsageReservationView.swift`。時間を選べるが、確保API未接続のため残高は変更しない |
| 11 利用中 | 同ファイルの `ActiveUsageView`。モック値の表示のみ。残り時間の計測・再制限は行わない |
| 12 設定 | `Features/Settings/SettingsView.swift`。許可・制限モード・アプリ選択・端末情報を表示。端末設定を変える操作は未接続 |
| 13 グループ | `Features/Groups/GroupView.swift`。サンプルメンバーと作業開始履歴を表示。招待・退出は未接続 |
| 14 通知例 | `Features/Notifications/NotificationExamplesView.swift`。設定画面から開く通知例。通知送信はしない |

08モックの「作業を終了した後も残高を使える」ように読める箇所は、API仕様に合わせて「一時停止中のみ利用枠を確保できる」表示にしている。終了・中止時は未使用残高を破棄する。09の実ShieldはiOSが表示するOS画面であり、FamilyControls未接続の現状ではアプリから適用できない。Debugビルドから開けるのは静的な見た目のプレビューだけ。ホームのDebug用シナリオ選択で一時停止状態にすると10へ進め、10から11のサンプル表示を開ける。同じ選択メニューの「通信エラー」で失敗表示と再読み込み導線を確認できるが、実際の通信は発生しない。履歴タブは08モック内にタブ表示があるため置いているが、専用モックと履歴APIがないため説明用の空状態にしている。

backendには業務RPCのprotoとGo handlerがある。mobileは`URLSession + Codable`でConnect JSONを扱い、Supabase公式Swift SDKでメールOTPとKeychain管理のAuthセッションを扱う。Debug設定画面にSupabase Project URL、publishable/anon key、Connect API URLを入力すると、OTP認証後に`EnsureUser`と`GetMe`を呼び出せる。Supabase URL・キー・OTPメール設定、staging JWT検証は利用者のプロジェクト設定が必要で、まだ接続確認していない。Swift DTOのproto JSON対応・更新責任も未決（詳細は[開発フロー](../docs/spec/6.iOSクライアント開発フロー.md)）。そのためホームを含む業務データは引き続き`MockHomeRepository`から表示し、残高消費、OS制限、通知配信、グループ更新、履歴取得は実APIへ接続していない。

認証の確認はSimulatorまたは実機でアプリの「設定」タブを開き、「アカウント接続」にProject URL、公開用キー、Connect API URLを入力する。メールアドレスへ届いた数字コードを入力すると、Authセッション取得後に業務User登録・取得を試みる。iOS段階1では未登録メールからのAuthユーザー新規登録も許可する。Supabaseのメールテンプレートは数字OTP（`{{ .Token }}`）を送信する設定が必要。セッションはSupabase SDKのApple向け既定保存先で管理する。実機でMac上のAPIに接続する場合は、API URLへMacのLAN IPを指定し、backend側もLANから到達可能な設定で起動する必要がある。サービスロールキーやsecret keyは入力しない。

Debugビルドのホームから「backendヘルスチェック」を開くと、指定URLの`GET /healthz`を確認できる。SimulatorからMac上のローカルbackendを確認する場合は既定値`http://127.0.0.1:8080`を使用する。iPhone実機から確認する場合、backendのComposeはポートを`127.0.0.1`にのみ公開しているため現状のままでは接続できない。Debug構成だけローカルネットワーク接続を許可し、Release構成のATS設定は変更していない。ヘルスチェックは認証や業務データの読み書きを行わず、実API疎通を完了したことにはならない。

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
