# InstallCommonApps.psm1
# Handles the catalogue + winget install logic for common apps

param()

Import-Module "$PSScriptRoot\..\Core\Config\Config.psm1"   -Force
Import-Module "$PSScriptRoot\..\Core\Logging\Logging.psm1" -Force

# -------------------------------------------------------------------
# Winget installed cache (speed)
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
    # Refresh cache every 5 minutes
    if ($script:QOT_WingetInstalledCache -and ((Get-Date) - $script:QOT_WingetInstalledCacheTime).TotalMinutes -lt 5) {
        return $script:QOT_WingetInstalledCache
    }

    $set = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)

    if (-not (Test-QOTWingetAvailable)) {
        $script:QOT_WingetInstalledCache     = $set
        $script:QOT_WingetInstalledCacheTime = Get-Date
        return $set
    }

    try {
        $result = winget list --source winget 2>$null

        foreach ($line in $result) {
            # Best effort: capture IDs like Vendor.App or Vendor.App.Sub
            if ($line -match "([A-Za-z0-9]+\.[A-Za-z0-9\.\-_]+)") {
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
# Catalogue
# -------------------------------------------------------------------
function Get-QOTCommonAppsCatalogue {
    $apps = @(
        # Browsers
        [pscustomobject]@{ Name="Google Chrome";        WingetId="Google.Chrome";               Category="Browser" }
        [pscustomobject]@{ Name="Mozilla Firefox";      WingetId="Mozilla.Firefox";             Category="Browser" }
        [pscustomobject]@{ Name="Microsoft Edge";       WingetId="Microsoft.Edge";              Category="Browser" }
        [pscustomobject]@{ Name="Brave Browser";        WingetId="Brave.Brave";                 Category="Browser" }

        # Utilities
        [pscustomobject]@{ Name="7-Zip";                WingetId="7zip.7zip";                   Category="Utility" }
        [pscustomobject]@{ Name="WinRAR";               WingetId="RARLab.WinRAR";               Category="Utility" }
        [pscustomobject]@{ Name="Notepad++";            WingetId="Notepad++.Notepad++";         Category="Utility" }
        [pscustomobject]@{ Name="Everything Search";    WingetId="voidtools.Everything";        Category="Utility" }
        [pscustomobject]@{ Name="PowerToys";            WingetId="Microsoft.PowerToys";         Category="Utility" }
        [pscustomobject]@{ Name="Greenshot";            WingetId="Greenshot.Greenshot";         Category="Utility" }
        [pscustomobject]@{ Name="ShareX";               WingetId="ShareX.ShareX";               Category="Utility" }
        [pscustomobject]@{ Name="Adobe Acrobat Reader"; WingetId="Adobe.Acrobat.Reader.64-bit"; Category="Utility" }

        # Media
        [pscustomobject]@{ Name="VLC Media Player";     WingetId="VideoLAN.VLC";                Category="Media" }
        [pscustomobject]@{ Name="Spotify";              WingetId="Spotify.Spotify";             Category="Media" }
        [pscustomobject]@{ Name="OBS Studio";           WingetId="OBSProject.OBSStudio";        Category="Media" }
        [pscustomobject]@{ Name="Audacity";             WingetId="Audacity.Audacity";           Category="Media" }

        # Communication
        [pscustomobject]@{ Name="Microsoft Teams";      WingetId="Microsoft.Teams";             Category="Communication" }
        [pscustomobject]@{ Name="Zoom";                 WingetId="Zoom.Zoom";                   Category="Communication" }
        [pscustomobject]@{ Name="Discord";              WingetId="Discord.Discord";             Category="Communication" }
        [pscustomobject]@{ Name="Slack";                WingetId="SlackTechnologies.Slack";     Category="Communication" }

        # Dev / IT
        [pscustomobject]@{ Name="Visual Studio Code";   WingetId="Microsoft.VisualStudioCode";  Category="Dev" }
        [pscustomobject]@{ Name="Git";                  WingetId="Git.Git";                     Category="Dev" }
        [pscustomobject]@{ Name="GitHub Desktop";       WingetId="GitHub.GitHubDesktop";        Category="Dev" }
        [pscustomobject]@{ Name="Python 3";             WingetId="Python.Python.3";             Category="Dev" }
        [pscustomobject]@{ Name="Node.js LTS";          WingetId="OpenJS.NodeJS.LTS";           Category="Dev" }
        [pscustomobject]@{ Name="PuTTY";                WingetId="PuTTY.PuTTY";                 Category="Dev" }
        [pscustomobject]@{ Name="WinSCP";               WingetId="WinSCP.WinSCP";               Category="Dev" }

        # Cloud
        [pscustomobject]@{ Name="OneDrive";             WingetId="Microsoft.OneDrive";          Category="Cloud" }
        [pscustomobject]@{ Name="Google Drive";         WingetId="Google.Drive";                Category="Cloud" }
        [pscustomobject]@{ Name="Dropbox";              WingetId="Dropbox.Dropbox";             Category="Cloud" }
    )

    return $apps
}

function Get-QOTCommonApps {
    $catalogue = @(Get-QOTCommonAppsCatalogue)

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
        $app | Add-Member -NotePropertyName IsSelected    -NotePropertyValue $false -Force
    }

    return $catalogue
}

function Install-QOTCommonApp {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$WingetId
    )

    if (-not (Test-QOTWingetAvailable)) {
        $msg = "winget is not available; cannot install $Name [$WingetId]."
        Write-QLog $msg "ERROR"
        throw $msg
    }

    $cmd = "winget install --id `"$WingetId`" -h --accept-source-agreements --accept-package-agreements"
    Write-QLog ("Starting install: {0} [{1}]" -f $Name, $WingetId)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "cmd.exe"
    $psi.Arguments              = "/c $cmd"
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

    if ($proc.ExitCode -ne 0) {
        if ($stderr) { Write-QLog ("winget error: {0}" -f $stderr.Trim()) "ERROR" }
        throw ("winget returned exit code {0} while installing {1} [{2}]." -f $proc.ExitCode, $Name, $WingetId)
    }

    if ($stdout) { Write-QLog ("winget output: {0}" -f $stdout.Trim()) "DEBUG" }
    Write-QLog ("Install succeeded: {0} [{1}]" -f $Name, $WingetId)
}

Export-ModuleMember -Function `
    Get-QOTCommonAppsCatalogue, `
    Get-QOTCommonApps, `
    Test-QOTWingetAvailable, `
    Test-QOTWingetAppInstalled, `
    Install-QOTCommonApp
