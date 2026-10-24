# Mobile APIエラー安定化 作業リスト

## 目的

時間が限られているため、mobileのAPIエラーを優先して再現・修正する。ユニットテストを追加し、Simulator向けアプリbuildと分けて実行する。Simulator内でのXCTest実行targetは今後整備し、仕様・調査結果・未決事項をこの資料と関連資料へ反映する。

作業ブランチは`fix/mobile-api-stability`。作業単位でローカルコミットし、pushしない。

## 初回調査で確認した現状

- `RootTabView`は保存済みSupabase sessionを復元し、有効なら起動時のログイン画面を省略する。sessionがなく、ログインを後回しにした記録もなければ歓迎／ログイン画面を出す。
- Mobile／DesktopともメールOTPを使い、Mobileは新規Auth user作成を許可する。OTP成功後、Mobileは`EnsureUser`と`GetMe`を呼び、Desktopも認証後に業務Userの確認を行う。同じSupabase project・backend環境・アカウントであれば同じsubjectから同じ業務Userへ対応する設計で、端末ペアリングコードはない。
- Mobile Debugでは開発者向け設定へProject URL・publishable key・Connect API URLを保存する。ReleaseではInfo.plistがBuild Settings値を読む構造だが、現行Xcode projectに3値のRelease設定を渡す`.xcconfig`／CI注入がないため、Release配布設定は未完了。通常利用者へ手入力させない構造自体はあるが、Releaseビルドへ環境別公開値を設定する作業が必要。Desktopも起動時の`FOCUS_LINK_*`環境変数を読むため、配布時の環境設定注入は未整備。
- Desktop／Mobileは同じSupabase project・メールOTPアカウント・backend環境を使えば、同じJWT subjectから同じ業務Userへ対応する。新規Auth user作成と既存Auth userのOTPログインを両クライアントで許可し、ペアリングコードは使わない。実環境での新規／既存・環境不一致を含むE2Eは未実施。
- 認証と業務User同期は別段階。`RootTabView`は起動時に`EnsureUser`／`GetMe`成功を要求する。監査で、設定画面からの認証状態変更通知がsessionの有無だけでauthenticatedへ切り替える経路を発見したため、通知後もRoot側で同期を再実行するよう修正した。失敗時は同期エラー・再試行・端末内利用・別アカウントログインを表示する。入口状態のresolver testはあるが、SwiftUI rootの通知連携と実backend復旧はSimulator受け入れ待ち。
- Mobileは`ConnectJSONClient`の`URLSession`を注入できる。`mobile/RewardTimeTests/Package.swift`とXCTestがあり、macOS host上でAPI通信・起動状態・通知登録ゲートの7件が通過した。iOS Simulator XCTest targetは未整備だが、アプリのSimulator向けbuildは成功した。通知登録は成功済み同一tokenの通常再読込を抑止し、並行要求をまとめ、手動同期・認証変更・APNs token受信では再試行できる。tokenそのものは重複抑止キーとして保存しない。
- 現時点のRepository API一覧（呼び出し存在の確認まで。成功応答・DTO互換・画面ごとのretryは引き続き検証）：

| 画面／目的 | 実装API経路 | 確認状況 |
| --- | --- | --- |
| 起動・アカウント | Supabase OTP／refresh、Identity `EnsureUser`・`GetMe`・`UpdateDisplayName`・`UpdateAvatar` | 起動時業務User同期とAuth状態の分離を要確認 |
| Home | Focus `GetCurrentSession`、Reward `GetBalance`、Restriction `GetRestrictionState` | 3 API間のsession ID／version整合・部分失敗時の表示を要確認 |
| Groups | Group `ListGroups`・`CreateGroup`・`CreateInvitation`・`AcceptInvitation`・`LeaveGroup`、REST `v1/group/work-starts` | 作成・更新後reload、空状態・エラー状態を要確認 |
| History | Focus `ListSessions`、Reward `ListTransactions` | ページング・片方だけの失敗・reloadを要確認 |
| 設定・制限 | Identity `RegisterDevice`、Restriction `GetRestrictionPolicy`・`UpdateRestrictionPolicy`・`GetRestrictionState`／`ReportRestrictionState` | revision競合・再試行を要確認 |
| 利用枠 | Restriction `ReserveUsageGrant`・`GetUsageGrant`・`ReportUsage`・`GetRestrictionOperation` | 再起動・応答喪失・再試行の重複防止を要確認 |
| 通知 | Identity `RegisterNotificationEndpoint`・`DeleteNotificationEndpoint` | APNs token／認証／DB失敗を分離して再現。過去ログにはregister時の`internal`とSQLSTATE 2201Bがあるが、現ブランチでの再発は未確認 |

### 既知のエラー報告と再現状況

