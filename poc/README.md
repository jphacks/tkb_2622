# 今回のアプリで必要な機能のPoCをこのディレクトリで作成

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

## 実機起動の現在状況（2026-10-24）

- iPhoneへのビルド、インストール、`devicectl device process launch` は成功した。
- 起動後にiPhoneで白画面になり、Xcodeは `Launching suspended and the debugger is responsible for resuming` の後、アプリへのデバッガ接続待ちになった。
- 使用環境はmacOS 26.5.2 / Xcode 26.5 / iPhone SE (第3世代)・iOS 27.0.1。Xcode 26.5がこのiOSバージョンの実機デバッグに対応していないことが原因候補だが、白画面の直接原因としては未確定。
- Family Controlsの認可ダイアログは表示されたが、許可状態とShieldの動作は未確認。配布向け `Family Controls (Distribution)` の警告は、今回の起動待ちとは別の項目。

macOS 26.6以降とiOS 27対応のXcodeに更新した後、Xcodeからプロジェクトを開き、iPhoneのロックを解除して実行先に選び、⌘Rで起動する。アプリ画面が表示されたら、認可状態、アプリ選択、Shield設定・解除の順に実機確認を再開する。白画面が続く場合は、XcodeのデバッグコンソールとDevices and Simulatorsの端末状態を記録し、原因を切り分ける。
