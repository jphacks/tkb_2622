# デスクトップアプリ

ユーザーの作業状況を計測し，結果と獲得した報酬時間を表示する．[プロダクト全体像](../docs/spec/5.プロダクト全体像.md)を参照する．

## 採用構成

- 対象OS：macOS・Windows．対応バージョンとCPUアーキテクチャは実機検証後に確定する．
- アプリ基盤：Wails v2.17.0，Go 1.26.10，React 19，TypeScript 7，Vite 8．
- 画面と端末内Go：Wailsのバインディングとイベントで連携する．
- クラウドとの通信：React → Wails bridge → Go → Connect API．ReactからAPIへ直接通信しない．GoはSupabase AuthへメールOTPを要求し，業務APIにはBearer access tokenだけを送る．
- 認証トークン：`99designs/keyring`を介してmacOS Keychain／Windows資格情報ストアへ保存する．OS資格情報ストアが利用できない場合に平文保存へ切り替えない．
- 画面・状態・接続契約は共通で，画面の見た目は[`docs/UI`](../docs/UI/)を基準にする．Mac・Windowsで異なるUI外枠は`frontend/src/platforms/`に置く．

Wails v2はmacOS・Windowsをサポートし，GoとWeb UIを組み合わせられるため，今回のアプリ基盤として採用する．Goを利用していても，端末内の計測処理とクラウドの業務処理は分けて管理する．

## Mac・Windowsの共同開発

Mac担当者が共通基盤を先に作り，その後にMac担当者とWindows担当者が各OSのUIを並行開発する．アプリ・Goモジュール・フロントエンドの依存は1つに保ち，OS別に雛形を複製しない．詳細は[デスクトップ共同開発](../docs/spec/7.デスクトップ共同開発.md)を参照する．

| 区分 | 配置・責務 |
| --- | --- |
| 共通UI | `frontend/src/pages`・`components`・`styles`．画面内容，共通部品，色・余白など |
| 共通状態・接続 | `frontend/src/state`・`bridge`・`fixtures`．表示用の型，操作，イベント，デモシナリオ |
| Mac UI | `frontend/src/platforms/macos`．Macの外枠・配置・スタイル |
| Windows UI | `frontend/src/platforms/windows`．Windowsの外枠・配置・スタイル |
| Go | セッション状態・コマンド・イベント契約は共通．OS別起動設定は分離 |

ブラウザプレビューは従来どおり`DemoBridge`を使い，表示確認用データだけを扱う．macOSのWailsアプリはローカル計測モードで起動し，作業状態をユーザー設定フォルダーの`Focus Link/desktop-state.json`へ保存する．観測記録は同じフォルダーの`sessions/<session-id>.jsonl`へ保存する．保存ディレクトリは`0700`，ファイルは`0600`で作成する．

macOSでは既存のネイティブPoCから前面アプリ名・アプリID・入力アイドル時間・対応ブラウザーのドメインを取得する．raw URL，ページタイトル，キー入力内容，画面画像，ブラウザーのタブIDは保存・送信しない．分類済み区間をConnect APIへ送り，報酬はセッション内で記録する．有効なiPhoneがないセッションは記録専用として開始し，iPhone制限処理は行わない．Windowsは計測をデモモードとする．

### API接続の範囲

デスクトップのWailsアプリはメールOTPで認証し，起動時にEnsureUser，このPCの端末登録，ListTasksを順に呼ぶ．設定画面ではサーバー上のタスクを表示・作成・編集できる．初回の有効なOTPでSupabase Authユーザーを自動作成する．ブラウザプレビューは引き続きDemoBridgeを使い，実APIへ接続しない．

起動プロセスに次の環境変数を設定する．値はアプリへ書き込まず，`.env`やソース管理へ追加しない．`SUPABASE_PUBLISHABLE_KEY`は公開用キーであり，サービスロールキーは使わない．

| 環境変数 | 用途 |
| --- | --- |
| `FOCUS_LINK_API_BASE_URL` | Connect APIのベースURL（本番HTTPS，ローカル開発はloopback HTTP可） |
| `FOCUS_LINK_SUPABASE_URL` | SupabaseプロジェクトのルートURL（`/auth/v1`より前） |
| `FOCUS_LINK_SUPABASE_PUBLISHABLE_KEY` | Supabaseのpublishable／anonキー |

