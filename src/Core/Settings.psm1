# Quinn Optimiser Toolkit - Settings module
# Handles global JSON settings for the app

# Path to the settings JSON file in AppData
$script:SettingsPath = Join-Path $env:LOCALAPPDATA 'StudioVoly\QuinnToolkit\settings.json'

function Get-QOSettings {
    <#
        Returns the current settings object.
        If the file does not exist or is broken, creates a default one.
    #>

    if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
        return New-QODefaultSettings
    }

    try {
        $json = Get-Content -LiteralPath $script:SettingsPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) {
            return New-QODefaultSettings
        }

        $settings = $json | ConvertFrom-Json -ErrorAction Stop

        # In case we add new properties in future versions
        $defaults = New-QODefaultSettings -NoSave
        foreach ($prop in $defaults.PSObject.Properties.Name) {
            if (-not $settings.PSObject.Properties.Name.Contains($prop)) {
                $settings | Add-Member -NotePropertyName $prop -NotePropertyValue $defaults.$prop
            }
        }

        return $settings
    }
    catch {
        # Settings file is corrupted, back it up and recreate
        try {
            $backupName = '{0}.bak_{1}' -f $script:SettingsPath, (Get-Date -Format 'yyyyMMddHHmmss')
            Copy-Item -LiteralPath $script:SettingsPath -Destination $backupName -ErrorAction SilentlyContinue
        } catch { }

        return New-QODefaultSettings
    }
}

function New-QODefaultSettings {
    param(
        [switch]$NoSave
    )

    $settings = [pscustomobject]@{
        SchemaVersion          = 1
        TicketStorePath        = ''
        LocalTicketBackupPath  = ''
        PreferredStartTab      = 'Cleaning'   # Cleaning | Apps | Advanced | Tickets
        InternalProtectionKey  = $null        # Will be generated and stored later

        # Tickets tab layout
        TicketsColumnOrder     = @()
        TicketsColumnWidths    = @{}
    }

    $dir = Split-Path -Parent $script:SettingsPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (-not $NoSave) {
        $settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
    }

    return $settings
}

function Save-QOSettings {
    <#
        Persists the provided settings object to disk.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Settings
    )

    $dir = Split-Path -Parent $script:SettingsPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $Settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
}

function Set-QOSetting {
    <#
        Updates a single property in the settings, saves, and returns the new object.

        Example:
            Set-QOSetting -Name 'PreferredStartTab' -Value 'Apps'
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        $Value
    )

    $settings = Get-QOSettings

    if ($settings.PSObject.Properties.Name -notcontains $Name) {
        # If the property does not exist yet, add it
        $settings | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
    else {
        $settings.$Name = $Value
    }

    Save-QOSettings -Settings $settings
    return $settings
}

Export-ModuleMember -Function Get-QOSettings, Save-QOSettings, Set-QOSetting
