package main

import (
	"embed"
	"log"

	"github.com/jphacks/tkb_2622/desktop/internal/app"
	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
)

//go:embed all:frontend/dist
var assets embed.FS

func main() {
	application := app.New()
	configuration := &options.App{
		Title: "Focus Link", Width: 440, Height: 260, MinWidth: 360, MinHeight: 260,
		AssetServer:      &assetserver.Options{Assets: assets},
		BackgroundColour: &options.RGBA{R: 248, G: 247, B: 252, A: 255},
		OnStartup:        application.Startup, OnDomReady: application.DomReady, OnShutdown: application.Shutdown,
		Bind: []interface{}{application.API},
	}
	configurePlatform(configuration)
	if err := wails.Run(configuration); err != nil {
		log.Fatal(err)
	}
}
