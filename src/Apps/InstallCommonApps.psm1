# src\Apps\InstallCommonApps.psm1
# Common apps catalogue + winget install logic
# Goals
# - Keep the Apps tab fast (do NOT run winget list during UI init)
# - Provide a static catalogue for the grid (checkbox, name, version)
# - Only check winget installed state when explicitly requested (optional)
# - Only run installs when Run selected actions is clicked

param()

Import-Module "$PSScriptRoot\..\Core\Config\Config.psm1"   -Force -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\Core\Logging\Logging.psm1" -Force -ErrorAction SilentlyContinue

# -------------------------------------------------------------------
# Winget installed cache (optional, on demand)
# -------------------------------------------------------------------
$script:QOT_WingetInstalledCache     = $null
$script:QOT_WingetInstalledCacheTime = [datetime]::MinValue

function Test-QOTWingetAvailable {
    try {
        $null = winget --version 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        try { Write-QLog ("winget --version failed: {0}" -f $_.Exception.Message) "WARN" } catch { }
        return $false
    }
}

function Get-QOTWingetInstalledIdSet {
    param(
        # Refresh cache every 5 minutes by default
        [int]$CacheMinutes = 5,

        # If set, force a refresh now
        [switch]$ForceRefresh
    )

    if (-not $ForceRefresh) {
        if ($script:QOT_WingetInstalledCache -and ((Get-Date) - $script:QOT_WingetInstalledCacheTime).TotalMinutes -lt $CacheMinutes) {
            return $script:QOT_WingetInstalledCache
        }
    }

    $set = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)

    if (-not (Test-QOTWingetAvailable)) {
        $script:QOT_WingetInstalledCache     = $set
        $script:QOT_WingetInstalledCacheTime = Get-Date
        return $set
    }

    try {
        # winget list output is not a stable table, so we do "best effort" parsing.
        # This is intentionally called only when needed (not at UI load).
        $lines = @(winget list --source winget 2>$null)

        foreach ($line in $lines) {
            # Capture IDs like Vendor.App or Vendor.App.Sub
            if ($line -match "([A-Za-z0-9]+\.[A-Za-z0-9][A-Za-z0-9\.\-_]+)") {
                [void]$set.Add($matches[1])
            }
        }
    }
    catch {
        try { Write-QLog ("winget list failed: {0}" -f $_.Exception.Message) "WARN" } catch { }
    }

    $script:QOT_WingetInstalledCache     = $set
    $script:QOT_WingetInstalledCacheTime = Get-Date
    return $set
}

function Test-QOTWingetAppInstalled {
    param(
        [Parameter(Mandatory)]
        [string]$WingetId
    )

    $set = Get-QOTWingetInstalledIdSet
    return $set.Contains($WingetId)
}

# -------------------------------------------------------------------
# Catalogue (fast, static)
# -------------------------------------------------------------------
function Get-QOTCommonAppsCatalogue {
    <#
        .SYNOPSIS
            Returns a static catalogue for the Common app installs grid.

        .NOTES
            - This function does NOT call winget.
            - Keeps the UI fast.
            - Version is displayed as "Latest" by design (winget resolves actual versions during install).
    #>

    $apps = @(
        # Browsers
        [pscustomobject]@{ IsSelected=$false; Name="Google Chrome";        Version="Latest"; WingetId="Google.Chrome";               Category="Browser" }
        [pscustomobject]@{ IsSelected=$false; Name="Mozilla Firefox";      Version="Latest"; WingetId="Mozilla.Firefox";             Category="Browser" }
        [pscustomobject]@{ IsSelected=$false; Name="Microsoft Edge";       Version="Latest"; WingetId="Microsoft.Edge";              Category="Browser" }
        [pscustomobject]@{ IsSelected=$false; Name="Brave Browser";        Version="Latest"; WingetId="Brave.Brave";                 Category="Browser" }

        # Utilities
        [pscustomobject]@{ IsSelected=$false; Name="7-Zip";                Version="Latest"; WingetId="7zip.7zip";                   Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="WinRAR";               Version="Latest"; WingetId="RARLab.WinRAR";               Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="Notepad++";            Version="Latest"; WingetId="Notepad++.Notepad++";         Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="Everything Search";    Version="Latest"; WingetId="voidtools.Everything";        Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="PowerToys";            Version="Latest"; WingetId="Microsoft.PowerToys";         Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="Greenshot";            Version="Latest"; WingetId="Greenshot.Greenshot";         Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="ShareX";               Version="Latest"; WingetId="ShareX.ShareX";               Category="Utility" }
        [pscustomobject]@{ IsSelected=$false; Name="Adobe Acrobat Reader"; Version="Latest"; WingetId="Adobe.Acrobat.Reader.64-bit"; Category="Utility" }

        # Media
        [pscustomobject]@{ IsSelected=$false; Name="VLC Media Player";     Version="Latest"; WingetId="VideoLAN.VLC";                Category="Media" }
        [pscustomobject]@{ IsSelected=$false; Name="Spotify";              Version="Latest"; WingetId="Spotify.Spotify";             Category="Media" }
        [pscustomobject]@{ IsSelected=$false; Name="OBS Studio";           Version="Latest"; WingetId="OBSProject.OBSStudio";        Category="Media" }
        [pscustomobject]@{ IsSelected=$false; Name="Audacity";             Version="Latest"; WingetId="Audacity.Audacity";           Category="Media" }

        # Communication
        [pscustomobject]@{ IsSelected=$false; Name="Microsoft Teams";      Version="Latest"; WingetId="Microsoft.Teams";             Category="Communication" }
        [pscustomobject]@{ IsSelected=$false; Name="Zoom";                 Version="Latest"; WingetId="Zoom.Zoom";                   Category="Communication" }
        [pscustomobject]@{ IsSelected=$false; Name="Discord";              Version="Latest"; WingetId="Discord.Discord";             Category="Communication" }
        [pscustomobject]@{ IsSelected=$false; Name="Slack";                Version="Latest"; WingetId="SlackTechnologies.Slack";     Category="Communication" }

        # Dev / IT
        [pscustomobject]@{ IsSelected=$false; Name="Visual Studio Code";   Version="Latest"; WingetId="Microsoft.VisualStudioCode";  Category="Dev" }
        [pscustomobject]@{ IsSelected=$false; Name="Git";                  Version="Latest"; WingetId="Git.Git";                     Category="Dev" }
        [pscustomobject]@{ IsSelected=$false; Name="GitHub Desktop";       Version="Latest"; WingetId="GitHub.GitHubDesktop";        Category="Dev" }
        [pscustomobject]@{ IsSelected=$false; Name="Python 3";             Version="Latest"; WingetId="Python.Python.3";             Category="Dev" }
        [pscustomobject]@{ IsSelected=$false; Name="Node.js LTS";          Version="Latest"; WingetId="OpenJS.NodeJS.LTS";           Category="Dev" }
        [pscustomobject]@{ IsSelected=$false; Name="PuTTY";                Version="Latest"; WingetId="PuTTY.PuTTY";                 Category="Dev" }
        [pscustomobject]@{ IsSelected=$false; Name="WinSCP";               Version="Latest"; WingetId="WinSCP.WinSCP";               Category="Dev" }

        # Cloud
        [pscustomobject]@{ IsSelected=$false; Name="OneDrive";             Version="Latest"; WingetId="Microsoft.OneDrive";          Category="Cloud" }
        [pscustomobject]@{ IsSelected=$false; Name="Google Drive";         Version="Latest"; WingetId="Google.Drive";                Category="Cloud" }
        [pscustomobject]@{ IsSelected=$false; Name="Dropbox";              Version="Latest"; WingetId="Dropbox.Dropbox";             Category="Cloud" }
    )

    return $apps
}

