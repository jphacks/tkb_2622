# macOS 実機結果

2026-10-24に、ActivityWatchもブラウザ拡張も使わず、前面アプリ・入力アイドル時間・Chrome／Safariの閲覧ドメインを取得しました。短時間の取得確認と、切替精度・権限拒否・長時間無操作などの未検証項目を分けて記録します。手順と期待値は [validation.md](validation.md) を参照してください。

## 実行環境

| 項目 | 値 | 確認状態 |
|---|---|---|
| macOS / CPU | macOS 26.6.2 / arm64 | 実行ログで確認済み |
| Swift | 6.4 | 実行ログで確認済み |
| Go | 1.27.3 | 実行ログで確認済み |
| focuslog / helper のビルド識別情報 | ネイティブ取得 a3f823d、CLI・分析 1b8f07e | ビルド・実行確認済み |
| Chrome / Safari の版 | Chrome 156.0.8078.47 / Safari 26.6.2 | アプリのInfo.plistで確認 |
| 実施日時・タイムゾーン | 2026-10-24 / Asia-Tokyo（内部UTC） | capture.jsonに各時刻を保存 |

## シナリオ結果

取得できた項目は下表に記録しました。各操作に対する時間誤差や未実施の条件は、成功済みと扱いません。実測データは ignored な data/ 以下に保存し、共有用の記述には raw URL、タイトル、個人情報を含めません。

| ID | 状態 | 期待値 | 実測値 / 証跡 | 差・誤差 / 取得不能 | 仮説 / 次の対応 |
|---|---|---|---|---|---|
| OBS-01 | 部分確認 | 前面アプリとidleを取得 | ChatGPT、Chrome、Safariのbundle ID/nameとidle_observed_atを取得 | 実際の入力時刻との誤差は未測定 | 手動マーカーと比較する |
| CHR-01 | ドメイン取得確認 | GitHub／YouTubeを区別 | github.com、www.youtube.comを各4件取得、status=ok | URL切替の時間誤差は未測定 | 連続計測中の切替を時刻マーカーと比較 |
| SAF-01 | 部分確認 | SafariのHTTP(S)ドメインを取得 | github.comを連続取得。専用YouTube文書で直接AppleScriptとhelperがwww.youtube.comに一致、tab_id=null | 同一window遷移試行ではYouTube指定後も4件github.com、原因未確定 | 下記のSafari再試験事項を参照 |
| OBS-02 / RACE-01 | 部分確認 | 非ブラウザ前面時にdomainを残さない | ChatGPT前面でnot_applicable/domain=null。前面不一致は固定テスト成功 | 取得途中の実機切替競合は未実施 | 長めの照会中に前面を切り替える |
| AUT-01 / AUT-02 | 許可環境のみ確認 | 許可と拒否を区別 | Chrome／Safariでokを取得 | 権限拒否・初回配布時のダイアログは未検証 | 本人操作で拒否条件を別試験 |
| WIN-01 / BROW-01 | 未実施 | ウィンドウなしを no_window、未対応ブラウザーを unsupported とする | — | — | validation.md の手順で確認 |
| ERR-01 | 固定テスト成功 | helper失敗・timeoutを区別 | プロセス失敗、形式不正、timeoutの自動テスト成功 | 実機AppleScript timeoutは未実施 | 応答しないブラウザ条件を別試験 |
| IDLE-01 | 固定テスト成功 | 60／180／300秒を分ける | 入力経過値の取得、閾値境界と入力再開の固定テスト成功 | 実機で59/60/61等を待つ試験は未実施 | validation.mdに従い手動入力時刻と比較 |
| STATE-01 / AUDIO-01 | null出力のみ確認 | 未取得状態を補完しない | audible、lock_state、sleep_stateのnullを確認 | 音声再生・ロック・sleep自体は未実施、取得機能も未実装 | 必要なら追加APIを別途検証 |
| GAP-01 / DUP-01 | 固定テスト成功 | 欠損と重複で時間を増やさない | 間隔超過・同時競合・順不同・重複・範囲外時刻のテスト成功 | 実機sleepや強制停止は未実施 | 実機停止と復帰を別試験 |
| OUT-01 / REPLAY-01 | 確認済み | 安全な保存と再生 | 0700/0600、上書き拒否、人工・実測データ再生成功 | 下記参照 | 保存先はGit対象外 |

## 実測記録テンプレート

シナリオを実行したら、該当行に値を記入したうえで、必要な詳細を以下の形で残します。

- 実行日時 / タイムゾーン:
- macOS / CPU:
- Chrome または Safari の版:
- focuslog / helper のビルド識別情報:
- 実行コマンドと再現手順:
- 期待値:
- 実測値 / 証跡:
- 状態:
- 差・誤差:
- 取得不能だった情報:
- 仮説:
- 次の対応:

スクリーンショットやログを証跡に添付する場合も、raw URL、ページタイトル、ユーザー名、その他の個人情報は伏せ、必要最小限の domain と status / reason だけを記録してください。

## 操作ログ取得の検証

