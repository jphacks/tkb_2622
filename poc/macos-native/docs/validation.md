# 実機確認手順

この文書は macOS native collector の期待値と、実機での確認記録方法を定めます。実測値は [results.md](results.md) に追記してください。下表は検証用チェックリストです。個々の実施状態・証跡は results.md を正本とします。

## 共通の記録ルール

各項目に、期待値、実測値、状態、差・誤差、取得不能だった情報、仮説、次の対応を記録します。状態は 未実施 / 実施中 / 期待どおり / 差異あり / 取得不能 のいずれかにします。実施時は macOS の版・CPU、ブラウザー名と版、focuslog / native-collector のビルド識別情報、実行コマンド、開始・終了時刻、再現手順を残します。JSON は data/ 以下に出力し、証跡には raw URL、ページタイトル、個人情報を転記しません。必要な場合は domain のみを残してください。

テストは対応するブラウザーや権限を本人が操作して行います。collector はブラウザーを前面にしたりタブを切り替えたりしません。Apple Events の許可ダイアログを見た本人が許可・拒否を選びます。

## 実機シナリオ

| ID | 手順 | 期待値 | 実測 / 状態 | 差・誤差 / 取得不能 | 仮説 / 次の対応 |
|---|---|---|---|---|---|
| OBS-01 | Terminal、Finder などを順に前面にして check または snapshot を実行する | app ID と app name が前面アプリに一致し、時刻が付く。idle seconds と idle observed at が同じ観測として記録される | 未実施 | — | 実機結果後に記入 |
| CHR-01 | Chrome を前面にし、GitHub と YouTube のページを順に開いて snapshot を取る | 前面が Chrome の場合に限り domain が github.com / youtube.com と変わる。raw URL とタイトルは出力にない | 未実施 | — | 実機結果後に記入 |
| SAF-01 | Safari を前面にし、GitHub と YouTube のページを順に開いて snapshot を取る | 前面が Safari の場合に限り domain が github.com / youtube.com と変わる。raw URL とタイトルは出力にない | 未実施 | — | 実機結果後に記入 |
| OBS-02 | Chrome / Safari を開いたまま、別アプリを前面にして snapshot を取る | 前面アプリだけを記録し、背景ブラウザーの domain / tab ID は採用しない | 未実施 | — | 実機結果後に記入 |
| RACE-01 | Chrome / Safari のタブ照会中に前面アプリを切り替える | 前後で前面アプリが変わった観測は browser status が foreground_changed となり、domain / tab ID を破棄する | 未実施 | — | 競合を再現できなかった場合は取得不能として記録 |
| AUT-01 | Chrome / Safari が前面の状態で初回照会し、本人が Automation を許可する | Apple Events が応答し、対応ブラウザーでは domain と tab ID を返す | 未実施 | — | macOS が表示した送信元と許可対象を記録 |
| AUT-02 | システム設定で送信元から Chrome / Safari への Automation を拒否した状態で照会する | browser status が permission_denied となり domain / tab ID は空。raw AppleScript エラーや URL は出力しない | 未実施 | — | status / reason と CLI 終了結果を照合 |
| WIN-01 | 前面ブラウザーをウィンドウなしの状態にして照会する | browser status が no_window となり、domain / tab ID は空 | 未実施 | — | OS / ブラウザーの状態も記録 |
| BROW-01 | Firefox など対応外ブラウザーを前面にする | browser status が unsupported。対応外の URL を問い合わせない | 未実施 | — | 対応判定を実測と照合 |
| IDLE-01 | 前面アプリを変えず入力を止め、60 秒は 59 / 60 / 61、180 秒は 179 / 180 / 181、300 秒は 299 / 300 / 301 秒付近をまたぐ観測を取る | idle seconds と idle observed at から連続アイドル開始時刻を求め、idle_over_threshold の区間フラグを直接比較する。閾値は包含扱いで、t より前は false、t 以降は true となる。読書・思考・離席分類はしない | 未実施 | — | 境界の正確な値を作れない場合は、実測した小数値と比較結果を残す |
| ERR-01 | AppleScript 応答が timeout する条件と、helper 呼び出しが --timeout に達する条件を別々に確認する | AppleScript timeout は browser status / reason に区別して記録し、外側の helper timeout は取得失敗にする。permission_denied / no_window と混同せず、子プロセスの生エラー本文は出さない | 未実施 | — | それぞれ status、reason、取得失敗、終了コードを記録 |
| STATE-01 | 画面ロックとシステムスリープを別々に含めて record する | lock state / sleep state は null のまま。中断や再開後の未観測時間は unknown として扱い、過去へ補完しない | 未実施 | — | スリープ前後の時刻差、欠損、last success を記録 |
| AUDIO-01 | Chrome の裏タブで音声を再生し、別アプリを前面にする | audible は null。background audio を入力アイドルや前面アプリから推測しない | 未実施 | — | 実機で音が出ていることと取得不能を分けて記録 |
| GAP-01 | record の poll 間にアプリ切替を挟み、さらに helper の timeout / 終了を含める。通常の Ctrl-C と強制終了も分ける | poll 間の全状態を観測したとは扱わない。取得失敗を記録し、欠損区間・セッション末尾を未知として残す。Ctrl-C / SIGTERM は途中結果を保存し、強制終了は保存されない場合がある | 未実施 | — | 観測数、失敗理由、unknown seconds、最終成功時刻を記録 |
| DUP-01 | exact duplicate、同時刻で状態が異なる観測、時刻の順序が逆の観測を含む Capture JSON を replay する | exact duplicate は duplicate snapshot count に現れて二重計上されない。同時刻で状態が異なる観測は該当区間を unknown にする。順序逆の入力は観測時刻順に並ぶ | 未実施 | — | capture の入力順、events の時刻順、intervals と件数を照合 |
| OUT-01 | 新しい --out に保存後、同じ --out を再指定する。出力物の権限と内容を確認する | 新規出力先だけを作り、既存先は上書きせずエラー。ディレクトリー 0700、JSON ファイル 0600。capture.json / events.json / analysis.json に URL とタイトルがない | 未実施 | — | stat と出力 JSON を確認し、実測値を記録 |
| REPLAY-01 | testdata/sample.json を replay する | ライブ helper を呼ばず、フィクスチャから analysis.json と report を生成する | 未実施 | — | 出力とフィクスチャの要約を照合 |