function Get-QOTCommonApps {
    <#
        .SYNOPSIS
            Returns common apps for the UI, optionally adding Installed/Available status.

        .PARAMETER IncludeStatus
            If set, will call winget list (cached) to mark items Installed/Available.
            Leave this OFF for fastest UI loads.
    #>
    param(
        [switch]$IncludeStatus
    )

    $catalogue = @(Get-QOTCommonAppsCatalogue)

    if (-not $IncludeStatus) {
        foreach ($app in $catalogue) {
            if ($null -eq $app.PSObject.Properties["Status"])        { $app | Add-Member -NotePropertyName Status        -NotePropertyValue "" -Force }
            if ($null -eq $app.PSObject.Properties["IsInstallable"]) { $app | Add-Member -NotePropertyName IsInstallable -NotePropertyValue $true -Force }
        }
        return $catalogue
    }

    $wingetOk = Test-QOTWingetAvailable
    $set = $null
    if ($wingetOk) { $set = Get-QOTWingetInstalledIdSet }

    foreach ($app in $catalogue) {
        $installed = $false
        $status    = "Unknown"

        if ($wingetOk) {
            $installed = $set.Contains($app.WingetId)
            $status = if ($installed) { "Installed" } else { "Available" }
        }

        $app | Add-Member -NotePropertyName Status        -NotePropertyValue $status -Force
        $app | Add-Member -NotePropertyName IsInstallable -NotePropertyValue (-not $installed) -Force
    }

    return $catalogue
}

# -------------------------------------------------------------------
# Install
# -------------------------------------------------------------------
function Install-QOTCommonApp {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$WingetId
    )

    if (-not (Test-QOTWingetAvailable)) {
        $msg = "winget is not available; cannot install $Name [$WingetId]."
        try { Write-QLog $msg "ERROR" } catch { }
        throw $msg
    }

    try { Write-QLog ("Starting install: {0} [{1}]" -f $Name, $WingetId) } catch { }

    # Use Start-Process with explicit args, avoids quoting bugs
    $args = @(
        "install",
        "--id", $WingetId,
        "-e",
        "--silent",
        "--accept-source-agreements",
        "--accept-package-agreements"
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "winget"
    $psi.Arguments              = ($args -join " ")
    $psi.CreateNoWindow         = $true
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    if ($stdout) { try { Write-QLog ("winget output: {0}" -f $stdout.Trim()) "DEBUG" } catch { } }

    if ($proc.ExitCode -ne 0) {
        if ($stderr) { try { Write-QLog ("winget error: {0}" -f $stderr.Trim()) "ERROR" } catch { } }
        throw ("winget returned exit code {0} while installing {1} [{2}]." -f $proc.ExitCode, $Name, $WingetId)
    }

    try { Write-QLog ("Install succeeded: {0} [{1}]" -f $Name, $WingetId) } catch { }

    # Optional: refresh cache so subsequent checks are accurate
    try { $null = Get-QOTWingetInstalledIdSet -ForceRefresh } catch { }
}

Export-ModuleMember -Function `
    Get-QOTCommonAppsCatalogue, `
    Get-QOTCommonApps, `
    Test-QOTWingetAvailable, `
    Get-QOTWingetInstalledIdSet, `
    Test-QOTWingetAppInstalled, `
    Install-QOTCommonApp
