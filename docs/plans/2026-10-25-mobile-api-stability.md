# Mobile APIエラー安定化 作業リスト

## デモ直前の連携優先項目（2026-10-25追記）

- P0: DesktopとiPhoneが同じSupabase project・Connect API環境・メールアカウントでログインし、Desktopの作業状態がiPhone Homeへ反映される実機E2Eを行う。Desktopから開始／一時停止／再開／終了し、通信断からの復帰も確認する。詳細な判定順は[Desktop・iPhone連携仕様](../spec/8.desktop-mobile連携の現状と課題.md#11-デモで最優先に成立させること)を参照。
- コード調査では両端末のbackend経由の読書きと30秒ポーリングを確認したが、実機E2Eは未実施。同期できない場合はAuth session、`EnsureUser`／`GetMe`、接続環境、RPC応答、画面反映の境界を特定して修正する。
- Desktop設定画面がiPhone連携を固定で「未接続」と表示する誤表示を、API認証状態とiPhone状態報告の表示へ分離した。Push通知とiOS制限適用は別の未受入機能として表示する。
- APNs token callbackが通知許可を固定で許可済みとしていたため、通知拒否時にもendpoint登録へ進み得た。callback時に通知許可状態を再取得し、拒否ならendpoint削除、未決なら登録を待つ。policyのhost testsとSimulator regression testで拒否／許可状態を検証した。
- HomeではDesktopのsession開始・終了と3本の並行読取が重なった際に、一時的なsession ID不一致を検出すると3 APIを1回だけ再取得する。修正前red／修正後greenのSimulatorテストで、2回目の整合取得と各APIの再要求を確認した。再取得後も不一致なら従来どおりエラーを返す。
- 2026-10-25 設定タブの連続API同期：画面表示・前景復帰・認証変更・Screen Time状態変更の同期要求が同じ内容でも、同期中ならもう一度同期するフラグへ変換されていた。要求内容（認証状態・user ID・端末制限設定）をキーに重複をまとめ、通信中に内容が変わった場合は最後の要求だけを続けて実行するgateを追加。Simulator回帰テストは重複破棄と最新要求の保持を確認し、iPhone 17 / iOS 27.0の全58 unit testsと全3 UI testsがpass。ログイン済みの実backendで設定画面を開いた際のRPC回数は未確認。通知ボタン後の再起動クラッシュは別件として再現・原因とも未確認。
- 2026-10-25 設定タブの認証再確認：`AuthenticationSettingsSection.onAppear`はタブ再表示のたびに保存済みSupabase sessionを確認し、ログイン中は`EnsureUser`／`GetMe`も再実行していた。画面インスタンスにつき自動復元を1回に制限し、同期に失敗した場合は既存の「アカウント情報を再同期」から明示retryする。restore gateのSimulator testは修正前compile fail（未実装gate）・修正後pass。iPhone 17 / iOS 27.0の全62 unit／UI testsがpass。実backendのRPC回数は未確認。
- 2026-10-25 ログイン後の再同期`EnsureUser` timeout：ユーザー報告は`EnsureUser`。ローカルbackend containerはrunningで、Mac loopback／LAN双方の`/healthz`はHTTP 200だったが、直近2時間のAPI logに`EnsureUser`はなかった。iPhoneからの再同期要求がこのbackendへ届いていない可能性がある。DebugのAPI URL既定値が実機でも`127.0.0.1:8080`だったため、既定値をSimulatorだけに限定し、実機Debugでは未設定扱いに変更。実機にloopbackが保存されている場合は同期先を拒否し、設定画面にMac LAN IPを使う案内を表示する。Simulator全63 testsとgeneric iOS Debug buildがpass。iPhone側の保存URL・Supabase token refresh／API到達のどちらで待つか、実機で再試行して未確認。
- 2026-10-25 再同期押下後も`EnsureUser`がbackend logにないことを確認。ログに出ていたのは`GET /healthz` 200とブラウザ直下の`GET /` 404（root route未提供なので想定どおり）。`ConnectJSONClient`はHTTP送信より前にtoken providerを呼び、Supabase session refresh失敗もIdentity Repositoryが`EnsureUser`として包む。token providerが失敗した場合に「アクセストークン取得」と表示し、HTTP未送信と分かるようにする。専用host regression testが通過、host suite 47件とSimulator suite 63件pass。実機でこの新表示が出るかは再インストール後の再同期で確認待ち。

## 目的

時間が限られているため、mobileのAPIエラーを優先して再現・修正する。ユニットテストとSimulator向けXCTestを実行し、仕様・調査結果・未決事項をこの資料と関連資料へ反映する。

作業ブランチは`fix/mobile-api-stability`。作業単位でローカルコミットし、pushしない。

## 初回調査で確認した現状

- `RootTabView`は保存済みSupabase sessionを復元し、有効なら起動時のログイン画面を省略する。sessionがなく、ログインを後回しにした記録もなければ歓迎／ログイン画面を出す。
- Mobile／DesktopともメールOTPを使い、Mobileは新規Auth user作成を許可する。OTP成功後、Mobileは`EnsureUser`と`GetMe`を呼び、Desktopも認証後に業務Userの確認を行う。同じSupabase project・backend環境・アカウントであれば同じsubjectから同じ業務Userへ対応する設計で、端末ペアリングコードはない。
- Mobile Debugでは開発者向け設定へProject URL・publishable key・Connect API URLを保存する。Releaseは`Release.xcconfig`とgit ignore対象の`Release.local.xcconfig`を使い、`build-release-simulator.sh`が設定値・HTTPS・生成Info.plistへの注入を検証する。URLのxcconfigコメント化を検知して直したうえで、架空値によるRelease Simulator buildとplist照合に成功した。実環境値を含むlocal config、CI設定、実機Archive／認証接続は未確認。通常利用者へ入力させないUI経路はある。Desktopも起動時の`FOCUS_LINK_*`環境変数を読むため、配布時の環境設定注入は未整備。
- Desktop／Mobileは同じSupabase project・メールOTPアカウント・backend環境を使えば、同じJWT subjectから同じ業務Userへ対応する。新規Auth user作成と既存Auth userのOTPログインを両クライアントで許可し、ペアリングコードは使わない。実環境での新規／既存・環境不一致を含むE2Eは未実施。
- ログイン導線を実装と照合：初回未ログインは歓迎画面内にメールOTP欄を表示し、未登録メールはAuth user作成を許可、既存メールは同じOTP導線で認証する。Simulator testでMobileが`create_user: true`の共通OTP routeを使い、`/verify`へ`type: email`を送りsessionを保存することを確認した。保存sessionはKeychain経由で復元し、期限切れならSupabase SDKがrefresh tokenを使い新sessionを保存することもstub HTTP responseで確認した。`EnsureUser`／`GetMe`成功後にAPI利用へ入る。Desktop側も`/otp`へ`create_user: true`を送り、`/verify`後に`EnsureUser`を呼ぶ。同じSupabase project・backendならメールOTP後に同じ業務Userへ対応する。初回画面UI testはDebug／Releaseで追加済みだが、実Supabaseのメール送信／OTP検証、OTP認証後の画面遷移、新規／既存Authおよび両クライアント同時ログインの実E2Eは未確認。
- 接続値の手入力：Mobile Debugの歓迎画面には折りたたみ式「開発者向け接続設定」が表示される。Releaseではこの欄を表示せず、Info.plistへビルド時に注入する。local xcconfigと、設定の検査・Release Simulator build・Info.plist照合を行うscriptを追加した。実環境値を含むlocal config／CI設定／実機Archiveは未確認。Desktopは`FOCUS_LINK_*`環境変数を起動時に読むため、Desktop配布時の値注入は未整備。利用者向け配布経路の受け入れは未完了。secret／service-role keyは配布しない。
- 認証と業務User同期は別段階。`RootTabView`は起動時に`EnsureUser`／`GetMe`成功を要求する。設定画面からの認証状態変更後もRoot側で業務User同期を実行する。業務User同期失敗後に選んだlocal-only状態は再起動・前景復帰時に維持し、同期を明示的に再開するまで認証済みAPIへ進まない。さらに、期限切れsession refreshの通信失敗を「未ログイン」と誤判定して歓迎画面へ戻す問題を修正した。状態resolverのhost testsは5件、local-only時の同期抑止はSimulator testで確認。SwiftUI root／Supabase／Connect APIの実backend復旧は未確認。
- Mobileは`ConnectJSONClient`の`URLSession`を注入できる。`mobile/RewardTimeTests/Package.swift`とXCTestがあり、macOS host上でAPI通信・起動状態・認証済みAPI gate・通知の未ログイン判定／許可状態を考慮した登録ゲート／順序・Home更新失敗・Device失効・Group APIエラー表示・端末設定APIエラー表示・利用枠再試行分類・transportの401／403／HTTP 404／REST Connect error／通信断／timeout／JSON decode errorの45件が通過した。iPhone 17 Simulator (iOS 27.0) ではRepository／ViewModel／auth contractの55件と、初回ログインUI testのDebug 1件が通過した。OTPとrefreshの応答はstubであり、実Supabaseや実backendへの認証付き往復を証明しない。通知登録は成功済み同一tokenの通常再読込を抑止し、並行要求をまとめ、Device登録後にendpointを登録する。Identityのプロフィール更新、端末登録・端末ポリシー読込／更新・通知登録／解除・サインアウト時の端末失効エラー表示には失敗したRPC名を含める。tokenそのものは重複抑止キーとして保存しない。
- モック経路の静的確認：`MockHomeRepository`とsample snapshotの参照箇所は`HomeView_Previews`だけ。実アプリのHomeは`ConfiguredHomeRepository`からAPI repositoryを作り、API設定が不足・不正ならsampleデータへ切り替えずエラーを返す。モック表示が実機に出る問題は現ソースからは確認されなかった。
- 2026-10-25 APIエラー表示の再検証：Groupのoperation別案内修正後はhost 45件・Simulator 39件pass。History `ListSessions`／`ListTransactions`のエラーへRPC名を加え、Simulator全40件pass、両RPC名を確認する対象テストも再実行してpass。Homeの3 RPCにもoperation名を付け、全40件pass、3つの失敗経路を対象テストで再実行してpass。実Supabase／backendへの認証付き要求は含まない。
- 2026-10-25 通知先解除のエラー照合：`DeleteNotificationEndpoint`失敗時にConnect codeとRPC名が保たれるRepository testを追加。対象testとSimulator全41件がiPhone 17 / iOS 27.0でpass。host 45件も再実行し全pass。実Supabase／backendへの認証付き要求は含まない。
- 2026-10-25 端末ポリシー同期のエラー照合：`RegisterDevice`・`GetRestrictionPolicy`・`UpdateRestrictionPolicy`のConnect errorをRPC名付きで表示するよう変更。新しい再現テストは修正前に失敗し、修正後にpass。`aborted`のrevision競合再取得は既存Simulator testで維持を確認。Simulator全43件pass。
- 2026-10-25 サインアウトAPIのエラー照合：`ListDevices`・`RevokeDevice`・サインアウト時の`DeleteNotificationEndpoint`失敗にRPC名を付与。修正前のRevokeDevice／DeleteNotificationEndpointテスト失敗を確認後、修正し、対象4件・Simulator全44件pass。`permission_denied`での既失効端末処理と`aborted`後の同一operation再試行もpass。
- 2026-10-25 Identity APIのエラー照合：`EnsureUser`・`GetMe`・`UpdateAvatar`・`UpdateDisplayName`のConnect errorへRPC名を付与。修正前に新規失敗テスト4件がred、修正後green。アイコン404の再現表示とプロフィール更新失敗経路を確認するSimulator全47件pass。実backendが404を返す原因は認証付き実API確認待ち。
- 2026-10-25 利用枠APIのエラー照合：Reserve／ReportRestrictionState／GetUsageGrant／ReportUsage／GetRestrictionOperationの失敗へRPC名を付け、Connect codeも維持。ラップされたエラーでも予約失敗の確定／不確定を元のConnect codeで分類し、曖昧な応答ではoperation IDを保つ。host 45件、iPhone 17 Simulator 50件、初回ログインUI test 1件がpass。実backendへの利用枠操作は未確認。
- 2026-10-25 自動同期エラーの表示：RootTabViewが保存済み利用枠同期失敗を`try?`で破棄し、別タブ中のHome状態API失敗も画面へ出していなかった。両要求を個別に実行し、片方が失敗してももう片方を継続するCoordinatorを追加。Homeに失敗したRPC名・Connect codeと再試行を表示し、両方成功したら警告を消す。Simulator testは修正前に未実装Coordinatorでbuild fail、修正後にReportUsage失敗後もHome再取得すること、およびGetCurrentSession失敗の表示を確認。iPhone 17 Simulator suite 53件と初回ログインUI test 1件がpass。実API失敗表示は未確認。
- 2026-10-25 Desktop–Mobile同一アカウント連携の切り分け：backend `EnsureUser`は一意な`(auth_provider, auth_subject)`をupsertし、`GetCurrentSession`は同じ業務User IDで作業を検索する。異なる認証session ID／operation IDでも同じsubjectが同じUser IDへ対応するloopback PostgreSQL統合testを追加し、稼働中のlocal DBでpass。Desktop全Go tests、backend全Go testsもpass。アプリ2台が実際に同じSupabase subject／project／API環境を使うE2Eは未確認。サーバーにHTTP method・RPC path・status・所要時間のみを出すログを追加し、Authorization／request bodyを記録しないtestを追加。`make -C backend up`でローカルAPIを再build・再起動し、`GET /healthz` HTTP 200、およびcredentialなしの`EnsureUser`が401になり、path/statusが記録されることを確認。次はiPhoneとDesktopで同一アカウントの作業同期を実行し、RPC path／statusを照合する。
- 2026-10-25 実行中backendの再確認：Compose上でAPI containerはrunning、PostgreSQLはhealthy、`GET /healthz`はHTTP 200。API logを直近24時間で確認したが、health checkと認証なし`EnsureUser`の401以外にrequestがなく、`GetMe`／`GetCurrentSession`も記録されていない。同一アカウントのDesktop／iPhone E2Eがまだ走っていない証拠であり、アプリ間不整合の原因を実APIで診断する段階には未到達。次回は両アプリを起動し、ログイン・業務User同期・Desktop作業開始・iPhone Home反映まで操作して同時刻のRPC statusを採取する。
- 2026-10-25 Desktop–iPhone反映の再照合：`HomeView`には既にホームタブ表示中・foreground中の30秒polling、foreground復帰時の即時更新、手動pull-to-refreshがある。RootTab側へ同じHome API pollingを追加すると重複要求になるため追加しない。Mobileが同じユーザーの作業状態を読むbackend経路とPostgreSQLの同一subject対応はテスト済みだが、実端末で両クライアントのSupabase project／backend環境をそろえたE2Eは未確認。READMEへ正しいpoll条件と、`/healthz`だけでは認証・User対応を証明しない旨を記載した。次のデモ確認は同一環境でDesktop開始→30秒以内にiPhone Homeへ反映を実施し、反映しない場合はbackendの`GetCurrentSession` HTTP statusを確認する。
- 2026-10-25 重複Home API要求：HomeViewがHome APIをpoll／foreground復帰し、RootTabも同じHome APIを起動・復帰時に並行して呼んでいた。Home表示中はRootTabのHome取得をskipし、usage grant同期は継続する。他タブ表示中はRootTabがHome状態を取得してScreen Timeへreconcileする。Simulator testを修正前に追加し未対応引数のcompile failureを確認後、修正しCoordinator suite 3件pass。全Simulator suite 54件、初回ログインUI test 1件pass。Xcode SimulatorのFamilyControlsサービス警告は出るがtestは通過。
- 2026-10-25 端末失効後の通知先解除：ローカル保存のdevice IDがbackendの`ListDevices`に見つからないと、端末IDとregistration IDを消してログアウトし、同じregistration IDの通知先が残り得た。backendの`DeleteNotificationEndpoint`は認証ユーザーとregistration IDで対象を限定し、対象なしでも成功するため、一覧を最後まで探して未検出でも解除APIを呼ぶ。解除失敗時はローカルIDを保持し、ログアウトを中断する。Simulatorで修正前red、修正後passを確認。全Simulator suite 55件、初回ログインUI test 1件がpass。
- 現時点のRepository API一覧（呼び出し存在の確認まで。成功応答・DTO互換・画面ごとのretryは引き続き検証）：

| 画面／目的 | 実装API経路 | 確認状況 |
| --- | --- | --- |
| 起動・アカウント | Supabase OTP／refresh、Identity `EnsureUser`・`GetMe`・`UpdateDisplayName`・`UpdateAvatar` | Simulatorで`EnsureUser`→`GetMe`順序、両要求の失敗RPC名・Connect code保持、プロフィール更新のroute／request field・失敗RPC名、OTP send／verifyのrequest contract、期限切れsession refreshを確認。実Supabase／backend認証とSwiftUI全画面E2Eは未確認 |
| Home | Focus `GetCurrentSession`、Reward `GetBalance`、Restriction `GetRestrictionState` | refresh失敗時に古いsnapshotを残しつつ警告を表示し、古いrestriction状態をOSへ再適用しないよう修正。各要求の失敗をRPC名付きエラーへ変換し、Simulatorで3 APIそれぞれの`internal`表示を確認。3 API間のsession ID整合・部分失敗時に不完全なsnapshotを返さないテストもある。実API表示は未確認 |
| Groups | Group `ListGroups`・`CreateGroup`・`CreateInvitation`・`AcceptInvitation`・`LeaveGroup`、REST `v1/group/work-starts` | RPC名とproto JSON DTO、REST response項目をGo handlerと静的照合し一致。Simulatorで実Repositoryの5 RPC route／ProtoJSON response／`internal` code保持、およびwork-start REST GETのpath・auth header・page size・RFC3339Nano cursorと次ページ保存を確認。各画面エラーへAPI operation名を追加し、招待期限の`failed_precondition`案内を`AcceptInvitation`だけに限定。host tests 2件で誤案内とoperation labelを確認。一覧再取得の失敗では前回値を保持し、警告と再試行を表示する。過去の実API `internal`／`not_found`は再現できておらず、認証付き実API成功は未確認 |
| History | Focus `ListSessions`、Reward `ListTransactions` | response DTO（entries/session/reward, transactions）・ProtoJSON int64・timestamp・page tokenをproto／Go handlerと照合し一致。ViewModelは両方の初回取得が成功してから更新し、失敗時は前回値とstale表示を保つ。Repositoryが失敗時にRPC名とConnect codeを表示用エラーへ保持するSimulator testを追加。再読み込み失敗時の両一覧保持、追加ページ失敗時の既存項目・page token保持も確認。実API pagingは未確認 |
| 設定・制限 | Identity `RegisterDevice`、Restriction `GetRestrictionPolicy`・`UpdateRestrictionPolicy`・`GetRestrictionState`／`ReportRestrictionState` | ログアウト中は端末登録・制限設定同期を実行しない認証ゲートを追加。`RegisterDevice`／`GetRestrictionPolicy`／`UpdateRestrictionPolicy`の失敗にRPC名を付ける。Simulatorで各失敗時のエラー表示と、`aborted` revision競合後の再取得を確認。ログアウト時はIdentity `ListDevices`・`RevokeDevice`・`DeleteNotificationEndpoint`で端末と通知先を解除し、各API失敗のRPC名表示、registration IDを破棄して次回登録用に更新することをSimulatorで確認 |
| 利用枠 | Restriction `ReserveUsageGrant`・`GetUsageGrant`・`ReportUsage`・`GetRestrictionOperation` | RPC名、ProtoJSON int64 string、request／response fieldsをprotoと照合し一致。Simulatorで4 Repository methodのroute、Bearer header、request/response DTO、operation `SUCCEEDED`／`NOT_FOUND`解釈とReserveの`not_found` code保持を確認。Reserve operation IDとpending usage reportはlocal保存する。曖昧なHTTP 5xx／Connect `internal`／不正応答ではoperation IDとmonitorを保持し同じ要求を再送、明確な拒否と事前設定エラーは解除する。OS monitor・応答喪失・プロセス再起動を含む実機E2Eは未確認 |
| 通知 | Identity `RegisterDevice`・`RegisterNotificationEndpoint`・`DeleteNotificationEndpoint` | endpoint要求前に同じregistration IDで`RegisterDevice`を実行し、Rootの業務認証状態とSupabase sessionの両方を満たす場合だけ同期する。Repository経由でDevice先行登録、Device失敗時のendpoint要求抑止、endpointの`not_found`・Deviceの`internal`・解除の`internal`と失敗RPC名保持をSimulator testで確認。ログアウト／local-onlyではAPIを呼ばずログインを案内。APNs token callback・認証通知・ログイン状態変更は成功済み登録の重複抑止を尊重する。通知許可後と明示的な再同期操作では強制登録する。旧SQLSTATE 2201B制約障害とは別に、過去のDevice未登録経路とnot_foundの同一性は未確定。認証付き実API往復は未確認 |

認証入口をコードとSimulator UI testで照合した結果、初回未ログインでログインを後回しにしていない場合は歓迎／ログイン画面を表示し、保存済みsessionがある場合は通常この画面を省略する。メールOTPの送信は新規Auth user作成を許可しているため、新規／既存メールの入口は共通である。OTP成功だけでAPI利用状態にせず、`EnsureUser`と`GetMe`が成功してから認証済み状態にする。UI testは初回画面と接続値未設定時の送信無効を確認し、Releaseでは接続値入力欄が出ないことを確認した。Release Simulator向けxcconfig注入・検証scriptを追加したが、実際のRelease値を使うbuild／CI／実機配布は未確認。Desktopも同じSupabase project・backend環境・メールOTP accountを使う構成で、ペアリングコードはない。従って、利用者が接続キーを入力しなくてよい**配布版**はまだ完成していない。新規／既存メールを用いた両アプリの実環境E2Eも未確認。

ユーザー受け入れ時には「初回はログイン画面」「session復元済みの既存利用者はログイン画面を省略」「新規・既存メールとも同じOTP導線」「MobileとDesktopは同一Supabase／backend環境の同一アカウントで連携」「一般利用者は公開接続値を入力しない」を個別に確認する。初回画面とDebug／Releaseでの接続値入力欄の表示差はSimulator UI testで確認した。新規／既存メールでのAuth実接続とMobile・Desktopを並行した同一業務Userの確認、配布構成の接続値自動設定は未完了。Debugは開発者向けに手入力設定を提供する。

認証・Desktop接続の受け入れ状況を、コード上の確認と実環境確認に分けて記録する：

## デモで優先する連携確認

- 仕様：アプリ間ペアリング操作はなく、両方が同一Supabase project・同一Authアカウント・同一backendを使えば、JWT `sub`から同じ`app.users.id`へ解決される。Desktopが開始した作業セッションをMobileが`GetCurrentSession`で読む。
- 自動テスト：loopbackのマイグレーション済みPostgreSQLに限るopt-in統合testで、同一Supabase subjectを異なる認証session ID／operation IDから`EnsureUser`した結果が同じ業務User IDであることを確認した。`IDENTITY_TEST_DATABASE_URL`なしの通常テストではskipされる。
- 実機受け入れ：DesktopとiPhoneの両方で同じメールを使うだけでなく、同じSupabase project URL／backend環境であることを確認する。両方をログアウト・ログインし、Desktopで作業を開始してからiPhoneのホームを更新（自動同期は前景中30秒間隔）し、同じ作業状態が表示されることを確認する。Mobileの「ログイン済み」だけでなくbackend同期成功が必要で、端末内利用を選んだ状態ではサーバー同期しない。
- 切り分け：backendは各API requestについてmethod／RPC path／HTTP status／所要時間を記録する。`401`はAuth project／session、`404`はroute、`5xx`はserver/DB側を中心に確認する。token、request body、メールアドレスはログへ出さない。ローカルAPI更新後は`make -C backend up`で再ビルド・起動し、`docker compose --project-directory backend -f backend/compose.local.yaml logs --since=5m api`で確認する。
- 未確認：2台から届くJWT subjectが同じか、実Auth user同期後の業務User IDが同じか、Desktopの開始セッションをMobileが受信するか。ここは同一環境を使ったE2Eを完了するまで「連携済み」と扱わない。

| 確認項目 | コード／Simulatorで確認済み | 実環境で残る確認 |
| --- | --- | --- |
| 初回起動のログイン画面 | 未ログイン・login deferredなしなら歓迎／メールOTP画面を出す。UI testでメール欄、後回し、接続未設定時の送信無効を確認 | SupabaseからOTPメールを受け取り、コード認証後にHomeへ進む |
| 既存利用者の再起動 | 保存sessionをKeychainから復元できればログイン画面を省略。期限切れsession refreshと一時的refresh失敗の状態保持はstub testで確認 | 実Supabase sessionで再起動・期限切れ更新・通信復帰を確認 |
| 新規／既存メール | Mobile／DesktopともメールOTPの新規作成を許可し、既存Auth userも同じOTP経路を使う実装 | 新規メールと既存メールを各1つ使い、両アプリで認証・EnsureUser/GetMeまで成功することを確認 |
| DesktopとMobileのユーザー対応 | 同一Supabase project・同一backend環境ならJWT subjectに対応する業務Userを共有する設計。端末ペアリングコードはない | DesktopとiPhoneで同一アカウントへログインし、同一ユーザーの作業状態・残高を相互に確認。別アカウントの分離も確認 |
| 接続値を利用者に入力させない | Release UIに接続値入力欄はない。Debugのみ開発者設定が表示される。xcconfig・Release Simulator build／Info.plist検証scriptを追加 | 実環境値を含むlocal configとCI設定、実機Archive／署名、Desktop配布用環境設定は未確認。設定済み配布成果物で入力なし起動を確認 |

ここでいう「同じアカウント」は、同じメール文字列だけでなく、同じSupabase projectで発行された同一Auth user／JWT subjectを指す。別Supabase projectや異なるbackend環境では同じメールを使っても別ユーザー・別データになる。接続値のBuild Settings注入は公開可能なProject URL、publishable key、HTTPS API URLだけとし、service-role key等の秘密は含めない。

### 既知のエラー報告と再現状況

| 報告 | 現在の証拠 | 次の切り分け |
| --- | --- | --- |
| 通知画面の再読込時などにAPI error `not_found`／`internal` | SQLSTATE 2201Bはmigration 00012のAPNs token regex制約で発生した。00014がregexを修正し、local DBはversion 14まで適用済み。過去のregister要求ログは9件あったが、失敗記録はなく成否を断定できなかった。呼び出し元ではAPNs token callback・認証変更・認証状態変更が`force=true`で登録gateの成功済み抑止を迂回していた。未ログインでもrefreshやcallbackがendpoint APIを呼ぶ経路は別途修正済み。通知許可拒否時に使う`DeleteNotificationEndpoint`は、backend handlerがDB上の対象件数にかかわらず`deleted:true`を返すため、重複解除は`not_found`原因ではない。自動通知は通常の登録gateを通り、通知許可後または明示的な「通知先を再同期」操作だけ強制登録するよう変更。host testが成功後の重複抑止・明示再同期・失敗後retry、Simulator testがDevice先行登録・endpoint `not_found`／Device `internal`保持を検証。画面はAPIのLocalizedError（Connect code含む）を表示し、通知許可済みなら手動再同期を提供する（コード照合、UI testなし）。旧not_foundとDevice未登録経路の同一性、過去エラーの再発は未確認。次回再発時に時刻・画面・Connect code・サーバー失敗operationを対応づける |
| 設定タブ再表示時の未ログイン端末APIエラー | 設定画面の`.task`・前景復帰・Screen Time設定変更が、local-only中も`RegisterDevice`／制限ポリシー同期を開始しうる。認証なしの`ConnectJSONClient`はAPI送信前にtoken欠落エラーを返す | `AuthenticatedAPISyncFlow`を端末設定同期前に通し、未ログイン時は要求を実行しない。host testでsigned-out時0件、authenticated時1件のoperationを確認 |
| 設定タブを開くと何度もリロードするように見える | 端末設定API同期要求の重複に加え、`AuthenticationSettingsSection.onAppear`がタブ再表示のたびにSupabase session確認とEnsureUser／GetMeを実行していた | 端末設定同期は要求キーで重複をまとめ、認証session復元も画面インスタンス内で1度だけ実行。失敗時は手動再同期できる。両gate test・設定タブUI testを含むiPhone 17 Simulator全62 testsがpass。ログイン済み実backendの通信回数と実機表示は未確認 |
| ログイン後の「アカウント情報を再同期」で`EnsureUser` timeout | Mac上のローカルAPIは起動中で、loopback／LAN health checkはHTTP 200。2時間分のAPIログに`EnsureUser`なし。実機Debugの未設定URL既定値が`127.0.0.1:8080`を指し得た | Simulatorだけloopbackを既定にし、実機DebugはConnect API URLを未設定にする。loopback値が保存済みなら無効扱いにし、画面にMac LAN IPを案内する。全63 Simulator testsとgeneric iOS Debug build pass。実機の保存URLと再同期結果は確認待ち |
| 再同期時に`EnsureUser` timeoutと表示されるがbackendに要求がない | iPhoneから`/healthz` 200、`/` 404は記録された一方、`EnsureUser` POSTは記録されていない。`ConnectJSONClient`のHTTP前アクセストークン取得失敗も`EnsureUser`として表示され得る | アクセストークン取得に失敗した場合は、その段階とSupabase接続確認をエラーに表示。host 47 tests・iPhone 17 Simulator 63 tests pass。新しい実機エラー表示と、HTTP送信後のtimeoutなのかtoken refresh前なのかは確認待ち |
| 通知ボタン操作後の再起動でアプリが落ちる | Simulatorのlocal-onlyで通知画面を開くUI testは通過したが、報告された再起動後クラッシュは実機ログがなく再現できていない | 実機のクラッシュレポートまたは再現条件を採取し、通知設定画面の`.task`・認証／scene変更・token callbackのどれが発火したか照合する |
| 起動時に期限切れsession refreshが失敗すると歓迎画面へ戻る | `RootTabView.hasAuthenticatedSession()`が`try? await auth.accessToken()`でrefreshの通信エラーを握りつぶし、保存sessionが残る一時的な通信障害も未ログインとして解決していた | session取得失敗を認証失敗と区別し、再試行可能な`identitySyncRequired`へ進める。認証を後回しにしたlocal-only状態は優先して保つ。host tests 2件とSimulatorで通信断時もrefresh tokenが保存されたsessionを保持し、retry stateを解決するテストを確認。実Supabaseをオフラインにした起動E2Eは未確認 |
| アイコン／表示名／初回identity同期APIが失敗しても、どのRPCか分からない | `UpdateAvatar`・`UpdateDisplayName`・`EnsureUser`・`GetMe`のRepository成功契約はSimulatorで確認済みだったが、失敗時はConnect codeだけでRPC名が表示されなかった。過去にアイコン保存で404が報告されたものの、同時刻のbackend error logがなく原因は特定できていない | 各Identity RPC失敗にservice/methodを付ける。Simulatorで`UpdateAvatar`の`not_found`、`UpdateDisplayName`の`internal`、`EnsureUser`／`GetMe`の失敗経路を確認。実backendにrouteがあるか・404が再発するかは認証付き実API待ち |
| 端末設定APIの`not_found`／`internal`が一般的な同期失敗だけに見える | 接続エラーのコードは表示していたが、端末登録・ポリシー読込・更新のどのRPCが失敗したか画面から分からなかった | `RegisterDevice`・`GetRestrictionPolicy`・`UpdateRestrictionPolicy`の失敗にRPC名を付ける。SimulatorでRegisterDevice／GetRestrictionPolicy／UpdateRestrictionPolicyの`internal`を確認し、`aborted`時のrevision再取得も維持。実API失敗の再発は未確認 |
| 招待発行／グループ退出が招待リンク期限切れと誤表示される | `GroupView.invitationFailureMessage()`が`CreateInvitation`・`AcceptInvitation`・`LeaveGroup`で共有され、どのAPIの`failed_precondition`も期限切れ／使用済みリンクと案内していた。また、`internal`表示だけではbackend logのoperationと照合しにくかった | 期限案内は`AcceptInvitation`だけに限定し、各Group API errorへoperation名を表示する。host tests 2件で誤案内とoperation labelを確認し、Simulator suite 39件が通過。実backend errorの再現は未確認 |
| 履歴APIのエラー発生元が分からない | `ListSessions`と`ListTransactions`の失敗がHTTP status／Connect codeだけで表示され、どちらの並行要求が失敗したか画面から分からなかった | Repositoryで失敗を各RPC名付きエラーに変換。Simulator testで両RPCの`internal`表示とoperation名を確認し、全40件pass。実API errorの再現は未確認 |
| Home APIのエラー発生元が分からない | `GetCurrentSession`、`GetBalance`、`GetRestrictionState`を並行取得し、失敗時にHTTP status／Connect codeしか画面に出さなかった | Repositoryで失敗要求のservice／methodを付けて再throwし、応答整合エラーにも関連RPC名を含める。Simulator testで3 APIの各`internal`を発生させ、operation表示とpartial snapshot抑止を確認。実API errorの再現は未確認 |
| Group API操作時の`internal`／`not_found`／404 | 2026-10-25再確認時、local API containerはrunning・Postgres healthy・migration 1〜14 applied。`/healthz`はHTTP 200、認証なし`ListGroups`はHTTP 401／Connect `unauthenticated`（`authentication required`）。直近24時間のAPI logは起動INFOのみで操作失敗なし。host test 43件とiPhone 17 Simulator test 39件は全通過。これはAPI入口・クライアントエラー経路の確認で、認証付き操作成功を示さない | 全操作で共通のerror helperを使用するよう変更。Connect `unimplemented`・`internal`・`not_found`・`unauthenticated`等のhost 5件、Simulator経路1件が通過。今回も実APIの認証付き要求がなく、過去エラーは再現できなかった。再発時は発生時刻、操作名（List/Create/Invitation/Accept/Leave）、画面のConnect code、同時刻のoperation failure／SQLSTATEを照合する。token・メール・招待tokenは共有ログに含めない |
| 業務User同期失敗後のlocal-only状態が復帰時に解除される | `RootTabView.restoreAuthentication()`が再起動・前景復帰後にSupabase sessionだけを見てlocal-only状態を認証済みに解決し、EnsureUser／GetMe成功なしで業務APIへ進める経路があった。設定のアカウント欄も保存sessionの復元時にbackend同期を自動再試行していた | `loginDeferred`を優先し、明示的に認証を再開するまでlocal-onlyを維持。sessionが残っていてもroot・設定・アカウント欄からbusiness APIを自動同期しない。アカウント欄は保存sessionを表示し、明示的な「アカウント情報を再同期」で同期する。host／Simulator testsで同期gateを確認 |
| 利用枠予約の結果不明エラー | `UsageReservationViewModel`はHTTP／Connectエラーをすべて確定拒否として扱い、monitorを停止してpending operation ID・秒数を消していた。backend `Sessions.Reserve`はoperation IDでトランザクション結果をreplayするため、HTTP 5xx等の結果不明後に新規IDを作ると二重予約の恐れがある | 結果が不明なHTTP 5xx、Connect `internal`／`unavailable`、不正応答、認証token欠落ではpending requestとmonitorを保持し、同じ利用時間・operation IDで再試行する。明確な拒否4xxと端末内設定エラーは停止・解除する。host 3件とSimulator policy testで確認。実API応答喪失は未確認 |
| 利用枠の保留予約が再試行できない | 前回応答不明後にサーバーだけ予約を確定すると、残高APIが減額済みの値を返す。画面は保留秒数を選択時間に復元する一方、通常の残高チェックで予約ボタンを無効化していた | 保留operation IDがあり、保存済みの秒数・選択時間が一致する場合は残高チェックを迂回して同じ操作を再送する。新規予約の残高制限と保留情報の整合性検証は維持する。host 3件とSimulator 1件で確認。実API応答喪失後のE2Eは未確認 |
| グループ一覧の再取得失敗で一覧が消える | `GroupViewModel.load()`は更新前に常に`.loading`へ遷移し、失敗時に`.failed`へ切り替えて前回成功データを破棄していた | 前回一覧を保ち、取得失敗の警告・再読み込みを表示する。再試行成功で警告を消して新しい一覧に置き換える。Simulator testで失敗後保持と再試行成功を確認 |

発生時のサーバーログは次で絞る（プロジェクトrootから実行。migration状態は`make -C backend migrate-status`で読み取り確認）：

```sh
docker compose --project-directory backend -f backend/compose.local.yaml logs --since=10m --no-log-prefix api \
  | jq -Rc 'try (fromjson | {time,level,msg,method,path,status,duration_ms,operation,error_type,sql_state,constraint,table,code}) catch empty'
```

## 優先順位

### P0 — エラーを再現して直す

0. **起動・認証・Desktop連携の導線を受け入れる**
   - 初回起動で未ログインなら歓迎／ログイン画面が表示されることを確認する。iPhone 17 / iOS 27.0のSimulator UI testでメール欄・ログイン後回し・接続値未設定時のOTP送信無効を確認済み。ログインを後回しにした場合の状態resolverもhost／Simulatorで確認した。
   - 新規メールと既存メールのOTPでSupabase Authへ入り、同じ環境のDesktopと同一の業務Userへ対応づくことを実機・Desktopで確認する。未登録メールが作成され、既存メールが既存アカウントへ入ることも別々に記録する。UIが両方を区別せず同じ導線で扱い、誤解を招く「新規登録専用」表示をしないことも見る。
   - 保存済みAuth sessionの再起動後復元、refresh、失効・ログアウト、EnsureUser／GetMe失敗後の再試行を確認する。
   - 一般利用者がSupabase公開keyやAPI URLを手入力しないRelease経路と、開発者だけが設定するDebug経路を確認する。値自体は記録しない。Mobileにはlocal xcconfigとRelease Simulator build／Info.plist検証scriptを追加済み。実値によるCI／Archive設定とDesktop配布版の環境設定注入は未整備なので、配布受け入れは未完了。
   - DesktopとiPhoneは同一メールOTPで直接認証する設計で、アプリ間ペアリングは不要。Desktopは現在起動時環境変数、Mobile Debugは開発者設定を使う。両方が同じSupabase projectとbackend環境を参照すること、および配布版で利用者にキーやURLの入力／環境変数設定を求めないことを確認する。

   | シナリオ | 期待結果 | 現在の確認状況 |
   | --- | --- | --- |
   | 初回起動・未ログイン | 歓迎／ログイン画面を表示。OTP送信前に公開名・アイコンを選択できる | iPhone 17 / iOS 27.0のUI testでメール欄・コード送信・ログイン後回しと、接続値なしの送信無効を確認。アイコン選択は手動目視済み。OTP送信は未確認 |
   | 新規利用者 | OTP成功後にAuth userを作成し、`EnsureUser`／`GetMe`完了後にアプリ機能へ入る | コード上の新規許可と状態resolverを確認。実Supabase／API E2E未確認 |
   | 既存利用者 | OTPで既存Auth userに入り、保存sessionを次回起動で復元 | コード経路を確認。実メールOTP・session refresh E2E未確認 |
   | 新規メールで両アプリを利用 | Mobile／DesktopそれぞれでOTP送信・検証し、各Auth userから同一業務Userへ対応 | 両クライアントともAuth user新規作成を許可するコードを確認。実Auth作成・同一業務User確認は未実施 |
   | 既存メールで両アプリを利用 | 同じ既存Auth userへOTPログインし、各端末でsessionを復元 | OTP・Keychain／Credential Storeのコード経路を確認。実ログイン・session更新E2Eは未実施 |
   | Desktop + Mobile | 同じSupabase project・backend・アカウントなら同じ業務User。ペアリング操作なし | Mobile／Desktop双方のEnsureUser経路を確認。両アプリ同時の実接続未確認 |
   | 接続値入力 | 開発者はDebug設定を使い、一般利用者はRelease配布アプリをそのまま使う | Release画面に入力欄なし。local xcconfig／検証scriptは実装し架空値でSimulator build・plist照合済み。実値CI／ArchiveとDesktop配布時の環境注入なし。利用者向け配布受け入れ未完了 |

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
   - Swift PackageのXCTestはmacOS host上で46件実行する。Xcodeの`RewardTimeSimulatorTests` targetでIdentity `EnsureUser`／`GetMe`／プロフィール更新のsuccess・RPC名付きfailure、Device登録／失敗後再試行、制限ポリシー新規作成・各RPC失敗名・revision競合後再取得、通知先RepositoryのDevice先行登録・登録／解除失敗のConnect errorとRPC名保持、Device失効APIのoperation別エラーと再試行、Group Repository 5 RPC契約・work-start REST cursor／error保持、Group API error／作業フィード・一覧refresh失敗保持、HistoryのRPC名付きAPI error・一覧／page refresh失敗保持、認証入口状態とsession refresh失敗回帰、local-only時の端末API抑止、端末設定APIエラー表示、利用枠4 Repository method契約・operation状態解釈／5 RPCの失敗時operation名／`not_found`保持／再試行方針、Homeの3 API整合と部分失敗、OTP send／verify、期限切れsession refresh、refresh通信断後のsession保持、自動利用枠同期失敗表示／retry、Home表示中のRoot重複refresh抑止、およびAPNs token callbackの通知許可判定を含む57件をiOS Simulator上で実行する。`RewardTimeUITests` schemeの初回ログイン画面をDebugで1件実行する。
   - `ConnectJSONClient`は`URLSession`を注入できる。host testsでBearer header、Connect code、401／403、plain HTTP 404、REST Connect error、session欠落、通信断、timeout、decode failureを確認する。Supabase SDKのexpired session refreshはSimulatorでstub HTTP応答を使って確認する。実SupabaseのOTP認証／refreshは未確認。
   - 認証起動状態を`AuthenticationEntryState`へ分け、業務User同期成功の要件と新規未認証・ローカル利用への分岐を2件テストした。RootView／Supabase／Connect APIの結合状態遷移は別途確認する。
   - 1つの失敗シナリオごとに、テストを先に追加して失敗を確認し、修正後に通す。
   - test用stubは通信応答を決定的に再現する目的だけに使い、アプリ機能でモックデータへ切り替える経路は作らない。

3. **現在報告されている通知画面の再読込エラー**
   - `.task`、scene復帰、認証変更、APNs token callbackによる重複refresh／重複登録をテストで確認する。
   - 同じtokenの並行／成功後の重複登録、明示的な再試行、未ログイン・設定不足、許可拒否時の解除を確認する。
   - 同じtokenのin-flightと成功済み再読込はgateとXCTestで対応。未ログイン／設定不足と許可拒否はAPI結合で引き続き確認する。
   - エラーコードは画面と診断ログで特定でき、token・access token等は表示／記録しない。

4. **認証・Connect transport**
   - access token欠落・401／403、HTTP status、Connect code、通信断、timeout、JSON decode failureはhost testsで個別に確認済み。期限切れsessionのSupabase SDK refreshと401の実backend往復は引き続き確認する。
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
| XCTestのseam | transport層・Repository/ViewModel層のどこまでをテスト対象とするか | `ConnectJSONClient`の注入URLSessionと`AuthenticationEntryState`、認証済みAPI gate、通知未ログイン判定、予約エラー分類・残高減少後の再試行可否、HTTP／Connect／network／decode transport errorをテストするSwift Package、およびiOS SimulatorでIdentity `EnsureUser`／`GetMe`／`UpdateDisplayName`／`UpdateAvatar`のRPC別success/failure、Device登録・通知先Repository（登録／解除）・失効Repository（operation別error／retry）・制限ポリシー新規作成／各RPC失敗名／revision競合後の再取得・Group Repositoryの5 RPC／work-start cursor契約・error保持・Group ViewModel／一覧refresh失敗保持・History API RPC名／エラー保持・一覧／page失敗保持・AuthenticationEntryState・local-only時の端末API抑止・端末設定エラー表示・利用枠4 Repository method契約／operation状態解釈・予約再試行方針・Homeの3 API整合／部分失敗／session IDずれ再取得、OTP send／verify、期限切れsession refresh、refresh通信断後のsession保持、Root Home refresh重複抑止を実行するtargetを追加 | host 46件・Simulator 57件と初回ログインUI test Debug 1件が通過。実Supabase／Desktop同一アカウント接続は未検証 |
| ログイン後の業務User同期失敗 | Supabase Auth成功後、EnsureUser／GetMeが失敗した場合にログイン済みUIへ入れるか | Authの成否と業務User同期を別状態で表示し、失敗時は再試行・ローカル利用・別アカウントログインを提供 | 実装済み、API実機確認待ち |
| 利用者向け接続設定 | local Debug値・Release環境値をどこで管理するか | Debugは開発者向け。ReleaseはBuild Settings／Info.plistで配布環境を組み込み、公開値だけを含める | コード上の経路あり、配布設定未確認 |
| Desktopとのアカウント対応 | 同一メール以外のアカウントリンク／統合が必要か | 既存仕様の同一Supabase subject→業務User対応を使う。別アカウント統合はしない | 仕様確認済み、E2E未確認 |
| iPhone再ログイン後の端末登録 | Auth sessionを作り直したときに旧Deviceをどう無効化するか。作業中にlogoutできるか | backendの`RevokeDevice`と`DeleteNotificationEndpoint`で端末／通知先を解除し、registration IDを破棄する。失効operation ID・device ID・versionは後片付け完了まで保存して応答喪失後も同一要求を再送。API失敗時はサインアウトを中断する | 順序・失敗・応答喪失・ListDevicesで未検出時のDeleteNotificationEndpoint再試行とID保持をhost／Simulatorでテスト済み。実APIでのログアウト→再ログインE2Eと、作業中logoutの製品挙動は未確認 |
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

`xcodebuild test` がテスト開始後にSimulator診断収集で停止する場合、ビルドと実行を分けて直列実行する：

```sh
xcodebuild build-for-testing \
  -project mobile/ios-reward-time.xcodeproj \
  -scheme RewardTimeSimulatorTests \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test-without-building \
  -project mobile/ios-reward-time.xcodeproj \
  -scheme RewardTimeSimulatorTests \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
```

このSimulator testは`URLProtocol`でbackend応答を制御するAPI契約・エラー処理テストであり、実backendやSupabaseへの接続試験ではない。
