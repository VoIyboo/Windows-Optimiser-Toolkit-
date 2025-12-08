# InstallCommonApps.psm1
# Winget-based helpers for installing common applications

param()

# Make sure logging is available if module is loaded directly
try {
    if (-not (Get-Command Write-QLog -ErrorAction SilentlyContinue)) {
        Import-Module "$PSScriptRoot\..\Core\Logging.psm1" -Force -ErrorAction SilentlyContinue
    }
} catch { }

function Get-QOTCommonAppDefinitions {
    <#
        .SYNOPSIS
            Returns the static list of common apps and their winget IDs.
    #>

    @(
        @{ Name = "Google Chrome";      WingetId = "Google.Chrome"              }
        @{ Name = "Mozilla Firefox";    WingetId = "Mozilla.Firefox"            }
        @{ Name = "7-Zip";              WingetId = "7zip.7zip"                  }
        @{ Name = "VLC Media Player";   WingetId = "VideoLAN.VLC"               }
        @{ Name = "Notepad++";          WingetId = "Notepad++.Notepad++"        }
        @{ Name = "Discord";            WingetId = "Discord.Discord"            }
        @{ Name = "Spotify";            WingetId = "Spotify.Spotify"            }
        @{ Name = "Visual Studio Code"; WingetId = "Microsoft.VisualStudioCode" }
    )
}

function Test-QOTWingetAvailable {
    <#
        .SYNOPSIS
            Checks whether winget is available on this system.
    #>
    try {
        winget --version 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        try { Write-QLog "winget not available: $($_.Exception.Message)" "WARN" } catch { }
        return $false
    }
}

function Test-QOTCommonAppInstalled {
    <#
        .SYNOPSIS
            Uses winget list to see whether the given ID is already installed.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$WingetId
    )

    if (-not (Test-QOTWingetAvailable)) { return $false }

    try {
        $result = winget list --id $WingetId --source winget 2>$null
        if ($LASTEXITCODE -eq 0 -and $result -match [regex]::Escape($WingetId)) {
            return $true
        }
    } catch {
        try { Write-QLog "winget list failed for $WingetId: $($_.Exception.Message)" "WARN" } catch { }
    }

    return $false
}

function Get-QOTCommonApps {
    <#
        .SYNOPSIS
            Returns common apps with basic install status for the UI.
    #>

    $definitions = Get-QOTCommonAppDefinitions
    $list = @()

    $wingetAvailable = Test-QOTWingetAvailable
    if (-not $wingetAvailable) {
        try { Write-QLog "Get-QOTCommonApps: winget not available; marking all as not installable." "WARN" } catch { }
    }

    foreach ($def in $definitions) {
        $installed = $false
        if ($wingetAvailable) {
            $installed = Test-QOTCommonAppInstalled -WingetId $def.WingetId
        }

        $status = if ($installed) { "Installed" } else { "Not installed" }

        $obj = [pscustomobject]@{
            Name           = $def.Name
            WingetId       = $def.WingetId
            Status         = $status
            IsInstalled    = $installed
            IsInstallable  = $wingetAvailable -and -not $installed
            InstallLabel   = if ($installed) { "Installed" } else { "Install" }
            InstallTooltip = if (-not $wingetAvailable) {
                                "winget not available on this system"
                             }
                             elseif ($installed) {
                                "Already installed"
                             }
                             else {
                                "Click to install"
                             }
        }

        $list += $obj
    }

    return $list
}

function Install-QOTCommonApp {
    <#
        .SYNOPSIS
            Installs a single common app by winget ID.
        .OUTPUTS
            [bool] - $true on success, $false on failure.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$WingetId,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Test-QOTWingetAvailable)) {
        try { Write-QLog "Install-QOTCommonApp: winget not available; cannot install $Name." "ERROR" } catch { }
        return $false
    }

    try {
        Write-QLog "Starting install for common app: $Name [$WingetId]"
        $cmd = "winget install --id `"$WingetId`" -h --accept-source-agreements --accept-package-agreements"
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -Wait -WindowStyle Hidden

        if ($LASTEXITCODE -ne 0) {
            Write-QLog "Install-QOTCommonApp: winget returned exit code $LASTEXITCODE for $Name." "WARN"
        } else {
            Write-QLog "Install-QOTCommonApp: install completed for $Name."
        }

        return $true
    } catch {
        try { Write-QLog "Install-QOTCommonApp failed for $Name: $($_.Exception.Message)" "ERROR" } catch { }
        return $false
    }
}

function Install-QOTCommonAppsBulk {
    <#
        .SYNOPSIS
            Installs multiple common apps (array of objects with Name + WingetId).
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Apps
    )

    foreach ($app in $Apps) {
        if (-not $app.WingetId) { continue }
        Install-QOTCommonApp -WingetId $app.WingetId -Name $app.Name | Out-Null
    }
}

Export-ModuleMember -Function `
    Get-QOTCommonAppDefinitions, `
    Test-QOTWingetAvailable, `
    Test-QOTCommonAppInstalled, `
    Get-QOTCommonApps, `
    Install-QOTCommonApp, `
    Install-QOTCommonAppsBulk

