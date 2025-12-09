# Logging.psm1
# Simple logging utilities for Quinn Optimiser Toolkit

# Module-scoped variables
$script:QLogRoot = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
$script:QLogFile = $null

function Set-QLogRoot {
    param(
        [string]$Root
    )

    if (-not $Root) {
        throw "Set-QLogRoot: Root path cannot be empty."
    }

    if (-not (Test-Path $Root)) {
        New-Item -Path $Root -ItemType Directory -Force | Out-Null
    }

    $script:QLogRoot = $Root
}

function Start-QLogSession {
    param(
        [string]$Prefix = "QuinnOptimiserToolkit"
    )

    if (-not $script:QLogRoot) {
        $script:QLogRoot = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        if (-not (Test-Path $script:QLogRoot)) {
            New-Item -Path $script:QLogRoot -ItemType Directory -Force | Out-Null
        }
    }

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
        Add-Content -Path $script:QLogFile -Value $line
    }
}

function Stop-QLogSession {
    if ($script:QLogFile) {
        $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $script:QLogFile -Value "[$ts] [INFO] Log session ended."
        $script:QLogFile = $null
    }
}

Export-ModuleMember -Function Set-QLogRoot, Start-QLogSession, Write-QLog, Stop-QLogSession
