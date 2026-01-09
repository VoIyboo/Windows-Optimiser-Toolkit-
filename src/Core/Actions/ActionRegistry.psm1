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

function Invoke-QOTScriptBlockSafely {
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [object]$Window,
        [string]$Context
    )

    try {
        return & $Script $Window
    }
    catch {
        if ($_.Exception -and $_.Exception.Message -match "Argument types do not match") {
            try {
                return & $Script
            }
            catch {
                if ($Context) {
                    try { Write-QLog ("{0} failed without Window param: {1}" -f $Context, $_.Exception.Message) "ERROR" } catch { }
                }
                throw
            }
        }

        if ($Context) {
            try { Write-QLog ("{0} failed: {1}" -f $Context, $_.Exception.Message) "ERROR" } catch { }
        }
        throw
    }
}


function Invoke-QOTRegisteredActions {
    param(
        [Parameter(Mandatory)]$Window
    )

    $selectedItems = New-Object System.Collections.Generic.List[object]

    foreach ($group in (Get-QOTActionGroups)) {
        $items = @()
        try {
            if ($group.GetItems -is [scriptblock]) {
                $items = @(Invoke-QOTScriptBlockSafely -Script $group.GetItems -Window $Window -Context ("Action group '{0}'" -f $group.Name))
            }
        }
        catch {
            try { Write-QLog ("Action group '{0}' failed to enumerate: {1}" -f $group.Name, $_.Exception.Message) "ERROR" } catch { }
            continue
        }

        if ($items.Count -gt 0) {
            $firstItemType = $null
            try { $firstItemType = $items[0].GetType().FullName } catch { $firstItemType = "unknown" }
            try {
                Write-QLog ("Action group '{0}' returned {1} items (collection type: {2}, first item type: {3})." -f $group.Name, $items.Count, $items.GetType().FullName, $firstItemType) "DEBUG"
            } catch { }
        }

        foreach ($item in $items) {
            if (-not $item) { continue }


            if ($item -is [hashtable]) {
                $item = [pscustomobject]$item
            }

            $isSelected = $false
            if ($null -ne $item.PSObject.Properties["IsSelected"]) {
                $check = $item.IsSelected
                if ($check -is [scriptblock]) {
                    try {
                        $isSelected = Invoke-QOTScriptBlockSafely -Script $check -Window $Window -Context ("Selection check for '{0}'" -f $item.Label)
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

    try { Write-QLog ("Selected actions collection type: {0}" -f $selectedItems.GetType().FullName) "DEBUG" } catch { }
    if ($selectedItems -is [System.Collections.IEnumerable]) {
        $firstSelected = $selectedItems | Select-Object -First 1
        if ($firstSelected) {
            try { Write-QLog ("First selected entry type: {0}" -f $firstSelected.GetType().FullName) "DEBUG" } catch { }
            try { Write-QLog ("First selected entry value: {0}" -f (($firstSelected | Out-String).Trim())) "DEBUG" } catch { }
        }
    }

    foreach ($entry in $selectedItems) {
        $item = $entry.Item
        $label = $item.Label
        $executor = $item.Execute
        if ($executor -is [scriptblock]) {
            try {
                Invoke-QOTScriptBlockSafely -Script $executor -Window $Window -Context ("Action '{0}'" -f $label)
            }
            catch {
                try { Write-QLog ("Action failed ({0}): {1}" -f $label, $_.Exception.Message) "ERROR" } catch { }
            }
        }
    }
}

Export-ModuleMember -Function Clear-QOTActionGroups, Register-QOTActionGroup, Get-QOTActionGroups, Invoke-QOTRegisteredActions
