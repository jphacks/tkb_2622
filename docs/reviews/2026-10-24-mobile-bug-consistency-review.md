# モバイルアプリ 不具合・仕様整合性レビュー

- 日付: 2026-10-24
- 対象ブランチ: `feat/dev-db-seed`
- 比較基点: `origin/main` (`951a9083fea89fc54b6553d2eaa6f52f438bf958`)
- 対象範囲: 比較基点以降のモバイル実装と、関連する制限・API仕様
- 方針: 読み取り専用の確認。コード修正・テスト実行はしていない。

## 確認結果

### Standards（規約・保守性）

リポジトリ内にコーディング規約を定めた `CONTRIBUTING.md` / `CODING_STANDARDS.md` は見つからず、提示された共通指示に反する明確な箇所は確認できなかった。

保守性上の軽微な懸念として、`ProtoJSONInt64` と `validatedURL` 相当の処理が複数の Repository に重複している。今後仕様を変える際に修正漏れが起きる可能性があるが、今回の範囲では機能不具合とは判定しない。

### Spec（不具合・仕様整合性）

#### 要修正候補

1. **制限状態の再送が冪等エラーになる可能性（優先度: 高）**

   [UsageGrantRepository.swift](../../mobile/RewardTime/Data/UsageGrantRepository.swift) は状態報告のたびに `appliedAt` を現在時刻で作る。一方、[MobileScreenTimeController.swift](../../mobile/RewardTime/Data/MobileScreenTimeController.swift) は応答が失われた場合に同じ operation ID を再利用する。backend は同一 operation ID に対してリクエスト本文のハッシュを照合するため、最初の要求が記録された後に再送すると、`appliedAt` の差で同じ操作として受理されない可能性がある。該当キーが残り、以後の再試行も失敗し続けるおそれがある。

2. **ホームの制限アプリ数が0になる可能性（優先度: 中）**

   選択アプリは App Group の `ScreenTimeSharedStorage.defaults` に保存されるが、[APIHomeRepository.swift](../../mobile/RewardTime/Data/APIHomeRepository.swift) は `UserDefaults.standard` から同じキーを読む。新規インストール後に選択したアプリ数がホームへ反映されず、0件と表示される可能性がある。

3. **履歴の残高表示がコード文字列のまま（優先度: 中）**

   [HistoryView.swift](../../mobile/RewardTime/Features/History/HistoryView.swift) の取引後残高表示は Swift の文字列補間になっていないため、実残高ではなく `formattedDuration(item.balanceAfterSeconds)` という文字列が表示される。

4. **履歴の追加読み込み中に種類を切り替えると、別種類の一覧へ追加される可能性（優先度: 中）**

   [HistoryView.swift](../../mobile/RewardTime/Features/History/HistoryView.swift) の `loadMore()` は開始時のページトークンを取得する一方、通信完了後に現在の `section` を見て追加先を決める。読み込み中も Picker は操作可能なので、通信中に切り替えるとページと追加先が食い違う可能性がある。

#### 仕様確認・受け入れ判断が必要

- **「標準以外を制限」の対象範囲**: 実装はカテゴリ全体へ Shield を設定している。一方、[機能・非機能要件](../strategy/2.機能-非機能要件.md) は iPhone 標準アプリを常時許可し Safari を例外とする。標準アプリの具体的な対象範囲は [API仕様書](../spec/3.API仕様書.md) でも未決事項のため、仕様どおりかは確定できない。
- **標準以外モードでの利用枠予約**: 予約処理は「選んだアプリを制限」モードに限定している。要件には両モードの記載があるため、標準以外モードでも予約可能にするのか、現状の制限を仕様として認めるのか決定が必要。
- **再読み込み失敗時の履歴表示**: 初回読み込み後の再読み込みに失敗すると、以前の履歴を残したままエラーを表示する。古い内容と分かる表示がなく、仕様書でも通信断時の扱いが未確定。

## 実機で未確認の項目

このレビューでは実機・Simulator操作を行っていない。FamilyControls の認可、選択したアプリへの Shield 表示、利用時間の計測と期限切れ解除、ログイン済み端末からのグループAPI同期は未確認。静的なコード確認だけでは正常動作を保証できない。

## レビュー範囲と制約

- `origin/main...HEAD` の差分を基に、モバイル実装と関連仕様を確認した。
- `docs/agents/issue-tracker.md` は存在しなかったため、既存の仕様書と要件書を照合に使用した。
- 作業開始時点で存在した未コミットの `backend/Makefile`、`backend/README.md`、`backend/dev/postgres/seed.sql` および個人用 Xcode 状態ファイルは変更していない。
- テスト・ビルド・実機確認は実行していない。

## 後続対応（2026-10-24）

- 上記の要修正候補4件は順に修正し、個別コミットした。
- 利用枠予約は「選んだアプリを制限」モードに限定する判断を確認した。既存の予約制御を維持する。
- 「標準以外を制限」はSafariを制限対象とし、他の標準アプリを常時許可する判断を確認した。常時許可アプリの選択を両モードで共有し、Shield対象とDeviceActivityの利用時間計測対象の両方から除外する。

### 2026-10-25 仕様更新

製品側の判断を更新し、利用者が常に許可するアプリを選ぶUIとその例外処理を削除する。「標準アプリ以外を制限」はSafariのみを制限対象にする。FamilyActivityPickerのopaque tokenからSafari名を検証できないため、Safari専用の選択導線で1アプリだけ選ばせる。上記の初回確認内容はこの決定で置き換える。
- Family Controlsの選択値はアプリ側から名前を識別できないopaque tokenである。そのため、Safariを選択していないことをアプリが自動検証することはできず、設定画面とPicker内の案内で明示する。利用者がSafariを例外に選ぶとSafariも制限対象外になる。
- 後続実装はiOS Simulator向けXcodeビルドに成功した。実機のShield動作は未確認。
