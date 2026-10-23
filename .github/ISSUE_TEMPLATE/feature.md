---
name: 機能・作業ユニット（AI DLC）
about: 実装する作業ユニット（Unit of Work）を1つ登録する
title: "[feat] "
labels: enhancement
---

<!-- AI DLC: 1 Issue = 1 作業ユニット。意図(Intent)と完了定義(DoD)を先に固定し、実装はそれを満たす最小手数で行う。 -->

## 意図 / Intent

<!-- なぜこれをやるのか。誰のどの課題を解くか。1〜3行。 -->

## 仕様の正本 / Spec references

<!-- docs/ の該当箇所を必ず1つ以上リンクする。仕様が無ければ先に docs を書くか、下の「未決事項」に上げる。 -->

- docs/xx_〇〇.md §x.x

## スコープ

- 対象コンポーネント: <!-- api / web / extension / shared / infra のいずれか複数 -->
- やること:
    - [ ]
- やらないこと（今回の範囲外）:
  -

## 完了定義 / Definition of Done

<!-- 検証可能な条件だけを書く。「動く」ではなく「何をどう確認したら完了か」。 -->

- [ ] 受け入れ基準:（例: `GET /v1/dashboard/summary` が docs/13 §2.3 の契約通りに返る）
- [ ] テスト:（例: pytest に赤→緑のケースを追加。web は vitest / build+lint 緑）
- [ ] ドキュメント整合:（仕様を変えたら docs と INDEX.md を更新）
