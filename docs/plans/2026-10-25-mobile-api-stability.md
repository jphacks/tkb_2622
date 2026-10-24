# Mobile APIエラー安定化 作業リスト

## 目的

時間が限られているため、mobileのAPIエラーを優先して再現・修正する。変更ごとにSimulatorで実行可能なテストを追加し、仕様・調査結果・未決事項をこの資料と関連資料へ反映する。

作業ブランチは`fix/mobile-api-stability`。作業単位でローカルコミットし、pushしない。

## 優先順位

### P0 — エラーを再現して直す

1. **API経路の棚卸し**
   - Auth／EnsureUser／GetMe
   - iPhone端末登録・制限ポリシー
   - Homeのセッション・残高・制限状態
   - Groups・公開名・招待・作業開始フィード
   - History・transactions
   - 利用枠・実利用報告
   - 通知先登録・解除
   - 各呼び出しについて、利用画面、request/response DTO、認証、エラー表示、retry、空状態を一覧化する。

2. **再現・テスト基盤**
   - mobileにXCTestのtarget／schemeがあるか確認し、なければ最小のSimulator向けテストtargetを追加する。
   - 候補seamはConnect JSON clientの`URLProtocol`差し替え、およびViewModelが依存するRepository protocol。実装を読んで最小の公開境界を選び、個別テストを始める前に本資料へ記録する。
   - 1つの失敗シナリオごとに、テストを先に追加して失敗を確認し、修正後に通す。
   - test用stubは通信応答を決定的に再現する目的だけに使い、アプリ機能でモックデータへ切り替える経路は作らない。

3. **現在報告されている通知画面の再読込エラー**
   - `.task`、scene復帰、認証変更、APNs token callbackによる重複refresh／重複登録をテストで確認する。
   - 同じtokenの並行登録、API失敗後の再試行、未ログイン・設定不足、許可拒否時の解除を確認する。
   - 競合や重複要求が再現した場合に限り、in-flightの集約や状態遷移を修正する。
   - エラーコードは画面と診断ログで特定でき、token・access token等は表示／記録しない。

4. **認証・Connect transport**
   - access token欠落・期限切れ・401／403、HTTP status、Connect code、通信断、timeout、JSON decode failureを個別に再現する。
   - ProtoJSON enum、`int64`、camelCase field、timestamp等の変換をAPI契約・生成物と照合する。
   - session更新後の端末registration ID、User同期、ログアウト・再ログインを確認する。

5. **機能別APIエラー**
   - Group／Home／History／Restriction／UsageのRepository呼び出しを画面単位で追い、一覧・詳細・作成・retryの成功／失敗／empty stateを確認する。
   - エラー後に古い成功状態やモック値を成功として表示しない。
   - 失敗が見つかったら、再現テスト→最小修正→Simulator buildの順に縦切りで進める。

### P1 — 結合確認とドキュメント

1. 最新migration・local Compose API・iOS Debug appの組み合わせで、認証付きAPIの往復を確認する。
2. APNsはendpoint登録、Outbox作成、配信、失効tokenを区別して確認する。配信試験はSandbox、登録済みrecipient、別メンバーによる新規作業開始を使う。
3. 各修正後に`mobile/README.md`または該当仕様書へ実装状況・確認内容・残課題を記録する。
4. 質問が必要になっても作業を止めず、決定が必要な理由・候補・安全な暫定方針を「未決事項」に書く。既存仕様で判断できる小さな点はその仕様に従う。
5. 縦切りごとにcommitし、作業木・秘密情報を確認してから保存する。pushしない。

### P2 — 後回し

- キャラクターが動くウィジェット。
- 友達の集中状態を表示するDynamic Island／Live Activity。
- 既存PoC `poc/ios-friend-focus-widget/` と仕様を確認し、API安定化後に独立した実装計画を作る。

## 完了条件

- 優先API経路の一覧と、それぞれの成功・失敗表示・retry方針が記録されている。
- 見つかったAPI不具合に再現性のあるSimulator testがあり、修正後に通る。
- iOS Simulator Debug buildが通る。
- 実機／APNsなどSimulatorで証明できない範囲を明記し、未解決エラーをコードと再現手順つきで残す。
- 関連ドキュメントが実装と一致し、コミットがローカルブランチにある。pushはしない。

## 参照資料

- [`mobile/README.md`](../../mobile/README.md) — 画面別の現在のAPI接続
- [`docs/spec/3.API仕様書.md`](../spec/3.API仕様書.md) — Connect契約・エラー分類・再同期
- [`docs/spec/4.ドメインモデル定義.md`](../spec/4.ドメインモデル定義.md) — 状態・不変条件
- [`docs/spec/6.iOSクライアント開発フロー.md`](../spec/6.iOSクライアント開発フロー.md) — iOS接続段階・未決事項
- [`docs/spec/8.desktop-mobile連携の現状と課題.md`](../spec/8.desktop-mobile連携の現状と課題.md) — 環境と端末間同期

## 未決事項

実装中に判断が必要な事項を、質問ではなくここへ追記する。

| 項目 | 必要な判断 | 暫定方針 | 状態 |
| --- | --- | --- | --- |
| XCTestのseam | transport層・Repository/ViewModel層のどこまでをテスト対象とするか | 最小の公開境界をコード調査後に提案し、そこで決定的なSimulator testを書く | 調査前 |
| 既知のmobile APIエラー | 画面・操作・Connect code・再現条件 | 画面別にログと実装から棚卸しし、特定できない場合は再現手順と必要情報を記録 | 調査前 |
| APNs実機受け入れ | sandbox署名、二人以上のrecipient、実機配信 | API安定化後にシミュレータ検証と分けて確認 | 未確認 |
