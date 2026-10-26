# tkb_2622 — 開発資料と Skills

Focus Linkの実装・設計・検証資料を管理するリポジトリです。PCでの実作業をiPhoneの娯楽アプリの利用可能時間につなげ、大学生や社会人の学業・仕事における作業開始と継続を支援します。Desktop・iPhone・Go API・インフラの実装を備えます。プロダクトの目的と仮説は戦略資料、構成と業務ルールは仕様資料、起動方法と検証実績は各コンポーネントのREADMEを参照してください。

## ディレクトリ

| ディレクトリ | 用途・現状 |
| --- | --- |
| [backend/](backend/) | Go APIの実装。PostgreSQL，identity・focus・reward・restriction・groupのRPC，通知Outbox・APNs配信処理，HTTP／Connectヘルスチェック，Docker起動手順 |
| [desktop/](desktop/) | Wails v2 / Go / Reactアプリ。作業セッション・履歴・認証のAPI接続，macOSネイティブ計測とメニューバー，Windowsタスクトレイを実装。Windows計測はデモモード |
| [mobile/](mobile/) | SwiftUIアプリ。ホーム・認証・履歴・グループのAPI接続，Screen Time制御・利用時間監視拡張，集中ルームWidgetを実装。[画面対応と検証範囲](mobile/README.md)を参照 |
| [infra/](infra/) | TerraformでCloudflare Workers・Cloud Run・Secret Manager・CI連携を定義。入口の検査・レート制限・直接アクセス対策を実装。[適用手順と検証範囲](infra/README.md)を参照 |
| [poc/](poc/) | 機能検証用。[macOS操作ログPoC](poc/macos-native/README.md)は拡張機能なしの自前取得を検証。 [iOS報酬時間PoC](poc/ios-reward-time/)、[友だち集中のウィジェット／Dynamic Island PoC](poc/ios-friend-focus-widget/)、手順は [README](poc/README.md) を参照 |
| [docs/](docs/) | 仕様・設計資料 |

## 戦略資料

| 資料 | 状態 |
| --- | --- |
| [プロダクト戦略](docs/strategy/1.プロダクト戦略.md) | 目的・課題と仮説・想定ユーザーストーリー・差別化の核を記載 |
| [機能・非機能要件](docs/strategy/2.機能-非機能要件.md) | アプリ・バックエンドの機能，品質要件案，受け入れシナリオ，未決事項を記載 |
| [PoC戦略](docs/strategy/3.poc戦略.md) | Mac/API/iPhone通信の確認実績，Screen Time・Widget・Dynamic Islandの実装と実機受け入れ項目を記載 |
| [機能分担戦略](docs/strategy/4.機能分担戦略.md) | 検討中：4人の担当案・責任の境界・並行開発の進め方を記載 |
| [デスクトップアプリ配布](docs/strategy/5.デスクトップアプリ配布.md) | OS別のビルド・配布形式，署名・公証，GitHub ReleasesとリリースCIの導入方針を記載 |

## 仕様資料

| 資料 | 状態 |
| --- | --- |
| [プロダクト全体像](docs/spec/5.プロダクト全体像.md) | 採用構成・Mermaid全体図・各要素の役割・利用の流れを記載 |
| [バックエンド構成](docs/spec/1.バックエンド構成.md) | モジュラーモノリス，クリーンアーキテクチャの依存方向，横断処理・トランザクション方針を記載 |
| [API仕様書](docs/spec/3.API仕様書.md) | タスク・セッション・報酬・制限・グループ・通知のAPI，実装対応表，小休憩モデルの業務動作と受け入れ条件を記載 |
| [ドメインモデル定義](docs/spec/4.ドメインモデル定義.md) | 途中報酬・小休憩，終了時の全未使用報酬破棄・制限解除，グループ・通知のモデルを記載 |
| [iOSクライアント開発フロー](docs/spec/6.iOSクライアント開発フロー.md) | mobileの認証・画面別API・端末制限の実装，Release設定，段階ごとの受け入れ条件を記載 |
| [インフラ構成](docs/spec/2.インフラ構成.md) | Supabase PostgreSQLの接続・権限・環境設定，実装済みTerraformと環境別の接続確認手順を記載 |
| [認証構成](docs/spec/6.認証構成.md) | Supabase Auth採用，ログイン方法の比較，JWT検証，業務User対応の契約案を記載 |
| [フロントエンド構成](docs/spec/6.フロントエンド構成.md) | Wails v2・React・TypeScript・ViteとSwiftUIの構成，両クライアントのAPI接続，OS別の常駐・計測と検証方針を記載 |
| [デスクトップ共同開発](docs/spec/7.デスクトップ共同開発.md) | Mac担当者が先行する共通基盤，OS別UIの境界・配置・接続契約，引き渡し条件・分担・検証を記載 |
| [Desktop・iPhone連携の構成と受け入れ確認](docs/spec/8.desktop-mobile連携の現状と課題.md) | 同一アカウントの認証・作業状態・残高・制限状態の連携，環境設定と受け入れ手順を記載 |

