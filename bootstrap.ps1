param(
    [string]$Branch = "main",
    [switch]$VerboseStartup
)

# bootstrap.ps1
# Remote bootstrap for: irm "<raw url>" | iex
# Downloads fresh repo zip into TEMP, extracts, runs Intro.ps1
# NEVER touches %LOCALAPPDATA%\StudioVoly\QuinnToolkit

$ErrorActionPreference = "Stop"
$ProgressPreference   = "SilentlyContinue"

$originalLocation = Get-Location

function Invoke-QOTDownloadRepoZip {
    param(
        [Parameter(Mandatory)]
        [string[]]$Urls,

        [Parameter(Mandatory)]
        [string]$OutFile,

        [int]$MaxAttemptsPerUrl = 2
    )

    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($url in $Urls) {
        for ($attempt = 1; $attempt -le $MaxAttemptsPerUrl; $attempt++) {
            try {
                if (Test-Path -LiteralPath $OutFile) {
                    Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
                }

                Write-Host ("Trying ({0}/{1}): {2}" -f $attempt, $MaxAttemptsPerUrl, $url)
                Invoke-QOTWebRequestToFile -Uri $url -OutFile $OutFile

                if (-not (Test-Path -LiteralPath $OutFile)) {
                    throw "Download completed but zip file was not created."
                }

                $fileInfo = Get-Item -LiteralPath $OutFile
                if ($fileInfo.Length -lt 1024) {
                    throw "Downloaded file is unexpectedly small ($($fileInfo.Length) bytes)."
                }

                return
            }
            catch {
                $errors.Add("$url (attempt $attempt): $($_.Exception.Message)") | Out-Null

                if ($attempt -lt $MaxAttemptsPerUrl) {
                    Start-Sleep -Milliseconds 500
                }
            }
        }
    }

    throw "Failed to download repository zip. Errors: $($errors -join '; ')"
}

function Invoke-QOTWebRequestToFile {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$OutFile
    )

    $requestParams = @{
        Uri     = $Uri
        OutFile = $OutFile
    }

    $iwrCommand = Get-Command Invoke-WebRequest -ErrorAction Stop
    if ($iwrCommand.Parameters.ContainsKey('UseBasicParsing')) {
        $requestParams.UseBasicParsing = $true
    }

    Invoke-WebRequest @requestParams | Out-Null
}

function Get-QOTBootstrapLogDir {
    $candidates = @(
        (Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"),
        (Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Logs"),
        (Join-Path $env:TEMP "QuinnOptimiserToolkit\Logs")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        try {
            if (-not (Test-Path -LiteralPath $candidate)) {
                New-Item -ItemType Directory -Path $candidate -Force | Out-Null
            }

            # Confirm write access before choosing the folder.
            $probePath = Join-Path $candidate "write-test.tmp"
            "ok" | Set-Content -LiteralPath $probePath -Encoding UTF8
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue

            return $candidate
        }
        catch {
            # Try next candidate.
        }
    }

    throw "Unable to create a writable log directory for bootstrap."
}

# -------------------------
# Logging
# -------------------------
$logDir = Get-QOTBootstrapLogDir

$bootstrapLog = Join-Path $logDir ("Bootstrap_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Start-Transcript -Path $bootstrapLog | Out-Null

try {
    # TLS
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {}

    # -------------------------
    # Repo info
    # -------------------------
    $repoOwners = @(
        "VoIyboo",
        "Volyboo"
    )
    $repoName  = "Windows-Optimiser-Toolkit-"
    if ([string]::IsNullOrWhiteSpace($Branch)) {
        $Branch = "main"
    }

    $branch = $Branch

    # -------------------------
    # TEMP workspace (code only)
    # -------------------------
    $baseTemp = Join-Path $env:TEMP "QuinnOptimiserToolkit"
    $zipPath  = Join-Path $baseTemp "repo.zip"

    if (Test-Path $baseTemp) {
        Remove-Item $baseTemp -Recurse -Force -ErrorAction SilentlyContinue
    }

    New-Item -ItemType Directory -Path $baseTemp -Force | Out-Null

    # Cache bust
    $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    Write-Host "Downloading Quinn Optimiser Toolkit..."
    Write-Host "Branch: $branch"

    $downloadUrls = New-Object System.Collections.Generic.List[string]

    foreach ($repoOwner in $repoOwners) {
        $downloadUrls.Add("https://github.com/$repoOwner/$repoName/archive/refs/heads/$branch.zip?cb=$cacheBust") | Out-Null
        $downloadUrls.Add("https://codeload.github.com/$repoOwner/$repoName/zip/refs/heads/$branch?cb=$cacheBust") | Out-Null
    }

    Invoke-QOTDownloadRepoZip -Urls $downloadUrls -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $baseTemp -Force

    # -------------------------
    # Resolve extracted folder
    # -------------------------
    $candidateRoots = New-Object System.Collections.Generic.List[string]
    $candidateRoots.Add($baseTemp) | Out-Null

    foreach ($directory in (Get-ChildItem -Path $baseTemp -Directory -Recurse -ErrorAction SilentlyContinue)) {
        $candidateRoots.Add($directory.FullName) | Out-Null
    }

    $toolkitRoot = $null
    $introPath = $null

    foreach ($candidateRoot in ($candidateRoots | Select-Object -Unique)) {
        $candidateIntro = Join-Path $candidateRoot "src\Intro\Intro.ps1"
        if (Test-Path -LiteralPath $candidateIntro) {
            $toolkitRoot = $candidateRoot
            $introPath = $candidateIntro
            break
        }
    }

    if (-not $introPath) {
        throw "Could not locate extracted repo folder (missing src\Intro\Intro.ps1 under: $baseTemp)"
    }
    
    if (-not (Test-Path -LiteralPath $toolkitRoot)) {
        throw "Resolved toolkit root path does not exist: $toolkitRoot"
    }
    
    $introLog = Join-Path $logDir ("Intro_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

    Write-Host ""
    Write-Host "Toolkit root: $toolkitRoot"
    Write-Host "Intro path:   $introPath"
    Write-Host "Intro log:    $introLog"
    Write-Host "Data folder:  $env:LOCALAPPDATA\StudioVoly\QuinnToolkit"
    Write-Host ""

    Set-Location $toolkitRoot

    # -------------------------
    # Launch WPF in Windows PowerShell (STA)
    # -------------------------
    $psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $introArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-STA",
        "-File", $introPath,
        "-LogPath", $introLog
    )

    if (-not $VerboseStartup) {
        $introArgs += "-Quiet"
    }

    & $psExe @introArgs
}
catch {
    try {
        Add-Type -AssemblyName PresentationFramework | Out-Null
        [System.Windows.MessageBox]::Show(
            "Bootstrap failed.`r`n$($_.Exception.Message)",
            "Quinn Optimiser Toolkit"
        ) | Out-Null
    } catch {}
    throw
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
    Set-Location $originalLocation
}
