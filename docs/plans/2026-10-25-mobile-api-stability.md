# Mobile APIエラー安定化 作業リスト

## 目的

時間が限られているため、mobileのAPIエラーを優先して再現・修正する。ユニットテストとSimulator向けXCTestを実行し、仕様・調査結果・未決事項をこの資料と関連資料へ反映する。

作業ブランチは`fix/mobile-api-stability`。作業単位でローカルコミットし、pushしない。

## 初回調査で確認した現状

- `RootTabView`は保存済みSupabase sessionを復元し、有効なら起動時のログイン画面を省略する。sessionがなく、ログインを後回しにした記録もなければ歓迎／ログイン画面を出す。
- Mobile／DesktopともメールOTPを使い、Mobileは新規Auth user作成を許可する。OTP成功後、Mobileは`EnsureUser`と`GetMe`を呼び、Desktopも認証後に業務Userの確認を行う。同じSupabase project・backend環境・アカウントであれば同じsubjectから同じ業務Userへ対応する設計で、端末ペアリングコードはない。
- Mobile Debugでは開発者向け設定へProject URL・publishable key・Connect API URLを保存する。ReleaseではInfo.plistがBuild Settings値を読む構造だが、現行Xcode projectに3値のRelease設定を渡す`.xcconfig`／CI注入がないため、Release配布設定は未完了。通常利用者へ手入力させない構造自体はあるが、Releaseビルドへ環境別公開値を設定する作業が必要。Desktopも起動時の`FOCUS_LINK_*`環境変数を読むため、配布時の環境設定注入は未整備。
- Desktop／Mobileは同じSupabase project・メールOTPアカウント・backend環境を使えば、同じJWT subjectから同じ業務Userへ対応する。新規Auth user作成と既存Auth userのOTPログインを両クライアントで許可し、ペアリングコードは使わない。実環境での新規／既存・環境不一致を含むE2Eは未実施。
- 認証と業務User同期は別段階。`RootTabView`は起動時に`EnsureUser`／`GetMe`成功を要求する。監査で、設定画面からの認証状態変更通知がsessionの有無だけでauthenticatedへ切り替える経路を発見したため、通知後もRoot側で同期を再実行するよう修正した。失敗時は同期エラー・再試行・端末内利用・別アカウントログインを表示する。入口状態resolverのhost testは2件通過したが、SwiftUI root／Supabase／Connect APIの結合状態遷移と実backend復旧は未確認。
- Mobileは`ConnectJSONClient`の`URLSession`を注入できる。`mobile/RewardTimeTests/Package.swift`とXCTestがあり、macOS host上でAPI通信・起動状態・通知の未ログイン判定／登録ゲート／順序・Home更新失敗・Device失効・Group APIエラー表示・利用枠再試行分類の29件が通過した。さらにXcodeの`RewardTimeSimulatorTests` targetを追加し、iPhone 17 Simulator (iOS 27.0) 上でDevice失効、Group API分類・作業フィード・一覧refresh失敗保持、認証入口状態、利用枠再試行方針の10件が通過した。認証入口テストは状態resolverまででありSwiftUI画面・SupabaseへのE2Eではない。端末失効のAPI応答を含むアプリ本体のSimulator buildも成功。通知登録は成功済み同一tokenの通常再読込を抑止し、並行要求をまとめ、Device登録後にendpointを登録する。tokenそのものは重複抑止キーとして保存しない。
- 現時点のRepository API一覧（呼び出し存在の確認まで。成功応答・DTO互換・画面ごとのretryは引き続き検証）：

