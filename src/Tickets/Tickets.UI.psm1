# src\Tickets\Tickets.UI.psm1
# UI wiring for Tickets tab

$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "..\Core\Tickets.psm1") -Force -ErrorAction Stop

# ------------------------------------------------------------
# PowerShell 5.1 safe helpers (NO ?? operator)
# ------------------------------------------------------------
function Get-QOSafeString {
    param([object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return ([string]$Value)
}

# ------------------------------------------------------------
# Create ticket from email object
# ------------------------------------------------------------
function Add-QOTicketFromEmail {
    param(
        [Parameter(Mandatory)]
        $Email
    )

    $subject = (Get-QOSafeString $Email.Subject).Trim()
    $from    = (Get-QOSafeString $Email.From).Trim()

    $body = ""
    if ($Email.PSObject.Properties.Name -contains "Body") {
        $body = (Get-QOSafeString $Email.Body).Trim()
    }
    elseif ($Email.PSObject.Properties.Name -contains "Snippet") {
        $body = (Get-QOSafeString $Email.Snippet).Trim()
    }

    if ([string]::IsNullOrWhiteSpace($subject)) {
        $subject = "Email ticket"
    }

    if ([string]::IsNullOrWhiteSpace($from)) {
        $from = "Unknown sender"
    }

    $ticket = New-QOTicket -Title $subject

    # Optional metadata (safe if fields exist)
    try {
        if ($ticket.PSObject.Properties.Name -contains "Source") { $ticket.Source = "Email" }
        if ($ticket.PSObject.Properties.Name -contains "From")   { $ticket.From = $from }
        if ($ticket.PSObject.Properties.Name -contains "Body")   { $ticket.Body = $body }
    } catch { }

    Add-QOTicket -Ticket $ticket | Out-Null
    return $ticket
}



# -------------------------
# State
# -------------------------
$script:TicketsGrid = $null
$script:TicketsEmailSyncRan = $false

# -------------------------
# Helpers
# -------------------------
function Write-QOTicketsUILog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Level = "INFO"
    )

    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog $Message $Level
        }
    } catch { }
}

function Get-QOTicketsForGrid {
    # Supports either:
    # - Get-QOTickets -> { Tickets = @(...) }
    # - Get-QOTickets -> @(...) directly
    try {
        $db = Get-QOTickets

        if ($null -eq $db) { return @() }

        if ($db -is [System.Collections.IEnumerable] -and -not ($db.PSObject.Properties.Name -contains "Tickets")) {
            return @($db)
        }

        if ($db.PSObject.Properties.Name -contains "Tickets") {
            return @($db.Tickets)
        }

        return @()
    }
    catch {
        return @()
    }
}

function Refresh-QOTicketsGrid {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    try {
        $items = @(Get-QOTicketsForGrid)
        $Grid.ItemsSource = $items
        $Grid.Items.Refresh()
    }
    catch {
        [System.Windows.MessageBox]::Show(
            "Load tickets failed.`r`n$($_.Exception.Message)"
        ) | Out-Null
    }
}

function Invoke-QOTicketsEmailSyncAndRefresh {
    param(
        [Parameter(Mandatory)]
        [System.Windows.Controls.DataGrid]$Grid
    )

    Write-QOTicketsUILog "Tickets: Email sync started"

    try {
        # This will be created in Step 5 (email fetch + ticket creation)
        if (Get-Command Sync-QOTicketsFromEmail -ErrorAction SilentlyContinue) {
            Sync-QOTicketsFromEmail
            Write-QOTicketsUILog "Tickets: Email sync finished"
        } else {
            Write-QOTicketsUILog "Tickets: Sync-QOTicketsFromEmail not found (skipping)" "WARN"
        }
    }
    catch {
        Write-QOTicketsUILog ("Tickets: Email sync failed: " + $_.Exception.Message) "ERROR"
    }

    # Always refresh afterwards, even if sync was skipped
    Refresh-QOTicketsGrid -Grid $Grid
}

