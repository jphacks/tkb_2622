# iOSアプリ開発

## 位置づけ

このディレクトリを本番向けiOSアプリのSwift / SwiftUI実装場所とする。画面のHTMLモックは [`docs/UI/`](../docs/UI/) にあり、実機での技術検証用アプリは [`poc/ios-reward-time/`](../poc/ios-reward-time/) に分けて置く。

画面の見た目はモックを参考にするが、残高・セッション・利用枠などの業務動作は [`docs/spec/3.API仕様書.md`](../docs/spec/3.API仕様書.md) と [`docs/spec/4.ドメインモデル定義.md`](../docs/spec/4.ドメインモデル定義.md) を正とする。モックと仕様に食い違いがある場合、実装側で解釈して埋めず、モックまたは仕様を更新してから着手する。

## 進め方

一度に全画面を作らず、動作を確認できる小さな縦切りで進める。

1. **モック・仕様の対応を確認する**：対象画面、対応要件、状態ごとの表示、未決事項を [`docs/UI/README.md`](../docs/UI/README.md) で確認する。
2. **アプリの土台を作る**：SwiftUIの起動・画面遷移と、画面が依存する状態・データの境界を用意する。
3. **ホーム画面を仮データで表示する**：セッション状態、残高、制限状態を読み取り専用で表示する。仮データはリポジトリ経由で渡し、後から通信実装に置き換えられるようにする。
4. **API契約が確定した範囲を接続する**：APIクライアントとリポジトリを実装し、通信中・失敗・未同期を画面で区別する。認証方式など未決の契約をアプリ内で決めない。
5. **小休憩の利用フローを接続する**：PAUSED中の利用枠確保、利用状態表示、実利用の報告をAPI契約に沿って扱う。終了・中止時は未使用残高を破棄する。
6. **制限機能を独立して検証・接続する**：制限の要求状態とiPhoneでの適用確認を区別する。FamilyControls / ManagedSettings の実装・権限追加は、必要なPoCと配布条件を確認し、対象作業として合意してから行う。

## 依存の境界

標準のSwift / SwiftUIとFoundationを使い、外部パッケージを追加しない。

```text
SwiftUI画面
  ↓
画面状態・ユースケース
  ↓
HomeRepository（ホーム情報取得の境界）
  ├─ 仮データ実装（画面開発用）
  └─ API実装（契約確定後）

制限操作 → RestrictionController（境界のみ。OS連携はPoC後）
```

画面はHTTP通信やOS制限APIを直接呼ばない。APIのDTOと画面表示用モデルを分け、サーバー残高をiPhoneから直接書き換えない。仮データ実装は実APIの結果を偽装せず、開発用であることが分かる形にする。

## 現在の実装

`ios-reward-time.xcodeproj` にSwiftUIアプリの土台を作成し、`HomeRepository` の仮データ実装を通してiPhone作業中ホームを表示する。作業状態・報酬残高・iPhone制限状態・最終更新時刻は表示専用で、操作による残高変更や制限解除は行わない。画面には仮データであることを明示する。

最初のコード単位はここまでとし、次はAPI仕様で必要な取得契約が確定した範囲から通信実装へ置き換える。残高消費、認証、FamilyControls、通知、グループ、履歴はこの段階に含めない。

## ソース構成

```text
mobile/
├── ios-reward-time.xcodeproj/
└── RewardTime/
    ├── RewardTimeApp.swift
    ├── Domain/MobileHomeSnapshot.swift
    ├── Data/HomeRepository.swift
    └── Features/Home/
        ├── HomeView.swift
        └── HomeViewModel.swift
```

## ビルドと起動

Schemeは `RewardTime`。Xcodeで `mobile/ios-reward-time.xcodeproj` を開き、iOS Simulatorを選んで実行する。CLIでは次のようにSimulator向けビルドを行える。

```sh
xcodebuild \
  -project mobile/ios-reward-time.xcodeproj \
  -scheme RewardTime \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/tkb2622-mobile-deriveddata \
  CODE_SIGNING_ALLOWED=NO \
  build
```

プロジェクトのiOS Deployment Targetは現時点で16.0に仮設定している。対応OSの正式決定時に見直す。Bundle Identifierも開発用の仮値であり、署名・実機配布前にチームの設定へ置き換える。

## 確認方法

- XcodeプロジェクトのSchemeとSimulatorを選び、ビルド・起動して対象画面を確認する。
- 変更に対応するユニットテストまたは手動確認を追加し、空状態・通信失敗・期限切れなど該当する状態を確認する。
- iOS Simulatorで起動し、仮データ表示と状態カードを確認する。Simulatorが使えない場合はXcodeのエラーを記録し、CLIビルドまで確認する。
- 実機制限の確認はシミュレータ画面確認と分け、[`poc/README.md`](../poc/README.md) の実機手順・記録に従う。

## 未決事項

認証サービス、利用時間の計測・同期、制限モード、解除失敗時の返還、対応OS・配布条件は [`docs/spec/3.API仕様書.md`](../docs/spec/3.API仕様書.md) と要件資料の未決事項に従う。これらをmobile側だけで確定しない。
