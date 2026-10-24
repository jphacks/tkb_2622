#!/usr/bin/env bash
# WSL から Windows 版を準備・起動する．
# WSL 上のパス（\\wsl.localhost\...）では Windows の npm が動かず，node_modules も OS ごとに別物になるため，
# desktop/ を Windows 側のフォルダへ同期し，そこで setup.ps1 / up.ps1 を実行する．
#   使い方: scripts/windows/wsl.sh setup|up
# 同期先は WIN_DESKTOP_DIR（WSL のパス）で変更できる．既定は %LOCALAPPDATA%\tkb_2622\desktop．
set -euo pipefail

DESKTOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# go.mod の replace（focuspocket/macos-native => ../poc/macos-native）が参照するため，desktop/ と同じ相対位置へ同期する
POC_DIR="$DESKTOP_DIR/../poc/macos-native"
POWERSHELL="$(command -v powershell.exe || echo /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe)"

if [[ ! -x "$POWERSHELL" ]]; then
	echo "powershell.exe が見つかりません．WSL の Windows 相互運用が有効か確認してください．" >&2
	exit 1
fi

if [[ -z "${WIN_DESKTOP_DIR:-}" ]]; then
	local_app_data="$("$POWERSHELL" -NoProfile -Command '[Environment]::GetFolderPath("LocalApplicationData")' | tr -d '\r')"
	WIN_DESKTOP_DIR="$(wslpath -u "$local_app_data")/tkb_2622/desktop"
fi

# Windows 側で生成・インストールされるものは同期しない（--delete でも消さない）．
# P（protect）は削除だけを止める．wails がビルド中に作る *.syso や初回に作る build/windows/ を
# 同期の --delete で消すとコンパイルが失敗するため保護し，リポジトリにある場合は通常どおり同期する．
sync_to_windows() {
	rsync -rlt --delete \
		--exclude '/frontend/node_modules/' \
		--exclude '/frontend/dist/' \
		--exclude '/frontend/wailsjs/' \
		--exclude '/frontend/package.json.md5' \
		--exclude '/build/bin/' \
		--filter 'P /*.syso' \
		--filter 'P /build/windows/' \
		"$DESKTOP_DIR/" "$WIN_DESKTOP_DIR/"
	rsync -rlt --delete \
		--exclude '/.archive/' \
		--exclude '/.tools/' \
		--exclude '/data/' \
		--exclude '/bin/' \
		"$POC_DIR/" "$WIN_DESKTOP_DIR/../poc/macos-native/"
}

run_powershell() {
	"$POWERSHELL" -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$WIN_DESKTOP_DIR/scripts/windows/$1")"
}

mkdir -p "$WIN_DESKTOP_DIR" "$WIN_DESKTOP_DIR/../poc/macos-native"
echo "==> $DESKTOP_DIR を $(wslpath -w "$WIN_DESKTOP_DIR") へ同期します"
sync_to_windows

case "${1:-}" in
setup)
	run_powershell setup.ps1
	;;
up)
	# WSL での編集を Windows 側へ同期し続け，wails dev のホットリロードに反映させる
	(
		while sleep 1; do
			sync_to_windows || echo "同期に失敗しました．次の周期で再試行します．" >&2
		done
	) &
	sync_pid=$!
	trap 'kill "$sync_pid" 2>/dev/null || true' EXIT
	run_powershell up.ps1
	;;
*)
	echo "使い方: $0 setup|up" >&2
	exit 2
	;;
esac
