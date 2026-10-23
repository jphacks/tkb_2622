---
name: issue-resolve
description: 既存の GitHub Issue を受け取り、その完了定義(DoD)を満たす実装を TDD で行い、PR 作成の直前まで進める。ブランチ作成→仕様確認→赤テスト→実装→緑→リファクタ→ローカル検証まで。「Issue #12 を解決して」「このイシュー実装して」「#12 やって」などのときに使う。TDD は tdd-develop、コード規約は *-best-practice、PR 化は pr-create に委譲する。
---

# issue-resolve — Issue を実装して PR 手前まで持っていく

AI DLC の実装フェーズ。Issue の**完了定義(DoD)を満たすことだけ**をゴールに、TDD で最小手数で実装する。スコープ外に広げない。

## 進め方

1. **Issue を読む** — `gh issue view <n> --repo Broca-Tech/shadow-ai`。意図・スコープ・DoD を把握。DoD が曖昧なら実装前に `issue-create` の観点で補い、Ryo に確認。
2. **仕様の正本を確認** — Issue のリンク先 `docs/` §を `docs-navigator` で開く。契約・計算式・受け入れ基準を実装の根拠にする。**正本と実装（例: スコアは `constants.py`）の両方**を見る。
3. **ブランチを切る** — main から。命名は Conventional Commits のタイプに合わせる:
    ```bash
    git switch main && git pull
    git switch -c feat/<短い説明>   # または fix/… chore/… docs/…
    ```
4. **TDD で実装** — `tdd-develop` に従い Red→Green→Refactor。
    - 対象コンポーネントの規約を必ず参照: api → `fastapi-best-practice`、web → `react-best-practice`、infra/GCP → `gcp-best-practice`。
    - DoD の受け入れ基準を**テストとして先に書く**（api=pytest / extension=vitest / web=vitest or 挙動確認）。
5. **DoD を1つずつ潰す** — チェックボックスを実際に検証しながら消化。仕様を変えたら docs と INDEX.md も更新（DoD に含まれるなら必須）。
6. **ローカル検証（PR の前提）** — 変更コンポーネントに対応するものを実行し、**結果を控える**（PR 本文に貼る）:
    ```bash
    cd api && pytest                 # 統合は TEST_DATABASE_URL 指定時
    cd extension && npm test          # vitest
    cd web && npm run build && npm run lint   # テストあれば npm test
    pre-commit run --all-files        # ruff/eslint/tsc = CI と同じ
    ```
7. **コミット** — 論理単位で。メッセージは `feat(web): …` / `fix(api): …` 形式（日本語可、末尾に共同著者行）。
8. **PR 化は `pr-create` に渡す** — DoD の充足状況と検証ログを引き継ぐ。

## 原則

- **DoD がゴール**。実装途中で気づいた別の改善は別 Issue に切る（`issue-create`）。勝手にスコープを広げない。
- **仕様に反する実装をしない**。docs と食い違ったら実装を止めて確認する。
- **テストが無い変更を緑と呼ばない**。ランタイム挙動のある変更は必ず実際に走らせて確認。
- k-匿名性(k=3)・テナント分離・error エンベロープなど、`deps.py` / `errors.py` の**横断規約を壊さない**。

## 関連スキル

`tdd-develop` / `fastapi-best-practice` / `react-best-practice` / `gcp-best-practice` / 仕上げ: `pr-create`
