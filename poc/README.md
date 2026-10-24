# 機能検証PoC

| PoC | 目的 |
|---|---|
| [macOS操作ログ](macos-native/README.md) | ActivityWatch・ブラウザ拡張なしで、前面アプリ・無操作時間・Chrome／Safariの選択中タブのドメインを取得する |
| [iOS報酬時間管理](ios-reward-time/) | iPhoneで報酬時間の管理とScreen Timeによる制限を検証する |
| [報酬状態同期API](reward-sync-api/server.py) | Mac → API → iPhoneアプリの報酬状態の通信を検証する |

macOS操作ログの実行方法・検証結果・未検証事項は専用のREADMEを参照してください。macOS操作ログの実測データと開発用ツールはGit管理対象外です。iOS報酬時間管理と報酬状態同期の手順・検証結果は以下に記載します。

## iOS報酬時間管理PoC

Swift / SwiftUIで作成したiOS PoCは [`ios-reward-time/`](ios-reward-time/) に置く。本番向けアプリの実装場所とは分け、PoC固有の画面・仮データ・検証コードをここで管理する。

## VS CodeからiOS Simulatorで起動する

VS Codeのターミナルでリポジトリのルートを開き、Xcodeのコマンドラインツールを使ってビルド・インストール・起動する。Xcode本体とiOS Simulator runtimeが必要。

### 1. Xcodeの選択を確認

```sh
xcode-select -p
xcodebuild -version
```

`xcode-select -p` が `/Library/Developer/CommandLineTools` を指している場合は、インストール済みXcodeの場所を指定する。例：

```sh
sudo xcode-select --switch "/Users/chiho/Downloads/Xcode.app/Contents/Developer"
```

Xcodeの場所を変えた場合は、パスを実際の場所に合わせる。

### 2. SimulatorとUDIDを確認

```sh
xcrun simctl list devices available
```

iPhoneのSimulatorが表示されない場合は、Xcodeの **Settings → Components** からiOS Simulator runtimeをインストールする。表示されたiPhoneのUDIDを設定する。UDIDの前後に山括弧（`<` `>`）は付けない。

```sh
SIMULATOR_UDID="E6D2EB24-62DE-4993-B795-92B4891E6748"
```

### 3. ビルド

```sh
xcodebuild \
  -project poc/ios-reward-time/tkb_2622_app.xcodeproj \
  -scheme tkb_2622_app \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  -derivedDataPath /private/tmp/tkb2622-deriveddata \
  build CODE_SIGNING_ALLOWED=NO
```

最後に `BUILD SUCCEEDED` と表示されることを確認する。ビルドだけではSimulator上のアプリは更新されないため、次のインストールと起動も行う。

### 4. Simulatorを起動

Simulatorがまだ起動していない場合：

```sh
xcrun simctl boot "$SIMULATOR_UDID"
open -a Simulator
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
```

すでに起動しているSimulatorでは `boot` を省略する。

### 5. アプリをインストールして起動

```sh
xcrun simctl install "$SIMULATOR_UDID" \
  /private/tmp/tkb2622-deriveddata/Build/Products/Debug-iphonesimulator/tkb_2622_app.app

xcrun simctl launch "$SIMULATOR_UDID" com.example.tkb-2622-app
```

## VS Codeから接続したiPhoneでビルド・起動する

Family Controlsの認可やShield動作はiPhone実機で確認する。iPhoneをMacへ接続し、ロックを解除して信頼済みにする。Xcodeの **Signing & Capabilities** で開発用のTeamが設定されていることを確認する。Simulator用コマンドと異なり、実機用ビルドでは署名を無効にしない。

### 1. 接続状態と実機UDIDを確認

```sh
xcrun devicectl list devices
```

一覧で接続したiPhoneのUDIDを確認し、次の変数に設定する。デバイス名を指定してもよい。

```sh
DEVICE_UDID="iPhoneのUDID"
APP_BUNDLE_ID="com.example.tkb-2622-app"
```

UDIDは実際の一覧に表示された値へ置き換える。Bundle IdentifierをXcodeで変更した場合は、`APP_BUNDLE_ID`も同じ値にする。

### 2. 署名付きで実機用ビルド

```sh
xcodebuild \
  -project poc/ios-reward-time/tkb_2622_app.xcodeproj \
  -scheme tkb_2622_app \
  -destination "platform=iOS,id=${DEVICE_UDID}" \
  -configuration Debug \
  -derivedDataPath /private/tmp/tkb2622-device-deriveddata \
  build
```

`BUILD SUCCEEDED` と表示されることを確認する。署名やFamily Controls entitlementで失敗した場合は、Xcodeで **Signing & Capabilities** のTeamとエラーを確認する。

### 3. iPhoneへインストールして起動