| 報告 | 現在の証拠 | 次の切り分け |
| --- | --- | --- |
| 通知画面の再読込時などにAPI error `not_found`／`internal` | SQLSTATE 2201Bはmigration 00012のAPNs token regex制約で発生した。00014がregexを修正し、今回の読み取り確認でlocal DBはversion 14まで適用済み。利用可能なAPI logには36秒間にregister要求9件があるが、対応するoperation failed行はなく、現在の失敗は再現していない | 成功済み同一tokenの重複要求を抑止するXCTestを追加済み。`not_found`が端末未登録か別原因かは、次の再発時に時刻・画面・Connect code・サーバー失敗operationを対応づける |
| Group作成時の`internal` | 過去の報告。現在のlocal APIでの再現・該当ログは未確認 | `CreateGroup`の要求受信／失敗ログとmigration状態を照合する |

発生時のサーバーログは次で絞る（プロジェクトrootから実行。migration状態は`make -C backend migrate-status`で読み取り確認）：

```sh
docker compose --project-directory backend -f backend/compose.local.yaml logs --since=10m api \
  | rg 'request received|operation failed|sql_state='
```

## 優先順位

### P0 — エラーを再現して直す

0. **起動・認証・Desktop連携の導線を受け入れる**
   - 初回起動で未ログインなら歓迎／ログイン画面が表示され、ログインを後回しにした場合は明示的なローカル利用になることを確認する。Release一般利用者へProject URL・publishable key・API URLの入力欄が表示されないことも確認する。
   - 新規メールと既存メールのOTPでSupabase Authへ入り、同じ環境のDesktopと同一の業務Userへ対応づくことを確認する。
   - 保存済みAuth sessionの再起動後復元、refresh、失効・ログアウト、EnsureUser／GetMe失敗後の再試行を確認する。
   - 利用者がSupabaseのkeyやAPI URLを手入力しなくてよいRelease設定経路と、Debug開発設定を分けて確認する。値自体は記録しない。
   - DesktopとiPhoneのどちらもアカウント情報を入力する方式か、同一メールOTPで直接認証する方式かをコード／仕様で照合し、環境を揃える手順を記録する。

1. **API経路の棚卸し**
   - Auth／EnsureUser／GetMe
   - iPhone端末登録・制限ポリシー
   - Homeのセッション・残高・制限状態
   - Groups・公開名・招待・作業開始フィード
   - History・transactions
   - 利用枠・実利用報告
   - 通知先登録・解除
   - 各呼び出しについて、利用画面、request/response DTO、認証、エラー表示、retry、空状態を一覧化する。

2. **再現・テスト基盤**
   - Swift PackageのXCTestを追加した。現状の7件はmacOS hostで実行し、iOS Simulator向けアプリbuildは別に行う。
   - `ConnectJSONClient`は`URLSession`を注入でき、transport seamでBearer header／Connect error／session欠落の3件を確認する。
   - 認証起動状態を`AuthenticationEntryState`へ分け、業務User同期成功の要件と新規未認証・ローカル利用への分岐を2件テストした。RootView／Supabase／Connect APIの結合状態遷移は別途確認する。
   - 1つの失敗シナリオごとに、テストを先に追加して失敗を確認し、修正後に通す。
   - test用stubは通信応答を決定的に再現する目的だけに使い、アプリ機能でモックデータへ切り替える経路は作らない。

3. **現在報告されている通知画面の再読込エラー**
   - `.task`、scene復帰、認証変更、APNs token callbackによる重複refresh／重複登録をテストで確認する。
   - 同じtokenの並行／成功後の重複登録、明示的な再試行、未ログイン・設定不足、許可拒否時の解除を確認する。
   - 同じtokenのin-flightと成功済み再読込はgateとXCTestで対応。未ログイン／設定不足と許可拒否はAPI結合で引き続き確認する。
   - エラーコードは画面と診断ログで特定でき、token・access token等は表示／記録しない。

4. **認証・Connect transport**
   - access token欠落・期限切れ・401／403、HTTP status、Connect code、通信断、timeout、JSON decode failureを個別に再現する。
   - ProtoJSON enum、`int64`、camelCase field、timestamp等の変換をAPI契約・生成物と照合する。
   - session更新後の端末registration ID、User同期、ログアウト・再ログインを確認する。

5. **機能別APIエラー**
   - Group／Home／History／Restriction／UsageのRepository呼び出しを画面単位で追い、一覧・詳細・作成・retryの成功／失敗／empty stateを確認する。
   - エラー後に古い成功状態やモック値を成功として表示しない。
   - 失敗が見つかったら、再現テスト→最小修正→Simulator buildの順に縦切りで進める。

