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
