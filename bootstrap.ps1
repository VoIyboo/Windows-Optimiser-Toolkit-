<#  Quinn Optimiser Toolkit - bootstrap.ps1

Usage (one-liner):

  irm https://raw.githubusercontent.com/VoIyboo/Windows-Optimiser-Toolkit-/main/bootstrap.ps1 | iex

This will:
  - Check PowerShell version
  - Download + unpack the repo (if needed)
  - Import core + modules
  - Launch the WPF UI
#>

# Ensure TLS 1.2 for GitHub
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Basic checks -------------------------------------------------
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "Quinn Optimiser Toolkit requires PowerShell 5.1 or later." -ForegroundColor Red
    return
}

# Admin check (UI has nicer handling later, this is just a safety net)
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$IsAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Host "Please run PowerShell as Administrator before launching the toolkit." -ForegroundColor Yellow
    # You can comment this return out if you want non-admin mode later
    return
}

# --- Locate or download repo --------------------------------------
$repo   = "VoIyboo/Windows-Optimiser-Toolkit-"
$branch = "main"

# Try to use local copy first (when user cloned the repo)
$rootFromScript = $null
try {
    $rootFromScript = Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue
} catch { }

if ($rootFromScript -and (Test-Path (Join-Path $rootFromScript "src"))) {
    # Running from a cloned repo
    $Global:QOT_Root = $rootFromScript
} else {
    # Running via one-liner – download zip to temp
    $tempRoot = Join-Path $env:TEMP "QuinnOptimiserToolkit"
    if (-not (Test-Path $tempRoot)) {
        New-Item -Path $tempRoot -ItemType Directory | Out-Null
    }

    $zipPath = Join-Path $tempRoot "toolkit.zip"
    $extractPath = Join-Path $tempRoot "repo"

    if (Test-Path $extractPath) {
        Remove-Item $extractPath -Recurse -Force
    }

    $zipUrl = "https://github.com/$repo/archive/refs/heads/$branch.zip"
    Write-Host "Downloading Quinn Optimiser Toolkit..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing

    Write-Host "Extracting..." -ForegroundColor Cyan
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    # The extracted folder is usually repoName-branch
    $repoFolder = Get-ChildItem -Path $extractPath | Where-Object { $_.PSIsContainer } | Select-Object -First 1
    $Global:QOT_Root = $repoFolder.FullName
}

# --- Import core + modules ----------------------------------------
$srcPath      = Join-Path $Global:QOT_Root "src"
$corePath     = Join-Path $srcPath "Core"
$modulesPath  = Join-Path $srcPath "Modules"
$uiPath       = Join-Path $srcPath "UI"

if (-not (Test-Path $corePath) -or -not (Test-Path $uiPath)) {
    Write-Host "Toolkit files are missing (src/Core or src/UI). Check the GitHub repo structure." -ForegroundColor Red
    return
}

# Core modules
Import-Module (Join-Path $corePath "Logging.psm1") -Force
Import-Module (Join-Path $corePath "Config.psm1")  -Force
Import-Module (Join-Path $corePath "Engine.psm1")  -Force

# Feature modules (auto-import every .psm1 under Modules)
if (Test-Path $modulesPath) {
    Get-ChildItem -Path $modulesPath -Filter *.psm1 | ForEach-Object {
        Import-Module $_.FullName -Force
    }
}

# UI module
. (Join-Path $uiPath "MainWindow.ps1")

# --- Init + launch ------------------------------------------------
Set-QLogRoot (Join-Path $Global:QOT_Root "Logs")
Load-QConfig
Write-QLog "Bootstrap complete. Launching main window."

Show-QMainWindow
