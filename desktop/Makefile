# Windows 向けの準備・起動．Windows の PowerShell から実行する（WSL・macOS では使えない）．
#   make -C desktop setup-win   依存関係（Go・Node.js・WebView2・Wails CLI・npm パッケージ）を準備
#   make -C desktop up-win      wails dev で起動
POWERSHELL := powershell -NoProfile -ExecutionPolicy Bypass -File

.PHONY: setup-win up-win

ifeq ($(OS),Windows_NT)
setup-win:
	$(POWERSHELL) scripts/windows/setup.ps1

up-win:
	$(POWERSHELL) scripts/windows/up.ps1
else
setup-win up-win:
	@echo "$@ は Windows の PowerShell から実行してください（WSL・macOS では Windows 版を起動できません）．"
	@exit 1
endif