| 画面／目的 | 実装API経路 | 確認状況 |
| --- | --- | --- |
| 起動・アカウント | Supabase OTP／refresh、Identity `EnsureUser`・`GetMe`・`UpdateDisplayName`・`UpdateAvatar` | コードと入口状態resolverは確認済み。SwiftUI画面・Supabase／実backendの認証結合は未確認 |
| Home | Focus `GetCurrentSession`、Reward `GetBalance`、Restriction `GetRestrictionState` | refresh失敗時に古いsnapshotを残しつつ警告を表示し、古いrestriction状態をOSへ再適用しないよう修正。回帰XCTestを追加。3 API間のsession ID／version整合・部分失敗時の実API表示は未確認 |
| Groups | Group `ListGroups`・`CreateGroup`・`CreateInvitation`・`AcceptInvitation`・`LeaveGroup`、REST `v1/group/work-starts` | RPC名とproto JSON DTO、REST response項目をGo handlerと静的照合し一致。Group API error mappingを一覧・作成・招待発行・招待受諾・退出・作業開始フィードの画面処理で共通化し、error code別案内を追加。一覧再取得の失敗では前回値を保持し、警告と再試行を表示する。過去の`internal`／`not_found`は現在再現せず、認証付き実API成功は未確認 |
| History | Focus `ListSessions`、Reward `ListTransactions` | response DTO（entries/session/reward, transactions）・ProtoJSON int64・timestamp・page tokenをproto／Go handlerと照合し一致。ViewModelは両方の初回取得が成功してから更新し、失敗時は前回値とstale表示を保つ。片方だけの失敗・実API pagingは未確認 |
| 設定・制限 | Identity `RegisterDevice`、Restriction `GetRestrictionPolicy`・`UpdateRestrictionPolicy`・`GetRestrictionState`／`ReportRestrictionState` | revision競合・再試行を要確認。ログアウト時はIdentity `ListDevices`・`RevokeDevice`・`DeleteNotificationEndpoint`で端末と通知先を解除し、registration IDを破棄して次回登録用に更新 |
| 利用枠 | Restriction `ReserveUsageGrant`・`GetUsageGrant`・`ReportUsage`・`GetRestrictionOperation` | RPC名、ProtoJSON int64 string、request／response fieldsをprotoと照合し一致。Reserve operation IDとpending usage reportはlocal保存する。曖昧なHTTP 5xx／Connect `internal`／不正応答ではoperation IDとmonitorを保持し同じ要求を再送、明確な拒否と事前設定エラーは解除する。OS monitor・応答喪失・プロセス再起動を含む実機E2Eは未確認 |
| 通知 | Identity `RegisterNotificationEndpoint`・`DeleteNotificationEndpoint` | 重複登録抑止に加え、endpoint要求の前に同じregistration IDで`RegisterDevice`を実行する順序を追加。ログアウト中は登録・解除APIを呼ばずログインを案内する。旧SQLSTATE 2201B制約障害とは別に、Device未登録時はbackendがnot_foundを返す経路を確認。認証付き実API往復は未確認 |

認証入口をコードで照合した結果、初回未ログインでログインを後回しにしていない場合は歓迎／ログイン画面を表示し、保存済みsessionがある場合は通常この画面を省略する。メールOTPの送信は新規Auth user作成を許可しているため、新規／既存メールの入口は共通である。OTP成功だけでAPI利用状態にせず、`EnsureUser`と`GetMe`が成功してから認証済み状態にする。iOSの接続値入力欄はDebug向けで、ReleaseではInfo.plist値を読むが、Release用URL・publishable key・API URLの`.xcconfig`／CI注入はまだない。Desktopも同じSupabase project・backend環境・メールOTP accountを使う構成で、ペアリングコードはない。従って、利用者が接続キーを入力しなくてよい**配布版**はまだ完成していない。新規／既存メールを用いた両アプリの実環境E2Eも未確認。

### 既知のエラー報告と再現状況

