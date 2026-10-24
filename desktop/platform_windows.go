package main

import (
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/windows"
)

func configurePlatform(configuration *options.App) {
	configuration.Windows = &windows.Options{
		// 画面はライト配色だけなので，OSがダークモードでもタイトルバーを画面に合わせる．
		Theme:    windows.Light,
		Messages: webview2Messages(),
	}
}

// WebView2 Runtimeが無い・壊れているときに表示するダイアログの文言．
func webview2Messages() *windows.Messages {
	return &windows.Messages{
		InstallationRequired: "Focus Link の起動には Microsoft Edge WebView2 Runtime が必要です。OK を押すとダウンロードしてインストールします。画面を表示せずに進むため、しばらくお待ちください。",
		UpdateRequired:       "Focus Link の起動には Microsoft Edge WebView2 Runtime の更新が必要です。OK を押すとダウンロードしてインストールします。画面を表示せずに進むため、しばらくお待ちください。",
		MissingRequirements:  "起動に必要なコンポーネントがありません",
		Webview2NotInstalled: "Microsoft Edge WebView2 Runtime がインストールされていません",
		Error:                "エラー",
		FailedToInstall:      "Microsoft Edge WebView2 Runtime を正しくインストールできませんでした。もう一度お試しください。",
		// 末尾に必要な最小バージョンが付け足される
		DownloadPage:         "Focus Link の起動には Microsoft Edge WebView2 Runtime が必要です。OK を押すとダウンロードページを開きます。必要なバージョン：",
		PressOKToInstall:     "OK を押すとインストールします。",
		ContactAdmin:         "Focus Link の起動には Microsoft Edge WebView2 Runtime が必要です。管理者に問い合わせてください。",
		InvalidFixedWebview2: "指定された WebView2 Runtime のフォルダーが正しくありません。",
		WebView2ProcessCrash: "WebView2 のプロセスが異常終了しました。Focus Link を再起動してください。",
	}
}
