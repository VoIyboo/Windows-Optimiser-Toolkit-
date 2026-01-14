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
        [string]$Context,
        [switch]$IgnoreTypeMismatch
    )

    try {
        $paramCount = 0
        $firstParam = $null
        $firstParamType = $null
        try {
            if ($Script.Ast -and $Script.Ast.ParamBlock) {
                $paramCount = $Script.Ast.ParamBlock.Parameters.Count
                if ($paramCount -gt 0) {
                    $firstParam = $Script.Ast.ParamBlock.Parameters[0]
                    try { $firstParamType = $firstParam.StaticType } catch { $firstParamType = $null }
                }
            }
        } catch { $paramCount = 0 }

        $shouldPassWindow = $false
        if ($paramCount -eq 1 -and $null -ne $Window) {
            if (-not $firstParamType -or $firstParamType -eq [object]) {
                $shouldPassWindow = $true
            }
            elseif ($Window -is $firstParamType) {
                $shouldPassWindow = $true
            }
        }

        if ($shouldPassWindow) {
            return & $Script $Window
        }

        return & $Script
    }
    catch {
        if ($_.Exception -and $_.Exception.Message -match "Argument types do not match|Cannot process argument transformation|A positional parameter cannot be found") {
            try {
                return & $Script
            }
            catch {
                if ($IgnoreTypeMismatch) {
                    if ($Context) {
                        try { Write-QLog ("{0} skipped due to parameter mismatch: {1}" -f $Context, $_.Exception.Message) "WARN" } catch { }
                    }
                    return $null
                }
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
 $selectedItems = Get-QOTSelectedActions -Window $Window

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
        $label = $null
        $executor = $null
        try { $label = $item.Label } catch { $label = "Unknown action" }
        try { $executor = $item.Execute } catch { $executor = $null }
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

function Get-QOTSelectedActions {
    param(
        [Parameter(Mandatory)]$Window
    )



    $selectedItems = New-Object System.Collections.Generic.List[object]

    foreach ($group in (Get-QOTActionGroups)) {
        $items = @()
        try {
            if ($group.GetItems -is [scriptblock]) {
                $items = @(Invoke-QOTScriptBlockSafely -Script $group.GetItems -Window $Window -Context ("Action group '{0}'" -f $group.Name) -IgnoreTypeMismatch)
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
                $check = $null
                try {
                    $check = $item.IsSelected
                }
                catch {
                    try { Write-QLog ("Selection value for '{0}' could not be read: {1}" -f $item.Label, $_.Exception.Message) "WARN" } catch { }
                    $check = $null
                }
                if ($check -is [scriptblock]) {
                    try {
                        $isSelected = Invoke-QOTScriptBlockSafely -Script $check -Window $Window -Context ("Selection check for '{0}'" -f $item.Label)
                        try {
                            $isSelected = [System.Management.Automation.LanguagePrimitives]::IsTrue($isSelected)
                        }
                        catch {
                            $isSelected = $false
                            try { Write-QLog ("Selection check result for '{0}' could not be evaluated: {1}" -f $item.Label, $_.Exception.Message) "WARN" } catch { }
                        }
                    }
                    catch {
                        try { Write-QLog ("Selection check failed for '{0}': {1}" -f $item.Label, $_.Exception.Message) "WARN" } catch { }
                    }
                } else {
                    try {
                        $isSelected = [System.Management.Automation.LanguagePrimitives]::IsTrue($check)
                    }
                    catch {
                        $isSelected = $false
                        try { Write-QLog ("Selection value for '{0}' could not be evaluated: {1}" -f $item.Label, $_.Exception.Message) "WARN" } catch { }
                    }
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

    return $selectedItems
}

function Test-QOTAnyActionsSelected {
    param(
        [Parameter(Mandatory)]$Window
    )

    try {
        $selected = Get-QOTSelectedActions -Window $Window
        return ($selected.Count -gt 0)
    }
    catch {
        try { Write-QLog ("Failed to evaluate selected actions: {0}" -f $_.Exception.Message) "WARN" } catch { }
        $ex = $_.Exception
        $msg = $ex.Message
        $type = $ex.GetType().FullName

        $stack = ""
        try { $stack = $_.ScriptStackTrace } catch { }

        Write-QLog ("Failed to evaluate selected actions: {0}" -f $msg) "WARN"
        Write-QLog ("Exception type: {0}" -f $type) "WARN"
        if ($stack) { Write-QLog ("Stack: {0}" -f $stack) "WARN" }
        return $false
    }
}

Export-ModuleMember -Function Clear-QOTActionGroups, Register-QOTActionGroup, Get-QOTActionGroups, Invoke-QOTRegisteredActions, Get-QOTSelectedActions, Test-QOTAnyActionsSelected