| 報告 | 現在の証拠 | 次の切り分け |
| --- | --- | --- |
| 通知画面の再読込時などにAPI error `not_found`／`internal` | SQLSTATE 2201Bはmigration 00012のAPNs token regex制約で発生した。00014がregexを修正し、local DBはversion 14まで適用済み。2026-10-25の読み取り確認では、直近90分にregister要求が9件あったが`operation failed`等のエラー記録はなく、現在の失敗は再現していない。成功完了ログもないため、要求の成否は断定できない。コード上はendpoint登録前のDevice登録が保証されず、backendはregistration IDのDevice検索に失敗するとnot_foundを返すため、この経路も候補だった。また、未ログインでも通知画面refreshからendpoint APIを呼ぶ経路があった | 同一token重複抑止、「Device登録→通知先登録」の順序、未ログイン時にendpoint APIを呼ばない判定をhost testsで確認済み。以前のnot_foundとDevice未登録経路が同一原因かは未確認。次の再発時に時刻・画面・Connect code・サーバー失敗operationを対応づける |
| Group API操作時の`internal`／`not_found`／404 | 現在のlocal API containerは稼働中。migration statusで1〜14がすべてapplied。認証なしの読み取り専用`ListGroups` probeはHTTP 401／Connect `unauthenticated`となり、現在のbackendにGroup routeがあることを確認。過去エラーは再現していない。RPC名・DTOをGo handlerと静的照合。以前は一覧取得だけがerror helperを使い、作成・招待発行／受諾・退出は別の汎用表示を使っていたため、操作エラーの説明が揃わなかった | 全操作で共通のerror helperを使用するよう変更。Connect `unimplemented`・`internal`・`not_found`・`unauthenticated`等のhost 5件、Simulator経路1件が通過。実backendでの認証付き操作は未確認。再発時に`CreateGroup`等のoperation failureとSQLSTATEを照合する |
| 利用枠予約の結果不明エラー | `UsageReservationViewModel`はHTTP／Connectエラーをすべて確定拒否として扱い、monitorを停止してpending operation ID・秒数を消していた。backend `Sessions.Reserve`はoperation IDでトランザクション結果をreplayするため、HTTP 5xx等の結果不明後に新規IDを作ると二重予約の恐れがある | 結果が不明なHTTP 5xx、Connect `internal`／`unavailable`、不正応答、認証token欠落ではpending requestとmonitorを保持し、同じ利用時間・operation IDで再試行する。明確な拒否4xxと端末内設定エラーは停止・解除する。host 3件とSimulator policy testで確認。実API応答喪失は未確認 |
| 利用枠の保留予約が再試行できない | 前回応答不明後にサーバーだけ予約を確定すると、残高APIが減額済みの値を返す。画面は保留秒数を選択時間に復元する一方、通常の残高チェックで予約ボタンを無効化していた | 保留operation IDがあり、保存済みの秒数・選択時間が一致する場合は残高チェックを迂回して同じ操作を再送する。新規予約の残高制限と保留情報の整合性検証は維持する。host 3件とSimulator 1件で確認。実API応答喪失後のE2Eは未確認 |
| グループ一覧の再取得失敗で一覧が消える | `GroupViewModel.load()`は更新前に常に`.loading`へ遷移し、失敗時に`.failed`へ切り替えて前回成功データを破棄していた | 前回一覧を保ち、取得失敗の警告・再読み込みを表示する。再試行成功で警告を消して新しい一覧に置き換える。Simulator testで失敗後保持と再試行成功を確認 |

発生時のサーバーログは次で絞る（プロジェクトrootから実行。migration状態は`make -C backend migrate-status`で読み取り確認）：

```sh
docker compose --project-directory backend -f backend/compose.local.yaml logs --since=10m api \
  | rg 'request received|operation failed|sql_state='
```

## 優先順位

### P0 — エラーを再現して直す

