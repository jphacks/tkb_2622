# setup.ps1 / up.ps1 で共通の処理．Windows PowerShell 5.1 で動くように書く．
$ErrorActionPreference = 'Stop'

$DesktopDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$FrontendDir = Join-Path $DesktopDir 'frontend'

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-Command([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# 外部コマンドは失敗しても例外にならないため，終了コードを確認する
function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath $($Arguments -join ' ') が終了コード $LASTEXITCODE で失敗しました．"
    }
}

# WSL 上のパス（\\wsl.localhost\...）では npm が動かず，node_modules も Linux 用になる
function Assert-WindowsCheckout {
    if ($DesktopDir.StartsWith('\\')) {
        throw "リポジトリが $DesktopDir にあります．Windows のドライブ（例: C:\dev\tkb_2622）に clone してから実行してください．"
    }
}

# winget でインストールした直後でも新しい PATH を使えるようにする
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Get-GoBinDir {
    $goBin = (& go env GOBIN).Trim()
    if (-not $goBin) {
        $goBin = Join-Path (& go env GOPATH).Trim() 'bin'
    }
    return $goBin
}

function Add-GoBinToSessionPath {
    $goBin = Get-GoBinDir
    if (($env:Path -split ';') -notcontains $goBin) {
        $env:Path = "$env:Path;$goBin"
    }
}

# go.mod に固定した Wails のバージョン（例: v2.17.0）
function Get-WailsVersion {
    $match = Select-String -Path (Join-Path $DesktopDir 'go.mod') -Pattern 'github\.com/wailsapp/wails/v2 (v\S+)'
    if (-not $match) {
        throw 'go.mod から Wails のバージョンを読み取れません．'
    }
    return $match.Matches[0].Groups[1].Value
}