- 自動テスト：`go test -race -count=1 -json ./...` 35件成功、失敗0件。analysis、cmd/focuslog、collectorの3パッケージ。modelは型定義のみです。
- 静的・ビルド：`go vet ./...`、Go CLIビルド、`native/build.sh`が成功しました。補助プログラムのプロセス初回起動がrace実行時に1秒を超えたため、テスト側の正常起動待機を5秒とし、形式不正テストがtimeoutで見かけ上通らないことも確認しました。
- 最終実機収集：Chromeの専用GitHub windowで `record --duration 4s --poll 1s --out data/final-native`。観測4件、取得エラー0件、github.com、推定前面時間2.999秒、Unknown 1.001秒。合計4秒です。Unknownには最初の観測前・最後の観測後が含まれます。
- 固定サンプル再生：12秒＝推定4秒＋Unknown 8秒。実測データ再生：4秒＝推定2.999秒＋Unknown 1.001秒。いずれも区間総和とアプリ時間の上限を照合しました。
- JSON検品：capture/events/analysisにurl/title/raw_url/window_titleキーがないこと、browser_domainにpath/query/fragmentがないこと、ファイル0600を確認しました。
- 実機証跡はGit管理外のdata/native-chrome-*、data/native-safari-*、data/safari-youtube-probe.json、data/final-nativeに保管しています。テストログはdata/final-tests.jsonです。共有には含めません。

## Safariの再試験事項

GitHubからYouTubeへのURL設定を送った試行で、直後の4秒間はgithub.comが観測されました。その試行中のブラウザ実URLは別途照合していないため、ナビゲーション待ち・window選択・取得遅延のどれが原因かは未確定です。その後、専用のYouTube文書を作った試行では、直接AppleScriptで読んだURLのhostとhelperのbrowser_domainがwww.youtube.comで一致しました。Safariのドメイン取得は確認できていますが、同じwindow内のタブ・URL切替の精度は未検証です。

全試行でテスト専用windowのみを閉じ、元の前面アプリへ戻しました。常駐Collector、自動起動設定、ActivityWatchサーバーは使っていません。実機の長時間idle境界、権限拒否、ロック・スリープ、裏タブ音声は未検証です。音声・ロック・スリープを必要とする製品判断はこのPoCだけでは行えません。


## 5分類評価の検証

明示した検証用TaskSnapshotとルールを使い、取得→正規化→評価→保存までを確認しました。以下の分類値は本人の実際の作業目的を評価した値ではありません。検証用タスクへの登録をテスト条件としています。

| 項目 | 確認結果 | 限界・残る確認 |
|---|---|---|
| 人工データ5分類 | 30分のT1200/R300/D180/U60/I60、B約89.286、Q約96.667%、Work1500秒を自動テスト | Iの根拠は人工LOCK。実ロック取得の証明ではない |
| 長い確定休止の式 | T300/I1500でB100、Q100%、W_rate約16.667%を自動テスト | 実スリープ取得は未実装 |
| pause / 欠測 / 重複 | pauseをEと全分類から除外、全面pauseの率はnull、重複LOCK/SLEEPは二重計上しない。欠測・短い脱線・全Unknownを自動テスト | 対話pause/resume、永続的なセッション復元は未実装 |
| Chromeの3文脈 | 38秒、観測38件、取得エラー0。github.comをT、example.comをD、developer.apple.comをRとして明示設定 | 人工のテスト目的。切替時刻の誤差評価ではない |
| 実ログ分類タイムライン | T8.017/R12.020/D15.018/U2.945/I0秒。Work20.037秒、B57.159、Q92.25%、W_rate52.729%。合計38秒 | サンプリング推定であり注視・理解の証明ではない |
| 実ログの無操作 | 310秒、観測310件、取得エラー0。無操作最大110.432秒、60秒以降の閾値true区間を確認。入力再開によるカウンタ減少も含む | 入力が再開されたため180/300秒の実境界は未到達。正確な手動入力時刻との誤差は未測定 |
| モード切替の再評価 | 同じ310秒ログをNORMAL/READING/VIDEOで再生し、すべて分類秒数の合計=310秒。READING/VIDEOは60秒超過だけでUnknownにしない | モード別閾値は自動テストも実施。実機180/300秒到達の確認とは区別する |
| 取得失敗と復帰 | 検証用wrapperで2回失敗後にnative helperへ復帰。8秒で実観測6件・失敗2件。障害を跨ぐ分析区間をUnknownにし、終了まで保存成功 | 全8秒の分類はU（検証設定の未登録等を含む）。実アプリ強制終了やsleep復帰の試験ではない |
| 安全な保存 | evaluationも0600。capture/events/analysis/evaluationにURL・title等のキーがなくdomainにpath/queryがないことを検品 | 設定に本人が入力したタスク名等は保存される |

実機証跡はGit除外のdata/five-class-browser/（captureとevaluation、切替命令時刻markers.json）、data/five-class-idle-observation/、data/five-class-mode-{normal,reading,video}/、data/five-class-recovery/に保存しました。専用Chromeウィンドウを閉じ、開始前の前面アプリへ戻しました。ブラウザの既存ウィンドウや設定は変更していません。

ロックは公開された画面スリープ／セッション切替通知と同義として扱いません。システムスリープには[NSWorkspace.willSleepNotification](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification)と[didWakeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification)が利用候補ですが、現行のサンプルごとに起動するhelperでは継続した通知監視ができません。記録中の継続監視Adapterを別途実装し、実際のsleep/wakeと欠損の照合が必要です。

Notion仕様全体を満たしたという判定ではありません。実ロック・スリープ、180/300秒の実境界、配布署名での権限拒否と復旧、長時間・強制終了時の耐久性を確認する必要があります。復帰時間・脱線エピソード・最長関連作業区間などの説明指標、永続WorkSession管理、報酬・iPhone側のPoCも別途残ります。


評価追加後の自動確認は、競合検出付き `go test -race -count=1 -json ./...`、`go vet ./...`、CLIビルドが成功しています。テストログはGit除外のdata/five-class-tests.jsonに保持し、実ログ検証とは区別します。