0. **起動・認証・Desktop連携の導線を受け入れる**
   - 初回起動で未ログインなら歓迎／ログイン画面が表示されることを確認する。iPhone 18 Pro / iOS 27.0の新規Simulatorで画面を目視済み。ログインを後回しにした場合のローカル利用は状態resolverでテスト済みだが、SwiftUI画面をassertするUI testは未実施。
   - 新規メールと既存メールのOTPでSupabase Authへ入り、同じ環境のDesktopと同一の業務Userへ対応づくことを実機・Desktopで確認する。未登録メールが作成され、既存メールが既存アカウントへ入ることも別々に記録する。
   - 保存済みAuth sessionの再起動後復元、refresh、失効・ログアウト、EnsureUser／GetMe失敗後の再試行を確認する。
   - 一般利用者がSupabase公開keyやAPI URLを手入力しないRelease経路と、開発者だけが設定するDebug経路を確認する。値自体は記録しない。MobileのRelease値をBuild Settings／CIから注入する設定とDesktop配布版の環境設定注入が未整備なので、配布構成を整えるまでは受け入れ未完了とする。
   - DesktopとiPhoneは同一メールOTPで直接認証する設計で、アプリ間ペアリングは不要。Desktopは現在起動時環境変数、Mobile Debugは開発者設定を使う。両方が同じSupabase projectとbackend環境を参照すること、およびDesktop配布版で利用者に環境変数設定を求めないことを確認する。

   | シナリオ | 期待結果 | 現在の確認状況 |
   | --- | --- | --- |
   | 初回起動・未ログイン | 歓迎／ログイン画面を表示。OTP送信前に公開名・アイコンを選択できる | iPhone 18 Pro / iOS 27.0の新規Simulatorで歓迎画面・アイコン一覧・メール欄・コード送信ボタンを目視。接続値なしのため送信ボタンは無効。画面をassertするUI testとOTP送信は未確認 |
   | 新規利用者 | OTP成功後にAuth userを作成し、`EnsureUser`／`GetMe`完了後にアプリ機能へ入る | コード上の新規許可と状態resolverを確認。実Supabase／API E2E未確認 |
   | 既存利用者 | OTPで既存Auth userに入り、保存sessionを次回起動で復元 | コード経路を確認。実メールOTP・session refresh E2E未確認 |
   | Desktop + Mobile | 同じSupabase project・backend・アカウントなら同じ業務User。ペアリング操作なし | コード／契約を確認。両アプリ同時の実接続未確認 |
   | 接続値入力 | Debugは開発者向け設定。Release一般利用者にはProject URL／公開key／API URL入力を要求しない | Release画面に入力欄はない。Release参照経路はあるがBuild Settings／CIへの値注入なし。Desktopも配布時の環境注入なし。利用者向け配布受け入れ未完了 |

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
   - Swift PackageのXCTestはmacOS host上で27件実行する。Xcodeの`RewardTimeSimulatorTests` targetでDevice失効API、Group APIエラー／作業フィード・一覧refresh失敗保持、認証入口状態、利用枠再試行方針の10件をiOS Simulator上で実行する。
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
   - ログアウト時に登録済みiPhoneをbackendから先に失効するようにし、API失敗時はローカルAuth sessionを残して再試行可能にした。順序と失敗時の保護はmacOS host／Simulator testsで確認。実API接続は未確認。

5. **機能別APIエラー**
   - Group／Home／History／Restriction／UsageのRepository呼び出しを画面単位で追い、一覧・詳細・作成・retryの成功／失敗／empty stateを確認する。
   - エラー後に古い成功状態やモック値を成功として表示しない。
   - 失敗が見つかったら、再現テスト→最小修正→Simulator buildの順に縦切りで進める。

6. **Desktopとの同一アカウント接続・設定配布**
   - MobileとDesktopがメールOTPと同じSupabase project／backend環境を使い、検証済みSupabase subjectから同じ業務Userを引く経路を確認する。
   - Releaseは公開可能なProject URL・publishable key・HTTPS API URLをアプリ設定へ組み込み、利用者にkey入力を要求しない。local DebugではMobileが開発設定を保存し、Desktopは起動環境変数を読むため、開発者向け手順は別記する。
   - 新規／既存メール、環境不一致、片方だけログイン、片方ログアウト、Auth成功後のEnsureUser/GetMe失敗を確認する。

