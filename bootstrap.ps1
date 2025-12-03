<#
    Quinn Optimiser Toolkit - bootstrap.ps1

    What this script does:
    - Checks PowerShell version
    - Figures out where to keep the toolkit files
    - If running from GitHub one liner, downloads the repo zip to %TEMP%\QuinnOptimiserToolkit
    - Extracts it and finds the src folder
    - Imports Core and Modules
    - Loads the WPF UI (MainWindow.xaml + MainWindow.ps1)
    - Starts the Quinn Optimiser Toolkit window
#>

param(
    [switch]$ForceUpdate
)

$ErrorActionPreference = "Stop"

# ---------------------------
# Basic checks
# ---------------------------
$MinimumPSMajor = 5

function Test-PowerShellVersion {
    if ($PSVersionTable.PSVersion.Major -lt $MinimumPSMajor) {
        Write-Host "Quinn Optimiser Toolkit requires PowerShell $MinimumPSMajor or higher." -ForegroundColor Red
        Write-Host "Current version: $($PSVersionTable.PSVersion.ToString())"
        throw "PowerShell version too low"
    }
}

# Returns the folder where the toolkit should live
function Get-ToolkitRoot {
    # If src exists beside this file, assume we are running from the repo clone
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $srcPath   = Join-Path $scriptDir "src"

    if (Test-Path $srcPath) {
        return $scriptDir
    }

    # Otherwise use a temp folder for downloaded version
    $tempRoot = Join-Path $env:TEMP "QuinnOptimiserToolkit"
    if (-not (Test-Path $tempRoot)) {
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    }
    return $tempRoot
}

# GitHub details for your repo
function Get-GitHubDownloadInfo {
    # Change these two to your real GitHub account and repo name
    $owner  = "YourGitHubUserOrOrg"
    $repo   = "QuinnOptimiserToolkit"
    $branch = "main"

    $zipUrl  = "https://github.com/$owner/$repo/archive/refs/heads/$branch.zip"
    $zipName = "$repo-$branch.zip"

    [pscustomobject]@{
        Owner   = $owner
        Repo    = $repo
        Branch  = $branch
        ZipUrl  = $zipUrl
        ZipName = $zipName
    }
}

# Finds src\ for either local repo or downloaded zip
function Get-ToolkitSrcPath {
    param(
        [string]$Root
    )

    # Local src
    $localSrc = Join-Path $Root "src"
    if (Test-Path $localSrc) {
        return $localSrc
    }

    # Downloaded zip structure: Root\Repo-Branch\src
    $info           = Get-GitHubDownloadInfo
    $unzippedFolder = Join-Path $Root ("{0}-{1}" -f $info.Repo, $info.Branch)
    $downloadedSrc  = Join-Path $unzippedFolder "src"

    if (Test-Path $downloadedSrc) {
        return $downloadedSrc
    }

    return $null
}

function Get-ToolkitInstalled {
    param(
        [string]$Root
    )

    $srcPath = Get-ToolkitSrcPath -Root $Root
    return [bool]$srcPath
}

# Downloads and extracts the latest code from GitHub
function Install-ToolkitFromGitHub {
    param(
        [string]$Root
    )

    $info = Get-GitHubDownloadInfo

    Write-Host "Downloading Quinn Optimiser Toolkit from GitHub..." -ForegroundColor Cyan
    $zipPath = Join-Path $Root $info.ZipName

    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    }

    Invoke-WebRequest -Uri $info.ZipUrl -OutFile $zipPath

    Write-Host "Extracting archive..." -ForegroundColor Cyan

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $Root)

    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    $srcPath = Get-ToolkitSrcPath -Root $Root
    if (-not $srcPath) {
        throw "Could not locate src folder after extraction."
    }

    Write-Host "Toolkit extracted to $Root" -ForegroundColor Green
    return $srcPath
}

# Imports all Core and Module .psm1 files, plus the UI wiring
function Import-ToolkitModules {
    param(
        [string]$SrcPath
    )

    $corePath    = Join-Path $SrcPath "Core"
    $modulesPath = Join-Path $SrcPath "Modules"
    $uiPath      = Join-Path $SrcPath "UI"

    if (-not (Test-Path $corePath)) {
        throw "Core folder not found at $corePath"
    }
    if (-not (Test-Path $uiPath)) {
        throw "UI folder not found at $uiPath"
    }

    # Import Core modules first
    Get-ChildItem $corePath -Filter *.psm1 | ForEach-Object {
        Import-Module $_.FullName -Force
    }

    # Import feature modules (DiskCleanup, Apps, Tweaks, etc)
    if (Test-Path $modulesPath) {
        Get-ChildItem $modulesPath -Filter *.psm1 | ForEach-Object {
            Import-Module $_.FullName -Force
        }
    }

    # Dot source the main UI script, which defines Show-QMainWindow
    $mainUi = Join-Path $uiPath "MainWindow.ps1"
    if (-not (Test-Path $mainUi)) {
        throw "MainWindow.ps1 not found in $uiPath"
    }

    . $mainUi
}

function Start-QuinnToolkit {
    Test-PowerShellVersion

    $root = Get-ToolkitRoot

    # If we are not installed in this root, or user forced update, pull latest from GitHub
    if ($ForceUpdate -or -not (Get-ToolkitInstalled -Root $root)) {
        $null = Install-ToolkitFromGitHub -Root $root
    }

    $srcPath = Get-ToolkitSrcPath -Root $root
    if (-not $srcPath) {
        throw "Toolkit src folder not found at $root."
    }

    Import-ToolkitModules -SrcPath $srcPath

    # Optional: if Logging module exists, set the log root to the same place
    if (Get-Command Set-QLogRoot -ErrorAction SilentlyContinue) {
        Set-QLogRoot -Root $root
    }

    # Optional: load config if Config module exists
    if (Get-Command Load-QConfig -ErrorAction SilentlyContinue) {
        Load-QConfig
    }

    # UI module must provide Show-QMainWindow
    if (-not (Get-Command Show-QMainWindow -ErrorAction SilentlyContinue)) {
        throw "Show-QMainWindow not found. Check UI\MainWindow.ps1 exports it."
    }

    Show-QMainWindow
}

try {
    Start-QuinnToolkit
}
catch {
    Write-Host "Quinn Optimiser Toolkit failed to start." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    if ($_.ScriptStackTrace) {
        Write-Host ""
        Write-Host "Stack:" -ForegroundColor DarkGray
        Write-Host $_.ScriptStackTrace
    }
    exit 1
}
