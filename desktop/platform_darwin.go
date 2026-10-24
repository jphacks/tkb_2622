package main

import (
	"github.com/wailsapp/wails/v2/pkg/menu"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/mac"
)

func configurePlatform(configuration *options.App) {
	configuration.Mac = &mac.Options{TitleBar: mac.TitleBarDefault()}
	applicationMenu := menu.NewMenu()
	applicationMenu.Append(menu.AppMenu())
	applicationMenu.Append(menu.EditMenu())
	configuration.Menu = applicationMenu
}
