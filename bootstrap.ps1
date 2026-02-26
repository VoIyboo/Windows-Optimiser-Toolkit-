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
                Invoke-WebRequest -Uri $url -OutFile $OutFile -UseBasicParsing | Out-Null

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
        "Volyboo",
        "VoIyboo"
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
    $rootFolder = Get-ChildItem $baseTemp -Directory |
        Where-Object { $_.Name -like "$repoName*" } |
        Select-Object -First 1

    if (-not $rootFolder) {
        throw "Could not locate extracted repo folder"
    }

    $toolkitRoot = $rootFolder.FullName
    $introPath   = Join-Path $toolkitRoot "src\Intro\Intro.ps1"

    if (-not (Test-Path $introPath)) {
        throw "Intro.ps1 not found"
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
