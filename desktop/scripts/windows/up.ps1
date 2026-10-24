# Windows でデスクトップアプリを開発モード（wails dev）で起動する．
# フロントエンドの変更はホットリロードされる．終了は Ctrl+C．
. (Join-Path $PSScriptRoot 'common.ps1')

Assert-WindowsCheckout

if (-not (Test-Command 'go')) {
    throw 'Go がありません．先に make setup-win を実行してください．'
}
Add-GoBinToSessionPath
if (-not (Test-Command 'wails')) {
    throw 'Wails CLI がありません．先に make setup-win を実行してください．'
}
if (-not (Test-Path (Join-Path $FrontendDir 'node_modules'))) {
    throw 'フロントエンドの依存がありません．先に make setup-win を実行してください．'
}

Push-Location $DesktopDir
try {
    Write-Step 'wails dev で起動します（終了は Ctrl+C）'
    Invoke-Native wails @('dev')
} finally {
    Pop-Location
}
