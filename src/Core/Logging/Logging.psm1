# Logging.psm1
# Simple logging utilities for Quinn Optimiser Toolkit

# Module-scoped variables
$script:QLogRoot = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
$script:QLogFile = $null

function Ensure-QLogRoot {
    try {
        if (-not $script:QLogRoot) {
            $script:QLogRoot = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        }

        if (-not (Test-Path -LiteralPath $script:QLogRoot)) {
            New-Item -Path $script:QLogRoot -ItemType Directory -Force | Out-Null
        }
    } catch { }
}

function Set-QLogRoot {
    param(
        [string]$Root
    )

    if (-not $Root) {
        throw "Set-QLogRoot: Root path cannot be empty."
    }

    if (-not (Test-Path -LiteralPath $Root)) {
        New-Item -Path $Root -ItemType Directory -Force | Out-Null
    }

    $script:QLogRoot = $Root
}

function Start-QLogSession {
    param(
        [string]$Prefix = "QuinnOptimiserToolkit"
    )

    Ensure-QLogRoot

    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $fileName  = "{0}_{1}.log" -f $Prefix, $timestamp
    $script:QLogFile = Join-Path $script:QLogRoot $fileName

    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] Log session started." |
        Out-File -FilePath $script:QLogFile -Encoding UTF8 -Force
}

function Write-QLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message

    # Write to console (useful during dev)
    Write-Host $line

    if ($script:QLogFile) {
        Add-Content -LiteralPath $script:QLogFile -Value $line -Encoding UTF8
    }
}

function Write-QOSettingsUILog {
    param([string]$Message)

    Ensure-QLogRoot

    try {
        $path = Join-Path $script:QLogRoot "SettingsUI.log"
        Add-Content -LiteralPath $path -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message) -Encoding UTF8
    } catch { }

    # Optional: also echo into main log stream for dev visibility
    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog "[SettingsUI] $Message" "INFO"
        }
    } catch { }
}

function Stop-QLogSession {
    if ($script:QLogFile) {
        $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Add-Content -LiteralPath $script:QLogFile -Value "[$ts] [INFO] Log session ended." -Encoding UTF8
        $script:QLogFile = $null
    }
}

Export-ModuleMember -Function `
    Set-QLogRoot, `
    Start-QLogSession, `
    Write-QLog, `
    Write-QOSettingsUILog, `
    Stop-QLogSession
