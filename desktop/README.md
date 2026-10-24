# デスクトップアプリ

ユーザーの作業状況を計測し，結果と獲得した報酬時間を表示する．[プロダクト全体像](../docs/spec/5.プロダクト全体像.md)を参照する．

## 採用構成

- 対象OS：macOS・Windows．対応バージョンとCPUアーキテクチャは実機検証後に確定する．
- アプリ基盤：Wails v2．端末内の処理をGo，画面をHTML・CSS・JavaScript/TypeScriptなどのWeb技術で実装する．画面用フレームワークは未選定．
- 画面と端末内Go：Wailsのバインディングとイベントで連携する．
- クラウドとの通信：端末内GoからConnect RPC / HTTPSでAPIへ接続する．DBへ直接接続せず，報酬の最終確定と残高管理はクラウド側で行う．

Wails v2はmacOS・Windowsをサポートし，GoとWeb UIを組み合わせられるため，今回のアプリ基盤として採用する．Goを利用していても，端末内の計測処理とクラウドの業務処理は分けて管理する．

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

このディレクトリは仕様整理段階であり，アプリの初期化・実機検証は未実施．

## 公式資料

- [Wails v2の概要](https://wails.io/docs/introduction/)
- [GoとWeb UIの連携](https://wails.io/docs/howdoesitwork/)
- [Wailsランタイム](https://wails.io/docs/reference/runtime/intro/)
