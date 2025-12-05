# src\Core\Logging.psm1
# Central logging utilities for Quinn Optimiser Toolkit

# Script scoped variables used only inside this module
$script:QOT_LogRoot       = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
$script:QOT_CurrentLog    = $null
$script:QOT_SessionId     = [guid]::NewGuid().ToString()
$script:QOT_HasHeader     = $false

function Set-QLogRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    if (-not (Test-Path $Root)) {
        New-Item -Path $Root -ItemType Directory -Force | Out-Null
    }

    $script:QOT_LogRoot = (Resolve-Path $Root).Path
}

function Get-QLogRoot {
    return $script:QOT_LogRoot
}

function Get-QLogPath {
    # One log per day per machine, with a session id tag in the header
    $dateStamp = (Get-Date).ToString("yyyy-MM-dd")
    $fileName  = "QOT-$dateStamp.log"
    $fullPath  = Join-Path $script:QOT_LogRoot $fileName

    if (-not (Test-Path $script:QOT_LogRoot)) {
        New-Item -Path $script:QOT_LogRoot -ItemType Directory -Force | Out-Null
    }

    $script:QOT_CurrentLog = $fullPath
    return $fullPath
}

function Start-QLogSession {
    # Ensure we have a log path
    $null = Get-QLogPath

    if (-not $script:QOT_HasHeader) {
        $header = "===== Quinn Optimiser Toolkit session started {0}  SessionId={1} =====" -f `
                  (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $script:QOT_SessionId
        Add-Content -Path $script:QOT_CurrentLog -Value $header
        $script:QOT_HasHeader = $true
    }
}

function Write-QLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO","WARN","ERROR","DEBUG")]
        [string]$Level = "INFO"
    )

    if (-not $script:QOT_CurrentLog) {
        # Lazy init if Start-QLogSession was not called yet
        Start-QLogSession
    }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message
    Add-Content -Path $script:QOT_CurrentLog -Value $line
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Level = "INFO"
    )
    # Backwards compatible wrapper that just forwards to Write-QLog
    Write-QLog -Message $Message -Level $Level
}

Export-ModuleMember -Function `
    Set-QLogRoot, Get-QLogRoot, Get-QLogPath, `
    Start-QLogSession, Write-QLog, Write-Log