# -------------------------
# Main wiring
# -------------------------
function Initialize-QOTicketsUI {
    param(
        [Parameter(Mandatory)]
        $Window
    )

    Add-Type -AssemblyName PresentationFramework | Out-Null

    $script:TicketsGrid = $Window.FindName("TicketsGrid")
    $btnRefresh         = $Window.FindName("BtnRefreshTickets")
    $btnNew             = $Window.FindName("BtnNewTicket")
    $btnDelete          = $Window.FindName("BtnDeleteTicket")

    if (-not $script:TicketsGrid) {
        [System.Windows.MessageBox]::Show("Missing XAML control: TicketsGrid") | Out-Null
        return
    }
    if (-not $btnRefresh) {
        [System.Windows.MessageBox]::Show("Missing XAML control: BtnRefreshTickets") | Out-Null
        return
    }
    if (-not $btnNew) {
        [System.Windows.MessageBox]::Show("Missing XAML control: BtnNewTicket") | Out-Null
        return
    }
    if (-not $btnDelete) {
        [System.Windows.MessageBox]::Show("Missing XAML control: BtnDeleteTicket") | Out-Null
        return
    }

    # Run one time sync when the grid first loads (first time you open Tickets tab)
    $script:TicketsGrid.AddHandler(
        [System.Windows.FrameworkElement]::LoadedEvent,
        [System.Windows.RoutedEventHandler]{
            try {
                if (-not $script:TicketsEmailSyncRan) {
                    $script:TicketsEmailSyncRan = $true
                    Invoke-QOTicketsEmailSyncAndRefresh -Grid $script:TicketsGrid
                } else {
                    Refresh-QOTicketsGrid -Grid $script:TicketsGrid
                }
            } catch { }
        }
    )

    # Manual refresh button: also runs sync (so you can pull new emails on demand)
    $btnRefresh.Add_Click({
        Invoke-QOTicketsEmailSyncAndRefresh -Grid $script:TicketsGrid
    })

    # New ticket (inline edit)
    $btnNew.Add_Click({
        try {
            $ticket = New-QOTicket -Title "New ticket"
            Add-QOTicket -Ticket $ticket | Out-Null

            Refresh-QOTicketsGrid -Grid $script:TicketsGrid

            $script:TicketsGrid.SelectedItem = $ticket
            $script:TicketsGrid.ScrollIntoView($ticket)

            if ($script:TicketsGrid.Columns.Count -gt 0) {
                $script:TicketsGrid.CurrentCell = New-Object System.Windows.Controls.DataGridCellInfo(
                    $ticket,
                    $script:TicketsGrid.Columns[0]
                )
                $script:TicketsGrid.BeginEdit()
            }
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Create ticket failed.`r`n$($_.Exception.Message)"
            ) | Out-Null
        }
    })

    # Delete ticket
    $btnDelete.Add_Click({
        try {
            $selected = $script:TicketsGrid.SelectedItem
            if (-not $selected) {
                [System.Windows.MessageBox]::Show("Select a ticket first.") | Out-Null
                return
            }

            if (-not ($selected.PSObject.Properties.Name -contains "Id")) {
                [System.Windows.MessageBox]::Show("Selected ticket has no Id.") | Out-Null
                return
            }

            $confirm = [System.Windows.MessageBox]::Show(
                "Delete this ticket?",
                "Confirm",
                "YesNo",
                "Warning"
            )

            if ($confirm -ne "Yes") { return }

            Remove-QOTicket -Id $selected.Id | Out-Null
            Refresh-QOTicketsGrid -Grid $script:TicketsGrid
        }
        catch {
            [System.Windows.MessageBox]::Show(
                "Delete ticket failed.`r`n$($_.Exception.Message)"
            ) | Out-Null
        }
    })

    # Initial load (fast, no email sync here, LoadedEvent will handle the first sync)
    Refresh-QOTicketsGrid -Grid $script:TicketsGrid
}

Export-ModuleMember -Function `
    Get-QOTickets, `
    Add-QOTicket, `
    Remove-QOTicket, `
    Add-QOTicketFromEmail
