//go:build !darwin && !windows

package main

import (
	"github.com/jphacks/tkb_2622/desktop/internal/app"
	"github.com/wailsapp/wails/v2/pkg/options"
)

func configurePlatform(configuration *options.App, _ *app.Host) {}
