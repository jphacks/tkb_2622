# macOS native collector PoC

ActivityWatch やブラウザー拡張に依存せず、macOS の前面アプリ、入力アイドル時間、前面にある Chrome / Safari の現在タブのホスト名をローカルで記録する検証用 CLI です。常駐サービスではなく、明示したコマンドの実行中だけ観測します。現時点で Windows は未対応です。

## 取得する情報と制約

- Swift helper は NSWorkspace から前面アプリの bundle ID と表示名を取得し、Core Graphics の CGEventSource から任意の入力イベントを受け取ってからの秒数と、その観測時刻を取得します。前面アプリは「キーイベントを受け取るアプリ」として定義されています。詳細は [NSWorkspace.frontmostApplication](https://developer.apple.com/documentation/appkit/nsworkspace/frontmostapplication) と [CGEventSource](https://developer.apple.com/documentation/coregraphics/cgeventsource) を参照してください。
- 前面アプリの bundle ID が Chrome または Safari のときだけ Apple Events で現在タブの URL を読みます。ChromeではタブIDも取得します。Safariの公開スクリプト定義には永続的なタブIDがないため、tab_idはnullのままです。URL はプロセス内で URLComponents.host に縮約して小文字化し、domain として扱います。JSON や標準出力に保存するフィールドは domain と tab ID です。raw URL とページタイトルは取得結果に含めず、保存もしません。Chrome の AppleScript インターフェイスについては [Chromium の AppleScript 資料](https://www.chromium.org/developers/design-documents/applescript/)を参照してください。
- 前面アプリが Apple Events の照会前後で変わった場合、その観測の browser domain と tab ID を破棄します。Chrome / Safari を前面に切り替えたり、タブを変更したりする命令は送りません。Firefox など対応外ブラウザーは unsupported として扱います。
- audible、画面ロック、スリープ状態は取得しないため、該当 JSON フィールドは null です。Chrome の audible 情報は拡張向けの [Chrome Tabs API](https://developer.chrome.com/docs/extensions/reference/api/tabs/) で提供されますが、この PoC は拡張もブラウザー内 JavaScript も使いません。Apple Events では音声の再生有無を照会していません。バックグラウンド再生、ロック、スリープの状況をアイドル値から推測して補いません。
- idle seconds は入力イベントからの経過時間です。読書、思考、離席、集中度を判定する値ではありません。60 / 180 / 300 秒は入力アイドル値から直接見る候補閾値で、読書・思考と離席の分類には使いません。
- snapshot の間引き観測から推定する前面時間であり、連続した前面状態を保証しません。分析は同じ前面アプリ / browser state の有効な観測間だけを推定し、状態変更や許容を超える観測間隔は unknown として残します。record では最大許容間隔を poll の 3 倍（3 秒以上、30 秒以下）として扱います。最後の観測からセッション末尾までを延長して埋めません。

## 必要な環境

開発確認対象は macOS 26.6.2 arm64、Swift 6.4、Go 1.27.3 です。これより前の macOS の最低対応版は定めていません。ビルドにはmacOS、swiftc（Xcode Command Line Tools）、Goが必要です。go.modはGo 1.22を指定していますが、動作検証は1.27.3で行いました。別環境では[Go公式手順](https://go.dev/doc/install)でGoを導入してください。この作業環境の.tools/goはローカル配置でGitには含めません。

## ビルドと実行

コマンドは poc/macos-native を作業ディレクトリーにして実行します。--helper に渡すパスも、そのコマンドを起動した作業ディレクトリーからの相対パスです。

    cd poc/macos-native
    if [ -x .tools/go/bin/go ]; then export PATH="$PWD/.tools/go/bin:$PATH"; fi
    ./native/build.sh
    go build -o bin/focuslog ./cmd/focuslog

    bin/focuslog check --helper bin/native-collector --timeout 8s
    bin/focuslog snapshot --out data/snapshot-1 --helper bin/native-collector --timeout 8s
    bin/focuslog record --duration 15s --poll 1s --out data/session --helper bin/native-collector --timeout 8s
    bin/focuslog replay --input testdata/sample.json --out data/replay

check は現在の状態を一度取得し、snapshot JSON を標準出力に出します。snapshot は一度だけ観測し、record は開始時に一度取得してから指定 poll 間隔を目安に観測します。helper の応答が遅い場合や timeout が起きた場合、poll が抜けることがあります。replay は保存済み Capture JSON を解析するオフラインコマンドで、macOS のライブ取得や Automation 権限を使いません。snapshot / record / replay は --out を省略すると分析結果を標準出力に出します。check はファイルを作らず snapshot を出力します。

--out は新規ディレクトリーでなければなりません。既存の出力先を指定するとエラーにして上書きを避けます。作成する出力ディレクトリーは mode 0700、JSON ファイルは mode 0600 です。保存するファイルは capture.json（スナップショットと取得失敗）、events.json（イベント列）、analysis.json（区間と集計）です。browser domain、前面アプリ名、tab ID、観測時刻、アイドル秒数は記録されます。raw URL とタイトルは保存しません。出力には作業時間や閲覧先が含まれ得るため、共有前に中身を確認してください。

通常の Ctrl-C / SIGTERM で record を終了すると、その時点までの観測を保存します。強制終了では保存処理が実行されない場合があります。ヘルパーが停止した場合や poll に欠損がある場合は取得失敗と unknown 時間を確認し、欠けた区間を観測済みと解釈しないでください。AppleScript の permission_denied、timeout、no_window は状態・理由を分けて記録します。

## Automation 権限

前面にある Chrome / Safari のタブを読むには、macOS の Automation 許可が必要です。初回に表示されるダイアログは macOS を操作する本人が判断してください。許可する場合は、ダイアログの送信元が Chrome または Safari を制御できるよう許可します。拒否した場合は browser status が permission_denied になり、domain と tab ID は保存されません。許可状態は「システム設定 > プライバシーとセキュリティ > オートメーション」で確認・変更できます。macOS は別アプリの操作にユーザーの許可を求めます（[Apple Support: アプリとWebサイトによる他のアプリの自動操作を許可する](https://support.apple.com/guide/mac-help/allow-apps-and-websites-to-automate-and-control-other-apps-mchl108e1718/mac)）。

この PoC の build script は Swift の実行ファイルをローカルに生成するだけで、署名・notarization・アプリバンドル・権限説明文を作りません。配布用ビルドでは Apple Events を送るプロセスの権限設計を確定し、アプリバンドルに必須の NSAppleEventsUsageDescription を用意してください。Hardened Runtime を有効にして配布する場合は、Apple Events entitlement の要否を確認します。Mac App Store の外で配布する場合は Developer ID 署名と notarization を行い、配布物の署名主体で Automation の許可ダイアログを実機確認してください（[NSAppleEventsUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)、[Apple Events entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)、[macOS ソフトウェアの notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)）。

## 文書

- [実機確認手順](docs/validation.md) — 期待値、再現手順、証跡の残し方。
- [実機結果](docs/results.md) — 確認済みのドメイン取得と、精度・権限拒否などの未検証事項。

旧 ActivityWatch PoC の作業物は .archive/activitywatch/ に保全し、現在の macOS native collector とは分けています。.archive/ は Git 対象外です。過去の証跡を消去したり、現行 PoC の入力と見なしたりしないでください。

## 自動テストとサンプル再生

PoCディレクトリ内でGoがPATHに入った状態で実行します。

```sh
go test -race ./...
go vet ./...
bin/focuslog replay --input testdata/sample.json --out data/replay-new
```

サンプルは12秒の人工データです。アプリ切替、GitHub／YouTube、ブラウザ権限拒否、Collectorの失敗を含み、推定4秒・Unknown 8秒になります。実機結果や集中時間を示すものではありません。サンプル内のfixture_collector_timeoutは意図した欠損です。

Reportのapplications/domainsは有効な観測点で見つかった一覧です。単発観測のアプリ時間は0秒で、時間を集計するのは前面情報が整合した隣接観測間だけです。イベントは観測点なのでstart_at=end_at、区間の品質はsample_based_estimateまたはunknownです。読書・思考・集中・報酬の判定は行いません。

Sanitizeは取得元/schemaの不一致をネイティブ由来に書き換えません。不正な観測は理由付きでUnknownにします。replayはこの形式で自分が管理する保存データを入力してください。アプリ表示名や理由欄に手動で機密情報を混入させたJSONまで匿名化する機能ではありません。
