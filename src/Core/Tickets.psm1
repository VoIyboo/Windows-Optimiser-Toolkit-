# src\Core\Tickets.psm1
# Core ticket storage + model (NO UI CODE IN HERE)

$ErrorActionPreference = "Stop"

# Only import Settings here
Import-Module (Join-Path $PSScriptRoot "Settings.psm1") -Force -ErrorAction Stop

function Get-QOTicketsStorePath {
    $s = Get-QOSettings

    if ($s -and $s.PSObject.Properties.Name -contains "TicketStorePath" -and $s.TicketStorePath) {
        return [string]$s.TicketStorePath
    }

    # Safe default if not set yet
    $defaultDir = Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Tickets"
    return (Join-Path $defaultDir "Tickets.json")
}

function Ensure-QOTicketsStoreDirectory {
    $path = Get-QOTicketsStorePath
    $dir  = Split-Path $path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $path
}

function Get-QOTickets {
    $path = Ensure-QOTicketsStoreDirectory

    if (-not (Test-Path $path)) {
        $db = [pscustomobject]@{
            Version   = 1
            UpdatedAt = (Get-Date).ToString("o")
            Tickets   = @()
        }
        $db | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
        return $db
    }

    $raw = Get-Content -Path $path -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{ Version = 1; UpdatedAt = (Get-Date).ToString("o"); Tickets = @() }
    }

    $db = $raw | ConvertFrom-Json

    if (-not ($db.PSObject.Properties.Name -contains "Tickets") -or $null -eq $db.Tickets) {
        $db | Add-Member -NotePropertyName Tickets -NotePropertyValue @() -Force
    }

    $db.Tickets = @($db.Tickets)
    return $db
}

function Save-QOTickets {
    param(
        [Parameter(Mandatory)]
        $Db
    )

    $path = Ensure-QOTicketsStoreDirectory
    $Db.UpdatedAt = (Get-Date).ToString("o")
    $Db | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
}

function New-QOTicket {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Description,
        [string]$Category = "General",
        [string]$Priority = "Normal"
    )

    [pscustomobject]@{
        Id          = ([guid]::NewGuid().ToString())
        Title       = $Title
        Description = $Description
        Category    = $Category
        Priority    = $Priority
        Status      = "New"
        CreatedAt   = (Get-Date).ToString("o")
        AssignedTo   = 'Unassigned'
        AssignedToId = $null
    }
}

function Add-QOTicket {
    param(
        [Parameter(Mandatory)]
        $Ticket
    )

    $db = Get-QOTickets
    $db.Tickets = @($db.Tickets) + @($Ticket)
    Save-QOTickets -Db $db
    return $Ticket
}

function Remove-QOTicket {
    param(
        [Parameter(Mandatory)][string]$Id
    )

    $db = Get-QOTickets
    $before = @($db.Tickets).Count
    $db.Tickets = @($db.Tickets | Where-Object { $_.Id -ne $Id })
    $after = @($db.Tickets).Count

    if ($after -ne $before) {
        Save-QOTickets -Db $db
        return $true
    }

    return $false
}

Export-ModuleMember -Function Get-QOTickets, Add-QOTicket, Remove-QOTicket, New-QOTicket
