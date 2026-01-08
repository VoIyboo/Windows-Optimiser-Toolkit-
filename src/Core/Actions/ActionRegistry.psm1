# src\Core\Actions\ActionRegistry.psm1
# Central registry for Run selected actions

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\Logging\Logging.psm1" -Force -ErrorAction SilentlyContinue

$script:QOT_ActionGroups = New-Object System.Collections.Generic.List[object]

function Clear-QOTActionGroups {
    $script:QOT_ActionGroups = New-Object System.Collections.Generic.List[object]
}

function Register-QOTActionGroup {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$GetItems
    )

    if (-not $script:QOT_ActionGroups) {
        $script:QOT_ActionGroups = New-Object System.Collections.Generic.List[object]
    }

    $existing = @($script:QOT_ActionGroups | Where-Object { $_.Name -eq $Name })
    foreach ($group in $existing) {
        [void]$script:QOT_ActionGroups.Remove($group)
    }

    $script:QOT_ActionGroups.Add([pscustomobject]@{
        Name     = $Name
        GetItems = $GetItems
    })

    try { Write-QLog ("Registered action group: {0}" -f $Name) "DEBUG" } catch { }
}

function Get-QOTActionGroups {
    if (-not $script:QOT_ActionGroups) {
        $script:QOT_ActionGroups = New-Object System.Collections.Generic.List[object]
    }

    return @($script:QOT_ActionGroups)
}

function Invoke-QOTRegisteredActions {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window
    )

    $selectedItems = New-Object System.Collections.Generic.List[object]

    foreach ($group in (Get-QOTActionGroups)) {
        $items = @()
        try {
            $items = @(& $group.GetItems $Window)
        }
        catch {
            try { Write-QLog ("Action group '{0}' failed to enumerate: {1}" -f $group.Name, $_.Exception.Message) "ERROR" } catch { }
            continue
        }

        foreach ($item in $items) {
            if (-not $item) { continue }

            $isSelected = $false
            if ($null -ne $item.PSObject.Properties["IsSelected"]) {
                $check = $item.IsSelected
                if ($check -is [scriptblock]) {
                    try {
                        $isSelected = & $check $Window
                    }
                    catch {
                        try { Write-QLog ("Selection check failed for '{0}': {1}" -f $item.Label, $_.Exception.Message) "WARN" } catch { }
                    }
                } else {
                    $isSelected = [bool]$check
                }
            }

            if ($isSelected) {
                $selectedItems.Add([pscustomobject]@{
                    Group = $group.Name
                    Item  = $item
                })
            }
        }
    }

    if ($selectedItems.Count -eq 0) {
        try { Write-QLog "No actions selected." "INFO" } catch { }
        return
    }

    foreach ($entry in $selectedItems) {
        $item = $entry.Item
        $label = $item.Label
        $executor = $item.Execute
        if ($executor -is [scriptblock]) {
            try {
                & $executor $Window
            }
            catch {
                try { Write-QLog ("Action failed ({0}): {1}" -f $label, $_.Exception.Message) "ERROR" } catch { }
            }
        }
    }
}

Export-ModuleMember -Function Clear-QOTActionGroups, Register-QOTActionGroup, Get-QOTActionGroups, Invoke-QOTRegisteredActions