Supabase側ではメールOTPのテンプレートに`{{ .Token }}`を含め，メール送信設定を行う．未設定の環境変数，API到達不能，資格情報ストア未使用は設定画面に表示する．

ログイン中の作業ではStartSession／GetCurrentSessionでサーバーセッションを開始・復元し，UploadActivityBatchで分類済み区間と計測状態を送る．新規セッションは仮ポリシー v2（T+Rの5分ごとに60秒，Q>=70%，K>=5分，計測正常）でサーバーが途中付与し，セッション開始時のルール版を固定する．付与後に条件を外れた場合は追加付与を止めるが，過去の付与や利用は取り消さない．一時停止・再開・終了・中止もConnect APIへ同期する．有効なiPhoneが未登録ならSessionの`tracking_only`がtrueとなり，制限を適用せず作業記録とセッション内報酬を保存する．iPhone登録済みで制限ポリシーが無効の場合は開始を拒否する．報酬は次のセッションへ持ち越さず，終了・中止時に未使用分を破棄する．終了後はAPI確定の獲得・利用枠充当・破棄秒数をフィードバックと履歴に表示する．ブラウザプレビューは引き続きDemoBridgeを使い，実APIへ接続しない．

### 着手順序

1. Mac担当者がWails・React・TypeScript・Viteを初期化し，共通の型・bridge・状態管理・OS別UIの入口を実装する．
2. 同じデモで開始・一時停止・再開・終了・中止と，失敗・同期待ち・権限拒否を再現する．MacのWailsでGo呼び出しとイベントを確認し，[引き渡し条件](../docs/spec/7.デスクトップ共同開発.md#6-開発の順序と担当)を満たす．
3. Windows担当者が共通基盤を取得し，Windowsで起動・Go呼び出し・イベントを確認する．両担当がOS別UIを実装し，共通ファイルは作業ごとに編集担当を一人に決める．
4. 共通Go bridgeから認証・PC登録・タスクAPIを接続する．続いて計測・セッション／報酬同期を接続する．トレイ・配布の実機確認は画面デモと分ける．

macOSではメニューバーのStatus Itemをクリックすると，開始・一時停止・再開・終了・中止を操作するネイティブポップオーバーを表示する．「ダッシュボード」「これまでの記録」「設定」から既存のWails画面を開ける．ポップオーバーの操作は既存のGoセッションAPIへ渡す．Wailsウィンドウを閉じてもアプリと計測は継続し，メニューバーの右クリックメニューから「終了」を選ぶとアプリを終了する．Windowsのトレイ対応は未実装である．

### 起動手順の整備

### 起動・確認

Go 1.26.10，Node.js 22.12以上（推奨22または24），Wails CLI 2.17.0を用意する．MacでのWailsビルドにはXcode Command Line Toolsが必要．Windowsのビルド・起動にはWebView2 Runtimeが必要．

```sh
cd desktop/frontend
npm ci
npm run dev -- --host 127.0.0.1
```

ブラウザーで表示する場合は`http://127.0.0.1:5173/?platform=macos`または`?platform=windows`を開く．画面下の「デモの状態を切り替えて確認する」から状態を選ぶ．ブラウザーは従来どおりデモ表示である．実APIを使う場合はConnect API URLとSupabase Auth URL・公開キーを起動プロセスの`FOCUS_LINK_*`環境変数に設定する．ローカルAPIには`http://127.0.0.1:8080`を指定する．`make -C backend up`はPostgreSQL・マイグレーション・APIを起動するが，Authは`backend/.env`で指定したSupabaseプロジェクトを使う．

#### Windowsでの起動

Windows版はWindowsのPowerShellとWSLのどちらからでも準備・起動できる．`make`がなければ，Windowsでは`winget install ezwinports.make`で入れる．

```sh
make -C desktop setup-win   # 初回・依存更新時
make -C desktop up-win      # wails devで起動（終了はCtrl+C）
```

| 実行場所 | 動作 |
| --- | --- |
| Windows（PowerShell） | Windows側にcloneしたリポジトリでそのまま実行する |
| WSL | `desktop/`をWindows側（既定は`%LOCALAPPDATA%\tkb_2622\desktop`．`WIN_DESKTOP_DIR`で変更可）へ同期し，go.modの`replace`が参照する`poc/macos-native`も同じ相対位置へ同期して，`powershell.exe`でそこから実行する．`up-win`の実行中はWSLでの編集を1秒ごとに同期し，ホットリロードに反映する |

WSLのリポジトリをWindowsから直接動かさないのは，Windowsのnpmが`\\wsl.localhost\...`上でスクリプトを実行できず，`node_modules`のネイティブ部品もOSごとに異なるためである．同期先の`node_modules`・`wailsjs`等はWindows側で生成し，同期で上書き・削除しない．同期先で編集した内容はWSLへ戻らないため，編集はWSL側で行う．

`setup-win`はGo・Node.js・WebView2 Runtimeがなければwingetでインストールし，go.modと同じ版のWails CLI，Goモジュール，npmパッケージを導入して`wails doctor`を表示する．GoのbinをユーザーのPATHへ追加する．Node.jsが未対応の版（22.12未満等）の場合は自動で更新せず停止する．`package-lock.json`を変更したら`setup-win`を再実行する．処理は`scripts/windows/`（PowerShellの`setup.ps1`・`up.ps1`，WSL用の`wsl.sh`）にある．

配布用のWindowsアプリは，Windows側の`desktop`（WSLから使う場合は同期先）で`wails build`を実行してビルドする．`build/bin/focus-link.exe`が生成される．アイコン・バージョン情報・マニフェストは`build/windows/`に置く．

```sh
cd desktop
sh build/dev-macos.sh
```

配布用のmacOSアプリは次のコマンドでビルドする．ビルド後，`native-collector`はアプリバンドル内へコピーされる．

```sh
cd desktop
sh build/build-macos-app.sh
```

対応ブラウザーのドメイン取得にはmacOSのオートメーション許可が必要になる場合がある．許可しない場合もアプリ名とアイドル時間の観測を続け，取得できなかったサンプルは報酬評価に使わない．

共通基盤の過去確認ではmacOS arm64のWails起動・Go呼び出し・イベント購読とアプリビルドが通っている．このローカル計測モードを追加した後のWailsビルドとmacOS権限の実機確認は，ビルド環境で確認する．Windows 11 amd64では，WSLからの`make -C desktop setup-win`・`up-win`によるWails起動・Go呼び出し・イベント受信，`go test ./internal/...`，`wails build`が通っている．Windowsの計測はデモモードのままである．

一時的な実行ログ・実機検証結果はPRなどに記録し，本READMEには継続利用する手順を残す．

## OSごとのPoC

Wailsの採用だけで，他アプリの最前面情報・入力・アイドル・閲覧URLを取得できると判断しない．OS固有のAPIや追加ライブラリの利用可否，必要な権限を調査し，macOS・Windowsそれぞれで検証する．

計測処理は共通のGoインターフェースとOS別実装に分ける方針とする．取得できない情報や権限拒否を区別し，判定不能な状態を正常な作業時間として扱わない．GoからネイティブAPIへ接続する方法もPoCで確認する．

| 確認対象 | 検証内容 |
| --- | --- |
| 起動・画面 | 両OSでビルド・起動し，Web UIとGoの呼び出し・イベント通知が動く |
| 計測 | 最前面アプリ，入力・アイドルなどの取得可否と権限，読む作業を含む判定の限界 |
| 継続動作 | 最小化，バックグラウンド移行，スリープ・復帰時のタイマーと記録 |
| API連携 | Go側から作業記録を送信し，確定した報酬を画面に表示できる |
| 配布 | 対象OSでのビルド環境，署名・配布方法，必要なランタイム |

## 開発環境

GoとNode.js / npmに加えて，macOSの開発にはXcode Command Line Tools，Windowsでの動作にはWebView2 Runtimeが必要．詳細は[Wails v2のインストール手順](https://wails.io/docs/gettingstarted/installation/)を参照する．Wailsはv2系を使用し，具体的なバージョンはプロジェクト初期化時に固定する．

macOSのローカル観測・分類・作業状態保存，メールOTP・PC登録・タスク設定，作業セッションと分類済み活動区間のConnect同期，セッション内報酬の取得，メニューバー常駐を実装している．有効なiPhoneがない場合は記録専用セッションとなる．iPhone制限の実機連携，Windowsネイティブ計測・トレイは未接続である．Supabase AuthのSMTP／OTPテンプレートと接続URL・公開キーは環境ごとに設定する．

## 公式資料

- [Wails v2の概要](https://wails.io/docs/introduction/)
- [GoとWeb UIの連携](https://wails.io/docs/howdoesitwork/)
- [Wailsランタイム](https://wails.io/docs/reference/runtime/intro/)
