# src\Core\Tickets.psm1 # Storage and basic model for Studio Voly Ticketing System (NO UI CODE)
$ErrorActionPreference = "Stop"

# Only import Settings here
Import-Module (Join-Path $PSScriptRoot "Settings.psm1") -Force -ErrorAction Stop

# =====================================================================
# Script state
# =====================================================================
$script:TicketStorePath = $null
$script:TicketBackupPath = $null

# =====================================================================
# Helpers
# =====================================================================
function Ensure-QOSettingProperty {
    param(
        [Parameter(Mandatory)]
        [object]$Settings,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        $DefaultValue
    )

    if (-not $Settings) {
        throw "Settings object is null."
    }

    if ($Settings.PSObject.Properties.Name -notcontains $Name) {
        $Settings | Add-Member -NotePropertyName $Name -NotePropertyValue $DefaultValue
    }

    return $Settings
}

function New-QODefaultTicketDatabase {
    return [pscustomobject]@{ SchemaVersion = 1 Tickets = @() }
}

# =====================================================================
# Storage initialisation
# =====================================================================
function Initialize-QOTicketStorage {
    if ($script:TicketStorePath -and $script:TicketBackupPath) { return }

    $settings = Get-QOSettings

    $settings = Ensure-QOSettingProperty -Settings $settings -Name "TicketStorePath" -DefaultValue ""
    $settings = Ensure-QOSettingProperty -Settings $settings -Name "LocalTicketBackupPath" -DefaultValue ""
    $settings = Ensure-QOSettingProperty -Settings $settings -Name "TicketsColumnLayout" -DefaultValue @()

    if ([string]::IsNullOrWhiteSpace([string]$settings.TicketStorePath)) {
        $defaultTicketsDir = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets"
        $defaultTicketsFile = Join-Path $defaultTicketsDir "Tickets.json"
        $settings.TicketStorePath = $defaultTicketsFile
    }

    if ([string]::IsNullOrWhiteSpace([string]$settings.LocalTicketBackupPath)) {
        $defaultBackupDir = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets\Backups"
        $settings.LocalTicketBackupPath = $defaultBackupDir
    }

    Save-QOSettings -Settings $settings

    $script:TicketStorePath = [string]$settings.TicketStorePath
    $script:TicketBackupPath = [string]$settings.LocalTicketBackupPath

    $storeDir = Split-Path -Parent $script:TicketStorePath
    if (-not (Test-Path -LiteralPath $storeDir)) {
        New-Item -ItemType Directory -Path $storeDir -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $script:TicketBackupPath)) {
        New-Item -ItemType Directory -Path $script:TicketBackupPath -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $script:TicketStorePath)) {
        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
    }
}

# =====================================================================
# Database IO
# =====================================================================
function Get-QOTickets {
    Initialize-QOTicketStorage

    try {
        $json = Get-Content -LiteralPath $script:TicketStorePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) {
            return New-QODefaultTicketDatabase
        }

        $db = $json | ConvertFrom-Json -ErrorAction Stop

        if (-not $db.PSObject.Properties.Name.Contains("SchemaVersion")) {
            $db | Add-Member -NotePropertyName "SchemaVersion" -NotePropertyValue 1
        }
        if (-not $db.PSObject.Properties.Name.Contains("Tickets")) {
            $db | Add-Member -NotePropertyName "Tickets" -NotePropertyValue @()
        }

        if ($null -eq $db.Tickets) {
            $db.Tickets = @()
        } else {
            $db.Tickets = @($db.Tickets)
        }

        return $db
    }
    catch {
        try {
            if (Test-Path -LiteralPath $script:TicketStorePath) {
                $backupName = Join-Path $script:TicketBackupPath ("Tickets_corrupt_{0}.json" -f (Get-Date -Format "yyyyMMddHHmmss"))
                Copy-Item -LiteralPath $script:TicketStorePath -Destination $backupName -ErrorAction SilentlyContinue
            }
        }
        catch { }

        $db = New-QODefaultTicketDatabase
        $db | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:TicketStorePath -Encoding UTF8
        return $db
    }
}

# (All CRUD functions follow here — New-QOTicket, Add-QOTicket, etc, exactly as in the repo)

Export-ModuleMember -Function `
    Initialize-QOTicketStorage,
    New-QODefaultTicketDatabase,
    Get-QOTickets,
    Save-QOTickets,
    New-QOTicket,
    Add-QOTicket,
    Get-QOTicketById,
    Remove-QOTicket,
    Set-QOTicketStatus,
    Set-QOTicketTitle