## 検証・確認資料

| 資料 | 状態 |
| --- | --- |
| [Mobileの検証手順・実績](mobile/README.md) | host・Simulator・ログイン画面UIのテスト実績，APIエラーと再試行，実機受け入れ手順を記載 |
| [macOS操作ログの実機結果](poc/macos-native/docs/results.md) | 前面アプリ・ブラウザードメインの取得，5分類評価，無操作境界と復帰の検証結果を記載 |

## UIモック

画面遷移と表示項目の参照用HTMLです。モックの状態と仕様との対応・実装時の扱いは[UIモック案内](docs/UI/README.md)，業務ルールは仕様資料を正とします。

| 画面群 | モック |
| --- | --- |
| Macの作業結果・履歴・設定・セッション操作 | [作業後フィードバック](docs/UI/01_Mac_作業後フィードバック.html)，[これまでの記録](docs/UI/02_Mac_これまでの記録.html)，[設定](docs/UI/03_Mac_設定.html)，[メニューバー開始前](<docs/UI/04_Mac_メニューバー(開始前).html>)，[作業中](<docs/UI/05_Mac_メニューバー(作業中).html>)，[一時停止中](<docs/UI/06_Mac_メニューバー(一時停止中).html>)，[起動時ポップアップ](docs/UI/07_Mac_アプリ起動時ポップアップ.html) |
| iPhoneの作業状態・制限・残高利用 | [作業中ホーム](docs/UI/08_iPhone_作業中ホーム.html)，[制限画面](<docs/UI/09_iPhone_制限画面(Shield).html>)，[残高を使う](docs/UI/10_iPhone_残高を使う.html)，[利用中](docs/UI/11_iPhone_利用中.html) |
| iPhoneの設定・グループ・通知 | [設定](docs/UI/12_iPhone_設定.html)，[グループ](docs/UI/13_iPhone_グループ.html)，[通知の例](docs/UI/14_iPhone_Mac_通知の例.html) |

資料が空の場合は仕様未定として扱います。実装に必要な仕様を決めたら該当資料に記載し、資料の追加・移動や記入状況の変更に合わせてこの索引を更新します。

## 開発用 Skills

| Skill | 用途 |
| --- | --- |
| [docs-navigator](.claude/skills/docs-navigator/SKILL.md) | 仕様・設計の参照先と未決事項を確認 |
| [issue-create](.claude/skills/issue-create/SKILL.md) | 要望を目的・範囲・完了条件付きの Issue に整理 |
| [issue-resolve](.claude/skills/issue-resolve/SKILL.md) | Issue の仕様確認・実装・検証・結果報告 |

Skills の正本は `.claude/skills/` です。`.codex/skills` と Codex の読み込み先 `.agents/skills` は、ともに `../.claude/skills` を参照する相対シンボリックリンクです。更新は正本に行います。リンクが保持される環境でチェックアウトしてください。

仕様を確認し、必要に応じて Issue に作業を整理してから実装・検証を進めます。Issue・PR の本文は [Issue テンプレート](.github/ISSUE_TEMPLATE/feature.md) と [PR テンプレート](.github/PULL_REQUEST_TEMPLATE.md) を利用できます。
