# tkb_2622 — 開発資料と Skills

新規アプリの初期開発用リポジトリ。デスクトップでユーザーの作業・集中度合を検知し、スマホアプリでスマホの使用を制限する構想です。詳細仕様は策定中です。バックエンドの技術スタック案は下記の仕様資料を参照してください。

## ディレクトリ

| ディレクトリ | 用途・現状 |
| --- | --- |
| [backend/](backend/) | バックエンド用。README は未記入 |
| [desktop/](desktop/) | 作業・集中度合を検知するデスクトップアプリ用 |
| [mobile/](mobile/) | スマホの使用を制限するアプリ用 |
| [infra/](infra/) | インフラ構成の管理用 |
| [poc/](poc/) | 必要な機能の PoC 用 |
| [docs/](docs/) | 仕様・設計資料 |

## 仕様資料

| 資料 | 状態 |
| --- | --- |
| [バックエンド構成](docs/spec/1.バックエンド構成.md) | 技術スタック案を記載 |
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
