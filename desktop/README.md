# デスクトップアプリ

ユーザーの作業状況を計測し，結果と獲得した報酬時間を表示する．[プロダクト全体像](../docs/spec/5.プロダクト全体像.md)を参照する．

## 採用構成

- 対象OS：macOS・Windows．対応バージョンとCPUアーキテクチャは実機検証後に確定する．
- アプリ基盤：Wails v2.17.0，Go 1.26.10，React 19，TypeScript 7，Vite 8．
- 画面と端末内Go：Wailsのバインディングとイベントで連携する．
- クラウドとの通信：端末内GoからConnect RPC / HTTPSでAPIへ接続する．DBへ直接接続せず，報酬の最終確定と残高管理はクラウド側で行う．
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

macOSでは既存のネイティブPoCから前面アプリ名・アプリID・入力アイドル時間・対応ブラウザーのドメインを取得する．raw URL，ページタイトル，キー入力内容，画面画像，ブラウザーのタブIDは保存しない．分類評価，報酬API，iPhone制限は未接続である．Windowsは引き続きデモモードである．

### 着手順序

1. Mac担当者がWails・React・TypeScript・Viteを初期化し，共通の型・bridge・状態管理・OS別UIの入口を実装する．
2. 同じデモで開始・一時停止・再開・終了・中止と，失敗・同期待ち・権限拒否を再現する．MacのWailsでGo呼び出しとイベントを確認し，[引き渡し条件](../docs/spec/7.デスクトップ共同開発.md#6-開発の順序と担当)を満たす．
3. Windows担当者が共通基盤を取得し，Windowsで起動・Go呼び出し・イベントを確認する．両担当がOS別UIを実装し，共通ファイルは作業ごとに編集担当を一人に決める．
4. 両OSで同じシナリオを確認し，実API・計測・同期を順に接続する．トレイ・保存・認証・配布の実機確認は画面デモの完成と分ける．

7画面すべての完成や，実API・トレイの完成を待ってからWindowsのUIに着手する必要はない．共通基盤の段階では通常ウィンドウで操作を確認し，実接続されていない機能はデモ／未対応と表示する．

### 起動手順の整備

### 起動・確認

Go 1.26.10，Node.js 22.12以上（推奨22または24），Wails CLI 2.17.0を用意する．MacでのWailsビルドにはXcode Command Line Toolsが必要．Windowsのビルド・起動にはWebView2 Runtimeが必要．

```sh
cd desktop/frontend
npm ci
npm run dev -- --host 127.0.0.1
```

ブラウザーで表示する場合は`http://127.0.0.1:5173/?platform=macos`または`?platform=windows`を開く．画面下の「デモの状態を切り替えて確認する」から状態を選ぶ．ブラウザーは従来どおりデモ表示である．macOSでWailsを起動するときは，ヘルパーを先にビルドするスクリプトを使う．

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

共通基盤の過去確認ではmacOS arm64のWails起動・Go呼び出し・イベント購読とアプリビルドが通っている．このローカル計測モードを追加した後のWailsビルドとmacOS権限の実機確認は，ビルド環境で確認する．Windowsは共通UIのブラウザプレビューのみで，Wails実機起動・ビルドは未確認．

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

macOSのローカル観測と作業状態の保存を実装している．実API，活動分類，報酬確定，メニューバー常駐，iPhone連携は未接続として扱う．

## 公式資料

- [Wails v2の概要](https://wails.io/docs/introduction/)
- [GoとWeb UIの連携](https://wails.io/docs/howdoesitwork/)
- [Wailsランタイム](https://wails.io/docs/reference/runtime/intro/)
