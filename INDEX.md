# tkb_2622 — 開発資料と Skills

新規アプリの初期開発用リポジトリ。PCでの実作業をiPhoneの娯楽アプリの利用可能時間に変え、大学生や社会人の学業・仕事における作業開始と継続を動機づける構想です。詳細仕様は策定中です。プロダクトの目的と仮説は下記の戦略資料、バックエンドの構成方針は仕様資料を参照してください。

## ディレクトリ

| ディレクトリ | 用途・現状 |
| --- | --- |
| [backend/](backend/) | Go APIの最小実装。Userテーブル，HTTP／Connectヘルスチェック，Docker起動手順 |
| [desktop/](desktop/) | macOS・Windows向けのWails v2 / Go / Web UIアプリ用 |
| [mobile/](mobile/) | スマホの使用を制限するアプリ用 |
| [infra/](infra/) | インフラ構成の管理用 |
| [poc/](poc/) | 機能検証用。[macOS操作ログPoC](poc/macos-native/README.md)は拡張機能なしの自前取得を検証 |
| [docs/](docs/) | 仕様・設計資料 |

## 戦略資料

| 資料 | 状態 |
| --- | --- |
| [プロダクト戦略](docs/strategy/1.プロダクト戦略.md) | 目的・課題と仮説・想定ユーザーストーリー・差別化の核を記載 |
| [機能・非機能要件](docs/strategy/2.機能-非機能要件.md) | アプリ・バックエンドの機能，品質要件案，受け入れシナリオ，未決事項を記載 |
| [PoC戦略](docs/strategy/3.poc戦略.md) | 追加要件の実機検証計画を記載．検証は未実施 |
| [機能分担戦略](docs/strategy/4.機能分担戦略.md) | 検討中：4人の担当案・責任の境界・並行開発の進め方を記載 |

## 仕様資料

| 資料 | 状態 |
| --- | --- |
| [プロダクト全体像](docs/spec/5.プロダクト全体像.md) | 採用構成・Mermaid全体図・各要素の役割・利用の流れを記載 |
| [バックエンド構成](docs/spec/1.バックエンド構成.md) | モジュラーモノリス，クリーンアーキテクチャの依存方向，横断処理・トランザクション方針を記載 |
| [API仕様書](docs/spec/3.API仕様書.md) | ヘルスチェックを実装済み．小休憩モデルの業務動作，基本APIの契約案，全機能の対応表，未決事項を記載 |
| [ドメインモデル定義](docs/spec/4.ドメインモデル定義.md) | 途中報酬・小休憩，終了時の全未使用報酬破棄・制限解除，グループ・通知のモデルを記載 |
| [インフラ構成](docs/spec/2.インフラ構成.md) | 未記入（空ファイル） |

資料が空の場合は仕様未定として扱います。実装に必要な仕様を決めたら該当資料に記載し、資料の追加・移動や記入状況の変更に合わせてこの索引を更新します。

## 開発用 Skills

| Skill | 用途 |
| --- | --- |
| [docs-navigator](.claude/skills/docs-navigator/SKILL.md) | 仕様・設計の参照先と未決事項を確認 |
| [issue-create](.claude/skills/issue-create/SKILL.md) | 要望を目的・範囲・完了条件付きの Issue に整理 |
| [issue-resolve](.claude/skills/issue-resolve/SKILL.md) | Issue の仕様確認・実装・検証・結果報告 |

Skills の正本は `.claude/skills/` です。`.codex/skills` と Codex の読み込み先 `.agents/skills` は、ともに `../.claude/skills` を参照する相対シンボリックリンクです。更新は正本に行います。リンクが保持される環境でチェックアウトしてください。

仕様を確認し、必要に応じて Issue に作業を整理してから実装・検証を進めます。Issue・PR の本文は [Issue テンプレート](.github/ISSUE_TEMPLATE/feature.md) と [PR テンプレート](.github/PULL_REQUEST_TEMPLATE.md) を利用できます。
