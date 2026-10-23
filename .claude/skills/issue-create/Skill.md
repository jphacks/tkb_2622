---
name: issue-create
description: 実装したい意図を、AI DLC の「作業ユニット（Unit of Work）」として完了定義(DoD)付きの GitHub Issue に落とし込み、gh で作成する。ふわっとした要望・TODO・バグを、仕様の正本にひも付いた検証可能な Issue に変換する。「〇〇をIssueにして」「これタスク化して」「issue立てて」などのときに使う。テンプレは .github/ISSUE_TEMPLATE。
---

# issue-create — 意図を作業ユニットに変換する

AI DLC では **1 Issue = 1 作業ユニット**。実装に入る前に「意図」と「完了定義」を固定し、あとは DoD を満たすだけにするのが狙い。曖昧な要望を、仕様の正本にひも付いた**検証可能な**Issue にする。

## 進め方

1. **意図を1〜3行で言語化** — なぜやるか / 誰のどの課題か。ここが曖昧なら Ryo に1問だけ確認する。
2. **仕様の正本を引く** — `docs-navigator` で該当 `docs/` §を特定し、Issue に必ずリンクする。仕様が無ければ「未決事項」に上げる（憶測で DoD を書かない）。
3. **スコープを切る** — 対象コンポーネント（api/web/extension/shared/infra）と「やること／やらないこと」を分ける。**大きすぎたら分割**（1ユニットは目安 半日〜1PR で終わる粒度）。
4. **完了定義(DoD)を検証可能な形で書く** — 「動く」ではなく「何をどう確認したら完了か」。受け入れ基準・テスト・ドキュメント整合の3観点（下記）。
5. **テンプレに沿って作成** — `.github/ISSUE_TEMPLATE/feature.md`（機能）/ `bug.md`（バグ）の項目を埋める。
6. **`gh` で作成** — ラベル・関連 Issue を付ける。

```bash
gh issue create --repo Broca-Tech/shadow-ai \
  --title "[feat] 部門別タイムシリーズに前週比を追加" \
  --label enhancement \
  --body-file <(cat <<'EOF'
（テンプレを埋めた本文）
EOF
)
```

## 完了定義(DoD)の3観点（必ず埋める）

- **受け入れ基準**: 契約・挙動を具体的に（例: `GET /v1/dashboard/departments/{id}/timeseries` が docs/13 §2.3 の契約通り、前週比フィールドを含めて返る）
- **テスト**: どのテストが赤→緑になれば完了か（api=pytest / extension=vitest / web=build+lint、テストあれば vitest）
- **ドキュメント整合**: 仕様を変えるなら docs と INDEX.md の更新まで含める

## 良い Issue のチェック

- [ ] 意図（なぜ）が書かれている
- [ ] 仕様の正本 `docs/` §へのリンクがある（または未決事項として明示）
- [ ] DoD が検証可能（第三者が「完了」を判定できる）
- [ ] スコープが1ユニット（大きければ分割し、親子 Issue にする）
- [ ] 適切なラベル（enhancement / bug / documentation …）

## 関連スキル

- 探索: `docs-navigator` / 着手: `issue-resolve`
