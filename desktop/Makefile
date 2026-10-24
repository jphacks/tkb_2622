# Windows 版の準備・起動．Windows の PowerShell と WSL のどちらからでも実行できる．
#   make -C desktop setup-win   依存関係（Go・Node.js・WebView2・Wails CLI・npm パッケージ）を準備
#   make -C desktop up-win      wails dev で起動（終了は Ctrl+C）
# WSL から実行した場合は desktop/ を Windows 側（%LOCALAPPDATA%\tkb_2622\desktop）へ同期して動かす．
POWERSHELL := powershell -NoProfile -ExecutionPolicy Bypass -File
IS_WSL := $(if $(wildcard /proc/sys/fs/binfmt_misc/WSLInterop*),yes,)

.PHONY: setup-win up-win

ifeq ($(OS),Windows_NT)
setup-win:
	$(POWERSHELL) scripts/windows/setup.ps1

up-win:
	$(POWERSHELL) scripts/windows/up.ps1
else ifeq ($(IS_WSL),yes)
setup-win:
	scripts/windows/wsl.sh setup

up-win:
	scripts/windows/wsl.sh up
else
setup-win up-win:
	@echo "$@ は Windows の PowerShell か WSL から実行してください．"
	@exit 1
endif