### P1 — 結合確認とドキュメント

1. local Compose APIのmigration 1〜14適用を確認した（`make -C backend migrate-status`、status commandのみでmigration適用なし）。現在の`ListGroups` routeは存在するが、iOS Debug appとの認証付きAPI往復は引き続き未確認。
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
- 見つかったAPI不具合に再現性のある自動テストがあり、修正後に通る。テストがmacOS hostかiOS Simulatorかを結果に明記する。
- iOS Simulator Debug buildが通る。Simulator上の画面・認証・API受け入れ確認は、自動build／host testとは別に記録する。
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
| XCTestのseam | transport層・Repository/ViewModel層のどこまでをテスト対象とするか | `ConnectJSONClient`の注入URLSessionと`AuthenticationEntryState`、通知未ログイン判定、予約エラー分類・残高減少後の再試行可否をテストするSwift Package、およびiOS SimulatorでDevice失効Repository・Group API error／作業フィード・一覧refresh失敗保持・AuthenticationEntryState・予約再試行方針を実行するtargetを追加 | host 29件・Simulator 10件通過。初回歓迎画面は新規Simulatorで目視。画面全体・認証付き実backend連携は未検証 |
| ログイン後の業務User同期失敗 | Supabase Auth成功後、EnsureUser／GetMeが失敗した場合にログイン済みUIへ入れるか | Authの成否と業務User同期を別状態で表示し、失敗時は再試行・ローカル利用・別アカウントログインを提供 | 実装済み、API実機確認待ち |
| 利用者向け接続設定 | local Debug値・Release環境値をどこで管理するか | Debugは開発者向け。ReleaseはBuild Settings／Info.plistで配布環境を組み込み、公開値だけを含める | コード上の経路あり、配布設定未確認 |
| Desktopとのアカウント対応 | 同一メール以外のアカウントリンク／統合が必要か | 既存仕様の同一Supabase subject→業務User対応を使う。別アカウント統合はしない | 仕様確認済み、E2E未確認 |
| iPhone再ログイン後の端末登録 | Auth sessionを作り直したときに旧Deviceをどう無効化するか。作業中にlogoutできるか | backendの`RevokeDevice`と`DeleteNotificationEndpoint`で端末／通知先を解除し、registration IDを破棄する。失効operation ID・device ID・versionは後片付け完了まで保存して応答喪失後も同一要求を再送。API失敗時はサインアウトを中断する | 順序・失敗・応答喪失をhost／Simulatorでテスト済み。実APIでのログアウト→再ログインE2Eと、作業中logoutの製品挙動は未確認 |
| 既知のmobile APIエラー | 画面・操作・Connect code・再現条件 | 通知登録重複を抑止し、Device未登録でendpoint登録が先行する順序欠落を修正。旧regex障害migrationも適用済み。過去の`not_found`とDevice未登録経路が同一原因かは未確認 | 一部修正、実APIで再発確認待ち |
| APNs実機受け入れ | sandbox署名、二人以上のrecipient、実機配信 | API安定化後にシミュレータ検証と分けて確認 | 未確認 |

## テスト実行

API transport／起動状態のユニットテストは`mobile/RewardTimeTests/Package.swift`でアプリ本体の`Data/ConnectJSONClient.swift`と`Data/AuthenticationEntryState.swift`を直接コンパイルする。これはmacOS host上で動作し、iOS Simulator XCTest実行ではない。

```sh
swift test --package-path mobile/RewardTimeTests
```

Simulatorで端末失効APIとログアウト順序を確認する（iPhone 17 / iOS 27.0の例）：

```sh
xcodebuild test \
  -project mobile/ios-reward-time.xcodeproj \
  -scheme RewardTimeSimulatorTests \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO
```

このSimulator testは`URLProtocol`でbackend応答を制御するAPI契約・エラー処理テストであり、実backendやSupabaseへの接続試験ではない。