```sh
xcrun devicectl device install app \
  --device "$DEVICE_UDID" \
  /private/tmp/tkb2622-device-deriveddata/Build/Products/Debug-iphoneos/tkb_2622_app.app

xcrun devicectl device process launch \
  --device "$DEVICE_UDID" \
  "$APP_BUNDLE_ID"
```

初回はXcodeがiPhoneの開発サポート情報を準備するため、Devices and Simulatorsに準備中と表示されることがある。iPhoneを接続・ロック解除したまま完了を待ってからビルドする。Family Controls (Development) の表示に配布向けentitlement申請の警告が併記される場合、それは配布時の要件であり、開発用の実機検証とは区別する。

## 実機起動時の経過（2026-10-24）

- iPhoneへのビルド、インストール、`devicectl device process launch` は成功した。
- 初回起動時はiPhoneが白画面になり、Xcodeは `Launching suspended and the debugger is responsible for resuming` の後、アプリへのデバッガ接続待ちになった。
- 使用環境はmacOS 26.5.2 / Xcode 26.5 / iPhone SE (第3世代)・iOS 27.0.1。Xcode 26.5とiOS 27.0.1の組み合わせが原因候補だったが、白画面の直接原因は確定していない。
- Family Controlsの認可ダイアログは表示されたが、許可状態とShieldの動作は未確認。配布向け `Family Controls (Distribution)` の警告は、今回の起動待ちとは別の項目。

その後、iPhoneアプリの画面表示と、アプリからAPIの仮残高42分を取得する動作を確認した。初回の白画面は解消しているが、発生原因とXcodeデバッガ接続の関係は未確定。

## MacからiPhoneへ報酬状態を送るPoC

`poc/reward-sync-api/server.py` は、MacとiPhoneが同じネットワーク上で仮の報酬状態を送受信するための一時API。Python標準ライブラリだけを使い、データはメモリ内に1件だけ保持する。Go / Connect RPCの製品API、認証、DB、報酬ルールを決めるものではない。

### 1. MacでAPIを起動

リポジトリのルートで実行する。

```sh
python3 poc/reward-sync-api/server.py
```

MacのIPアドレスをシステム設定のネットワーク詳細で確認する。同じWi-FiにiPhoneを接続する。APIはPoC用のHTTP・認証なしで起動するため、家庭内などの信頼できるネットワークでのみ使用し、インターネットに公開しない。

### 2. Macから仮の報酬状態を送信

別のターミナルでMacのWi-Fi側IPアドレスを設定してから実行する。

```sh
MAC_IP="$(ipconfig getifaddr en0)"
echo "$MAC_IP"
UNLOCK_ENDS_AT="$(date -u -v+10M '+%Y-%m-%dT%H:%M:%SZ')"

curl --fail-with-body -X POST "http://${MAC_IP}:8787/v1/reward-snapshot" \
  -H 'Content-Type: application/json' \
  -d "{\"balanceMinutes\":42,\"unlockEndsAt\":\"${UNLOCK_ENDS_AT}\"}"
```

42分は通信確認用の仮データで、正式な報酬ルールではない。レスポンスに同じ残高と終了予定が返ればMacからAPIへの送信は成功。

### 3. iPhoneでAPIから取得

PoCアプリの「Mac/API通信（PoC）」に `http://<MacのIPアドレス>:8787` を入力し、「APIから報酬状態を取得」を押す。`/v1/reward-snapshot` は入力しない。初回のローカルネットワーク確認では許可する。APIの仮残高と解除終了予定が表示されれば、APIからiPhoneへの取得は成功。アプリ内のローカル仮残高は変更しない。

APIは再起動すると保持データが消える。接続できない場合は、MacとiPhoneが同じネットワーク上にあること、MacのIPアドレス、APIプロセスの起動状態、Macのファイアウォール設定を確認する。

### 実機で確認できた結果

- MacからのPOSTは `201 Created` を返した。
- MacのネットワークIP経由のGETは `200 OK` を返した。
- iPhoneアプリからAPIの仮データを取得し、42分の表示を確認した。
- これでMac → API → iPhoneアプリの通信経路を確認できた。Family Controls認可・Shield動作・期限後の再制限は別の未確認項目。

## 次のPoC：本人認可と1アプリのShield

通信確認後は、iPhone実機でScreen Timeの認可と手動制限を検証する。

1. アプリの「Family Controls」状態を確認し、「本人利用の認可を要求」を押す。認可を許可し、表示が「許可済み」になるか確認する。
2. 「制限するアプリを選択」でアプリを1つ選ぶ。
3. 「選択したアプリを制限」を押し、対象アプリを開いてShieldが表示されるか確認する。
4. PoCに戻り「このPoCの制限を解除」を押し、Shieldが消えるか確認する。
5. 認可状態、対象アプリ、制限・解除結果、表示されたエラーを記録する。

以前の試行では認可ダイアログで拒否を選んでおり、許可状態は未確認。アプリに「拒否」と表示された場合はその状態を記録し、許可済みと扱わない。
