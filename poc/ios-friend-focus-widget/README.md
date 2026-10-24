# 友だち集中ウィジェットPoC

## 確かめること

友だちが集中中か休憩中かに応じて、iPhoneのホーム画面ウィジェットとDynamic Islandでキャラクターの表示を切り替えられるかを確かめる。ホーム画面ウィジェットはWidgetKitとApp Groupで状態を共有し、Dynamic IslandはWidget Extension内のLive ActivityとホストアプリのActivityKitで状態を表示する。

この段階では、ホストアプリ上のボタンで友だちの状態を模擬する。同じiPhone上で状態を保存してホーム画面ウィジェットへ更新を依頼し、Live Activityを開始・更新・終了するところまでが対象。別のiPhoneやMacから状態を送る処理、API、APNs、ログイン、FamilyControlsは含めない。

## プロジェクト

- Xcodeプロジェクト: `FriendFocusWidgetPoC.xcodeproj`
- Scheme: `FriendFocusWidgetPoC`
- Deployment Target: iOS 17.0
- Host app Bundle ID: `com.example.tkb2622.friendfocuspoc`
- Widget Bundle ID: `com.example.tkb2622.friendfocuspoc.widget`
- App Group: `group.com.example.tkb2622.friendfocuspoc`

Bundle IDとApp Group IDはPoC用の仮値。実機へ署名して入れるには、自分のApple Developer Teamで利用可能なApp IDとApp Groupを登録し、XcodeのSigning & Capabilitiesで両ターゲットに同じApp Groupを設定する。Team IDや個人の署名情報はリポジトリへ記録しない。

## 起動と確認

1. Xcodeで `FriendFocusWidgetPoC.xcodeproj` を開く。
2. `FriendFocusWidgetPoC` と `FriendFocusWidgetExtension` のSigning & Capabilitiesで自分のTeamを選び、同じApp Groupを有効にする。仮のApp Group IDを自分のTeamで使えない場合は、両方のentitlementsと `SharedFocusSnapshot.swift` にあるIDを同じ値に変更する。
3. 実行先にiPhoneまたはiOS Simulatorを選んで、`FriendFocusWidgetPoC` schemeを実行する。
4. ホストアプリで「友だちが集中を開始」を押す。ホーム画面に戻り、長押し → 追加（`+`）→「友だちの集中」→ 小サイズのウィジェットを追加する。
5. ウィジェットに「集中中」と作業中の猫が表示されることを確認する。ホストアプリで「友だちが集中を終了」を押し、休憩表示へ変わるか確認する。
6. ホストアプリを終了してホーム画面へ戻る。状態が保持されていることを確認する。
7. ホストアプリで再度「友だちが集中を開始」を押す。Dynamic Island対応iPhoneの場合、ホーム画面へ戻してIslandに猫と「集中」が表示されるか確認する。Islandを長押しして拡大表示も確認する。
8. 「友だちが集中を終了」を押してLive Activityの表示が休憩中へ変わることを確認する。「Live Activityを終了」で表示が消えることを確認する。

Xcode 27は従来の`Simulator.app`ではなくDevice Hubでシミュレータ画面を表示する。Xcodeのメニューから **Xcode → Open Developer Tool → Device Hub** を開き、起動中のiPhoneシミュレータで **View Screen** を選ぶ。

ウィジェットを追加した後に初期表示が古い場合は、ホストアプリを開いて状態ボタンをもう一度押す。WidgetKitの更新依頼は即時反映の保証ではない。反映までの秒数を測り、すぐ／遅れて反映／反映しないを記録する。Live ActivityはアプリからActivityKitで開始・更新・終了する。Dynamic Island非対応端末ではロック画面などに表示される。iOS Simulatorと実機は別々に確認する。

## 合格条件と記録

- App Group共有領域がホストアプリとWidget Extensionの両方から利用できる。
- アプリの状態切替後、ウィジェットの文言とキャラクターが集中中／休憩中に切り替わる。
- ホストアプリを終了した後も、最後に保存した状態が表示される。
- Dynamic Island対応機種でLive Activityを開始し、集中／休憩状態の表示と終了を確認する。
- それぞれの状態変更から反映までの時間、OSバージョン、実機／Simulator、署名設定、失敗ログを記録する。

状態変更アニメーションは切替時の短い視覚効果であり、キャラクターがウィジェット上で常時動き続けることを意味しない。WidgetKitは更新をスケジュール管理するため、更新依頼後の表示時刻はシステムに委ねられる。

## 次段階：別端末の状態を届ける検証

ローカル切替が確認できた後、Macまたは友だちのiPhoneからイベントを送り、ウィジェット／Live Activity表示までの遅延を計測する。候補はAPIで状態を取得する方式とWidgetKit／ActivityKit Pushを使う方式。後者はPush tokenを受け取り配信するサーバーが必要になる。採用方式、更新頻度、オフライン時の扱いは検証結果とバックエンド仕様を見て決める。

## コマンドラインでビルド

```sh
xcodebuild \
  -project poc/ios-friend-focus-widget/FriendFocusWidgetPoC.xcodeproj \
  -scheme FriendFocusWidgetPoC \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/friend-focus-widget-deriveddata \
  CODE_SIGNING_ALLOWED=NO \
  build
```

このコマンドはSimulator向けビルドを確認するもの。ウィジェットのホーム画面追加・見た目・更新タイミングを確認するにはSimulatorまたはiPhoneで起動する。
