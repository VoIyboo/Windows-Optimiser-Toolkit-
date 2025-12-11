# Tickets.psm1
# Storage and basic model for Studio Voly Ticketing System

# We use settings.json to decide where tickets live.
# Tickets are stored as JSON at a primary path, with timestamped backups.

# Script-level cache of resolved paths
$script:TicketStorePath   = $null
$script:TicketBackupPath  = $null

function Initialize-QOTicketStorage {
    <#
        Resolves and ensures ticket store and backup paths exist.
        Uses Get-QOSettings / Save-QOSettings from Settings.psm1.
    #>

    if ($script:TicketStorePath -and $script:TicketBackupPath) {
        return
    }

    # Load current settings
    $settings = Get-QOSettings

    # Default primary store:
    #   %LOCALAPPDATA%\StudioVoly\QuinnToolkit\Tickets\Tickets.json
    if ([string]::IsNullOrWhiteSpace($settings.TicketStorePath)) {
        $defaultTicketsDir  = Join-Path $env:LOCALAPPDATA 'StudioVoly\QuinnToolkit\Tickets'
        $defaultTicketsFile = Join-Path $defaultTicketsDir 'Tickets.json'
        $settings.TicketStorePath = $defaultTicketsFile
    }

    # Default backup folder:
    #   %LOCALAPPDATA%\StudioVoly\QuinnToolkit\Tickets\Backups
    if ([string]::IsNullOrWhiteSpace($settings.LocalTicketBackupPath)) {
        $defaultBackupDir = Join-Path $env:LOCALAPPDATA 'StudioVoly\QuinnToolkit\Tickets\Backups'
        $settings.LocalTicketBackupPath = $defaultBackupDir
    }

    # Persist any new defaults back to settings.json
    Save-QOSettings -Settings $settings

    $script:TicketStorePath  = $settings.TicketStorePath
    $script:TicketBackupPath = $settings.LocalTicketBackupPath

    # Ensure the primary folder exists
    $storeDir = Split-Path -Parent $script:TicketStorePath
    if (-not (Test-Path -LiteralPath $storeDir)) {
        New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
    }

    # Ensure the backup folder exists
    if (-not (Test-Path -LiteralPath $script:TicketBackupPath)) {
        New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null
    }

    # Ensure the main tickets file exists
    if (-not (Test-Path -LiteralPath $script:TicketStorePath)) {
        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
    }
}

function New-QODefaultTicketDatabase {
    <#
        Creates a blank ticket database object.

        {
          "SchemaVersion": 1,
          "Tickets": []
        }
    #>
    $db = [pscustomobject]@{
        SchemaVersion = 1
        Tickets       = @()
    }

    return $db
}

function Get-QOTickets {
    <#
        Returns the current ticket database object.
        If the file is missing or corrupted, it self-heals with a default DB.
    #>

    Initialize-QOTicketStorage

    try {
        $json = Get-Content -LiteralPath $script:TicketStorePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) {
            return New-QODefaultTicketDatabase
        }

        $db = $json | ConvertFrom-Json -ErrorAction Stop

        # Light schema self-heal if needed
        if (-not $db.PSObject.Properties.Name.Contains('SchemaVersion')) {
            $db | Add-Member -NotePropertyName 'SchemaVersion' -NotePropertyValue 1
        }
        if (-not $db.PSObject.Properties.Name.Contains('Tickets')) {
            $db | Add-Member -NotePropertyName 'Tickets' -NotePropertyValue @()
        }

        return $db
    }
    catch {
        # Backup the broken file, then recreate
        try {
            if (Test-Path -LiteralPath $script:TicketStorePath) {
                $backupName = Join-Path $script:TicketBackupPath ("Tickets_corrupt_{0}.json" -f (Get-Date -Format 'yyyyMMddHHmmss'))
                Copy-Item -LiteralPath $script:TicketStorePath -Destination $backupName -ErrorAction SilentlyContinue
            }
        } catch { }

        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
        return $db
    }
}

function Save-QOTickets {
    <#
        Saves the provided ticket database to the primary path
        and writes a timestamped backup copy.
    #>
    param(
        [Parameter(Mandatory = $true)]
        $TicketsDb
    )

    Initialize-QOTicketStorage

    # Primary save
    $TicketsDb | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8

    # Backup save (best effort, failures are non fatal)
    try {
        $stamp      = Get-Date -Format 'yyyyMMddHHmmss'
        $backupName = Join-Path $script:TicketBackupPath ("Tickets_{0}.json" -f $stamp)
        $TicketsDb | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $backupName -Encoding UTF8
    } catch {
        # Intentionally ignore backup errors to avoid breaking app usage
    }
}

Export-ModuleMember -Function `
    Initialize-QOTicketStorage, `
    New-QODefaultTicketDatabase, `
    Get-QOTickets, `
    Save-QOTickets
