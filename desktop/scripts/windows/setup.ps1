# Windows でデスクトップアプリを起動するための依存関係を準備する．
# Go・Node.js・WebView2 Runtime がなければ winget でインストールし，
# Wails CLI（go.mod と同じバージョン）とフロントエンドの依存を導入する．
. (Join-Path $PSScriptRoot 'common.ps1')

function Install-WingetPackage([string]$Id) {
    if (-not (Test-Command 'winget')) {
        throw "winget がありません．$Id を手動でインストールしてから再実行してください．"
    }
    Write-Step "$Id をインストールします"
    Invoke-Native winget @('install', '--id', $Id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements')
    Update-SessionPath
}

function Test-WebView2 {
    # Microsoft が案内している WebView2 Runtime の検出方法（pv が 0.0.0.0 以外なら導入済み）
    $clientId = '{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    $keys = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$clientId",
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$clientId",
        "HKCU:\Software\Microsoft\EdgeUpdate\Clients\$clientId"
    )
    foreach ($key in $keys) {
        $item = Get-ItemProperty -Path $key -Name pv -ErrorAction SilentlyContinue
        if ($item -and $item.pv -and $item.pv -ne '0.0.0.0') {
            return $true
        }
    }
    return $false
}

function Test-NodeVersion {
    # frontend/package.json の engines: ^22.12.0 || ^24.0.0 || >=26.0.0
    $version = [version]((& node --version).Trim().TrimStart('v'))
    return (($version.Major -eq 22 -and $version.Minor -ge 12) -or $version.Major -eq 24 -or $version.Major -ge 26)
}

Assert-WindowsCheckout

# ---------- Go ----------
if (-not (Test-Command 'go')) {
    Install-WingetPackage 'GoLang.Go'
}
$goVersion = [version](((& go env GOVERSION).Trim() -replace '^go', '') -replace '[^0-9.].*$', '')
# Go 1.21 以降なら go.mod が要求する版（go 1.26.x）を自動で取得する
if ($goVersion -lt [version]'1.21') {
    throw "Go $goVersion は古すぎます．Go 1.21 以降に更新してから再実行してください．"
}
Write-Step "Go $goVersion を使用します（go.mod の版は必要に応じて自動取得）"

# ---------- Node.js ----------
if (-not (Test-Command 'node')) {
    Install-WingetPackage 'OpenJS.NodeJS.LTS'
}
if (-not (Test-NodeVersion)) {
    throw "Node.js $((& node --version).Trim()) は未対応です．22.12 以上の 22 系，24 系，26 以降のいずれかにしてください．"
}
Write-Step "Node.js $((& node --version).Trim()) を使用します"

# ---------- WebView2 Runtime ----------
if (Test-WebView2) {
    Write-Step 'WebView2 Runtime は導入済みです'
} else {
    Install-WingetPackage 'Microsoft.EdgeWebView2Runtime'
}

# ---------- Wails CLI ----------
$wailsVersion = Get-WailsVersion
Add-GoBinToSessionPath
$installedWails = ''
if (Test-Command 'wails') {
    $installedWails = (& wails version 2>$null | Select-Object -First 1)
}
if ("$installedWails".Trim() -ne $wailsVersion) {
    Write-Step "Wails CLI $wailsVersion をインストールします"
    Invoke-Native go @('install', "github.com/wailsapp/wails/v2/cmd/wails@$wailsVersion")
} else {
    Write-Step "Wails CLI $wailsVersion は導入済みです"
}

# 新しいターミナルでも wails を使えるよう，ユーザー PATH に Go の bin を追加する
$goBin = Get-GoBinDir
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ((("$userPath") -split ';') -notcontains $goBin) {
    [Environment]::SetEnvironmentVariable('Path', ("$userPath;$goBin").Trim(';'), 'User')
    Write-Step "ユーザーの PATH に $goBin を追加しました"
}

# ---------- プロジェクトの依存 ----------
Push-Location $DesktopDir
try {
    Write-Step 'Go モジュールを取得します'
    Invoke-Native go @('mod', 'download')

    Write-Step 'フロントエンドの依存をインストールします'
    Push-Location $FrontendDir
    try {
        Invoke-Native npm @('ci')
    } finally {
        Pop-Location
    }

    Write-Step 'wails doctor で環境を確認します'
    & wails doctor
} finally {
    Pop-Location
}

Write-Host ''
Write-Host '準備が完了しました．make up-win で起動できます．' -ForegroundColor Green
