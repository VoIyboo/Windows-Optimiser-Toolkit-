# bootstrap.ps1
# Download latest Quinn Optimiser Toolkit build to a temp folder and run Intro.ps1

$ErrorActionPreference = "Stop"

# Remember where the user started
$originalLocation = Get-Location

# Track the PowerShell console window (if any)
$consoleHandle = [IntPtr]::Zero

# Try to load Win32 APIs and minimise the console
try {
    Add-Type -Namespace QOT -Name NativeMethods -MemberDefinition @'
using System;
using System.Runtime.InteropServices;

public static class NativeMethods {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@

    $consoleHandle = [QOT.NativeMethods]::GetConsoleWindow()
    if ($consoleHandle -ne [IntPtr]::Zero) {
        # 6 = SW_MINIMIZE
        [QOT.NativeMethods]::ShowWindow($consoleHandle, 6) | Out-Null
    }
}
catch {
    # If this fails, we just leave the console alone
}

try {
    # Make sure TLS 1.2 is enabled for GitHub
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
    catch { }

    $repoOwner = "VoIyboo"
    $repoName  = "Windows-Optimiser-Toolkit-"
    $branch    = "main"

    # Temp working folder
    $baseTemp  = Join-Path $env:TEMP "QuinnOptimiserToolkit"
    $zipPath   = Join-Path $baseTemp "repo.zip"
    $extractTo = Join-Path $baseTemp "repo"

    if (-not (Test-Path $baseTemp)) {
        New-Item -Path $baseTemp -ItemType Directory -Force | Out-Null
    }

    # Clean old extract
    if (Test-Path $extractTo) {
        Remove-Item $extractTo -Recurse -Force
    }

    $zipUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$branch.zip"

    Write-Host "Downloading Quinn Optimiser Toolkit..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

    Write-Host "Extracting..." -ForegroundColor Cyan
    Expand-Archive -Path $zipPath -DestinationPath $extractTo -Force

    # The extracted folder will be "Windows-Optimiser-Toolkit--main"
    $rootFolder = Get-ChildItem -Path $extractTo | Select-Object -First 1
    if (-not $rootFolder) {
        throw "Could not locate extracted repo folder under $extractTo"
    }

    $toolkitRoot = $rootFolder.FullName
    Write-Host "Toolkit root: $toolkitRoot"

    # Path to Intro.ps1 inside the extracted repo
    $introPath = Join-Path $toolkitRoot "src\Intro\Intro.ps1"

    if (-not (Test-Path $introPath)) {
        throw "Intro.ps1 not found at $introPath"
    }

    # Change location to the toolkit root so relative paths in Intro.ps1 work
    Set-Location $toolkitRoot

    # Hand off to the Intro script (Intro handles Config / Logging / Engine)
    & $introPath
}
finally {
    # Always restore the user's original prompt location
    Set-Location $originalLocation

    # Try to restore the console window if we minimised it
    try {
        if ($consoleHandle -ne [IntPtr]::Zero) {
            # 9 = SW_RESTORE
            [QOT.NativeMethods]::ShowWindow($consoleHandle, 9) | Out-Null
        }
    }
    catch { }
}