IDLE-01 は、取得した idle seconds が整数境界と一致することを前提にしません。60 / 180 / 300 秒それぞれで境界前後の実測値を残し、境界値の包含規則は実装と実測の両方を確認してください。

## 記録用テンプレート

results.md の各項目に次の情報を記録します。

- 期待値:
- 実測値 / 証跡:
- 状態:
- 差・誤差:
- 取得不能だった情報:
- 仮説:
- 次の対応:


## 5分類の評価確認

同じCaptureを異なるSession設定でreplayし、分類タイムラインと集計を照合します。実作業のルールを推測せず、検証用の明示したタスクを使います。

| ID | 条件 | 期待値 |
|---|---|---|
| FOCUS-01 | 主作業・関連先・無関係先を明示登録しrecord/replay | TとRは同じ重み、未知の先はU、設定はevaluation.jsonへ固定保存 |
| FOCUS-02 | 同一無関係先9.999秒・10秒・繰り返す短い訪問 | 10秒で開始へ遡及D。短い訪問を足し合わせずU、Qが低下 |
| FOCUS-03 | 同一ログをNORMAL/READING/VIDEOで再評価 | 選んだ60/180/300秒の閾値だけを使う。閾値到達以降はU |
| FOCUS-04 | pause、全pause、欠測、全U | pauseは5分類とEから除外、欠測はU。K=0ならB=null、E=0ならQ/W_rate=null |
| FOCUS-05 | 人工LOCK/SLEEP区間、重複根拠、pauseとの重なり | Iを関連作業に含めず二重計上せず、pauseを優先。実機取得成功とは区別 |
| FOCUS-06 | helperの失敗後に取得を復帰 | 欠測をUに残して復帰後の観測から評価し、末尾のT/Rを延ばさない |

サンプル再生手順はREADMEの`--session`例、自動テストは`go test -race ./...`を使います。各結果でT+R+D+U+I=E、E+pause=セッション幅を確認します。