6. **Desktopとの同一アカウント接続・設定配布**
   - MobileとDesktopがメールOTPと同じSupabase project／backend環境を使い、検証済みSupabase subjectから同じ業務Userを引く経路を確認する。
   - Releaseは公開可能なProject URL・publishable key・HTTPS API URLをアプリ設定へ組み込み、利用者にkey入力を要求しない。local DebugではMobileが開発設定を保存し、Desktopは起動環境変数を読むため、開発者向け手順は別記する。
   - 新規／既存メール、環境不一致、片方だけログイン、片方ログアウト、Auth成功後のEnsureUser/GetMe失敗を確認する。

### P1 — 結合確認とドキュメント

1. 最新migration・local Compose API・iOS Debug appの組み合わせで、認証付きAPIの往復を確認する。
2. APNsはendpoint登録、Outbox作成、配信、失効tokenを区別して確認する。配信試験はSandbox、登録済みrecipient、別メンバーによる新規作業開始を使う。
3. 各修正後に`mobile/README.md`または該当仕様書へ実装状況・確認内容・残課題を記録する。
4. 質問が必要になっても作業を止めず、決定が必要な理由・候補・安全な暫定方針を「未決事項」に書く。既存仕様で判断できる小さな点はその仕様に従う。
5. 縦切りごとにcommitし、作業木・秘密情報を確認してから保存する。pushしない。

### P2 — 後回し

- キャラクターが動くウィジェット。
- 友達の集中状態を表示するDynamic Island／Live Activity。
- 既存PoC `poc/ios-friend-focus-widget/` と仕様を確認し、API安定化後に独立した実装計画を作る。

## 完了条件

- 優先API経路の一覧と、それぞれの成功・失敗表示・retry方針が記録されている。
- 見つかったAPI不具合に再現性のあるSimulator testがあり、修正後に通る。
- iOS Simulator Debug buildが通る。
- 実機／APNsなどSimulatorで証明できない範囲を明記し、未解決エラーをコードと再現手順つきで残す。
- 関連ドキュメントが実装と一致し、コミットがローカルブランチにある。pushはしない。

## 参照資料

- [`mobile/README.md`](../../mobile/README.md) — 画面別の現在のAPI接続
- [`docs/spec/3.API仕様書.md`](../spec/3.API仕様書.md) — Connect契約・エラー分類・再同期
- [`docs/spec/4.ドメインモデル定義.md`](../spec/4.ドメインモデル定義.md) — 状態・不変条件
- [`docs/spec/6.iOSクライアント開発フロー.md`](../spec/6.iOSクライアント開発フロー.md) — iOS接続段階・未決事項
- [`docs/spec/8.desktop-mobile連携の現状と課題.md`](../spec/8.desktop-mobile連携の現状と課題.md) — 環境と端末間同期

## 未決事項

実装中に判断が必要な事項を、質問ではなくここへ追記する。

| 項目 | 必要な判断 | 暫定方針 | 状態 |
| --- | --- | --- | --- |
| XCTestのseam | transport層・Repository/ViewModel層のどこまでをテスト対象とするか | `ConnectJSONClient`の注入URLSessionと`AuthenticationEntryState`をテストするSwift Packageを追加。現行の`swift test`はmacOS host実行であり、iOS Simulator XCTest targetは未整備。iOS Simulator向けRewardTime app buildは別途実行 | 初期分を実装、Simulator test target未整備 |
| ログイン後の業務User同期失敗 | Supabase Auth成功後、EnsureUser／GetMeが失敗した場合にログイン済みUIへ入れるか | Authの成否と業務User同期を別状態で表示し、失敗時は再試行・ローカル利用・別アカウントログインを提供 | 実装済み、API実機確認待ち |
| 利用者向け接続設定 | local Debug値・Release環境値をどこで管理するか | Debugは開発者向け。ReleaseはBuild Settings／Info.plistで配布環境を組み込み、公開値だけを含める | コード上の経路あり、配布設定未確認 |
| Desktopとのアカウント対応 | 同一メール以外のアカウントリンク／統合が必要か | 既存仕様の同一Supabase subject→業務User対応を使う。別アカウント統合はしない | 仕様確認済み、E2E未確認 |
| 既知のmobile APIエラー | 画面・操作・Connect code・再現条件 | register重複は抑止し、旧regex障害migrationは適用済み。`not_found`の現在原因は未特定のため、再発時にbackend logと画面操作を紐づける | 一部修正、再現待ち |
| APNs実機受け入れ | sandbox署名、二人以上のrecipient、実機配信 | API安定化後にシミュレータ検証と分けて確認 | 未確認 |

## テスト実行

API transport／起動状態のユニットテストは`mobile/RewardTimeTests/Package.swift`でアプリ本体の`Data/ConnectJSONClient.swift`と`Data/AuthenticationEntryState.swift`を直接コンパイルする。これはmacOS host上で動作し、iOS Simulator XCTest実行ではない。

```sh
swift test --package-path mobile/RewardTimeTests
```
