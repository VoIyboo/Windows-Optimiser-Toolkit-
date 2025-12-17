# InstallCommonApps.psm1
# Handles the catalogue and winget-based install of common apps

# Import core modules (relative to src\Apps)
Import-Module "$PSScriptRoot\..\Core\Config\Config.psm1"   -Force
Import-Module "$PSScriptRoot\..\Core\Logging\Logging.psm1" -Force

function Get-QOTCommonAppsCatalogue {
    <#
        Returns a list of common apps the toolkit can install via winget.

        Each object:
        - Name     : Display name
        - WingetId : winget package ID
        - Category : Optional grouping (Browser, Utility, etc.)
    #>

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

        # Cloud / Backup
        [pscustomobject]@{ Name="OneDrive";             WingetId="Microsoft.OneDrive";          Category="Cloud" }
        [pscustomobject]@{ Name="Google Drive";         WingetId="Google.Drive";                Category="Cloud" }
        [pscustomobject]@{ Name="Dropbox";              WingetId="Dropbox.Dropbox";             Category="Cloud" }
    )

    return $apps
}

function Test-QOTWingetAvailable {
    <#
        Quick check to see if winget is available on this system.
    #>
    try {
        $null = winget --version 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    catch {
        Write-QLog ("winget --version failed: {0}" -f $_.Exception.Message) "WARN"
    }
    return $false
}

function Test-QOTWingetAppInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WingetId
    )

    if (-not (Test-QOTWingetAvailable)) {
        Write-QLog "Test-QOTWingetAppInstalled: winget is not available on this system." "WARN"
        return $false
    }

    try {
        $result = winget list --id $WingetId --source winget 2>$null
        if ($LASTEXITCODE -eq 0 -and $result -match [regex]::Escape($WingetId)) {
            return $true
        }
    }
    catch {
        Write-QLog ("winget list failed for {0}: {1}" -f $WingetId, $_.Exception.Message) "WARN"
    }

    return $false
}

function Get-QOTCommonApps {
    <#
        Builds the UI-ready common apps list.

        Adds:
        - Status       : Installed / Available / Unknown
        - IsInstallable: True if not installed
        - IsSelected   : For future multi-select support
    #>
    $catalogue = @(Get-QOTCommonAppsCatalogue)

    foreach ($app in $catalogue) {
        $installed = $false
        $status    = "Available"

        if (Test-QOTWingetAvailable) {
            $installed = Test-QOTWingetAppInstalled -WingetId $app.WingetId
            $status    = if ($installed) { "Installed" } else { "Available" }
        }
        else {
            $status    = "Unknown"
        }

        $app | Add-Member -NotePropertyName Status        -NotePropertyValue $status -Force
        $app | Add-Member -NotePropertyName IsInstallable -NotePropertyValue (-not $installed) -Force
        $app | Add-Member -NotePropertyName IsSelected    -NotePropertyValue $false -Force
    }

    return $catalogue
}

function Install-QOTCommonApp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$WingetId
    )

    if (-not (Test-QOTWingetAvailable)) {
        $msg = "Install-QOTCommonApp: winget is not available; cannot install {0} [{1}]." -f $Name, $WingetId
        Write-QLog $msg "ERROR"
        throw $msg
    }

    $cmd = "winget install --id `"$WingetId`" -h --accept-source-agreements --accept-package-agreements"
    Write-QLog ("Starting install for {0} [{1}] with command: {2}" -f $Name, $WingetId, $cmd)

    try {
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

        if ($proc.ExitCode -eq 0) {
            Write-QLog ("Install-QOTCommonApp succeeded for {0} [{1}]." -f $Name, $WingetId)
            if ($stdout) { Write-QLog ("winget output: {0}" -f $stdout.Trim()) "DEBUG" }
        }
        else {
            Write-QLog ("Install-QOTCommonApp FAILED for {0} [{1}] ExitCode={2}" -f $Name, $WingetId, $proc.ExitCode) "ERROR"
            if ($stderr) { Write-QLog ("winget error: {0}" -f $stderr.Trim()) "ERROR" }
            $errMsg = "winget returned exit code {0} while installing {1} [{2}]." -f $proc.ExitCode, $Name, $WingetId
            throw $errMsg
        }
    }
    catch {
        Write-QLog ("Install-QOTCommonApp exception for {0} [{1}]: {2}" -f $Name, $WingetId, $_.Exception.Message) "ERROR"
        throw
    }
}

Export-ModuleMember -Function `
    Get-QOTCommonAppsCatalogue, `
    Get-QOTCommonApps, `
    Test-QOTWingetAvailable, `
    Test-QOTWingetAppInstalled, `
    Install-QOTCommonApp
