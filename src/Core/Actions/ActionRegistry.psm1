# src\Core\Actions\ActionRegistry.psm1
# Central registry for Run selected actions

$ErrorActionPreference = "Stop"

Import-Module "$PSScriptRoot\..\Logging\Logging.psm1" -Force -ErrorAction SilentlyContinue

$script:QOT_ActionGroups = New-Object System.Collections.Generic.List[object]
$script:QOT_ActionDefinitions = @{}

function Initialize-QOTActionGroups {
    if (-not $script:QOT_ActionGroups -or -not ($script:QOT_ActionGroups -is [System.Collections.Generic.List[object]])) {
        $script:QOT_ActionGroups = New-Object System.Collections.Generic.List[object]
    }
}

function Clear-QOTActionDefinitions {
    $script:QOT_ActionDefinitions = @{}
}

function Register-QOTActionDefinition {
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$ScriptPath
    )

    if (-not $script:QOT_ActionDefinitions -or -not ($script:QOT_ActionDefinitions -is [hashtable])) {
        $script:QOT_ActionDefinitions = @{}
    }

    $script:QOT_ActionDefinitions[$ActionId] = [pscustomobject]@{
        ActionId = $ActionId
        Label    = $Label
        ScriptPath  = $ScriptPath
    }

    try { Write-QLog ("Registered action definition: {0} -> {1}" -f $ActionId, $ScriptPath) "DEBUG" } catch { }
}

function Get-QOTActionDefinition {
    param(
        [Parameter(Mandatory)][string]$ActionId
    )

    if (-not $script:QOT_ActionDefinitions -or -not ($script:QOT_ActionDefinitions -is [hashtable])) {
        $script:QOT_ActionDefinitions = @{}
    }

    if ($script:QOT_ActionDefinitions.ContainsKey($ActionId)) {
        return $script:QOT_ActionDefinitions[$ActionId]
    }

    return $null
}

function Invoke-QOTActionById {
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)]$Window
    )

    $definition = Get-QOTActionDefinition -ActionId $ActionId
    if (-not $definition) {
        try { Write-QLog ("Action definition not found for ActionId '{0}'." -f $ActionId) "WARN" } catch { }
        return $false
    }

    $label = $definition.Label
    $scriptPath = $definition.ScriptPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) {
        try { Write-QLog ("Action definition missing script path for '{0}'." -f $ActionId) "WARN" } catch { }
        return $false
    }
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        try { Write-QLog ("Script path not found for '{0}': {1}" -f $ActionId, $scriptPath) "ERROR" } catch { }
        Write-QOTActionConsoleLog -ActionId $ActionId -Status "ERROR" -Message "Script not found."
        return $false
    }

    Write-QOTActionConsoleLog -ActionId $ActionId -Status "START" -Message $label
    try { Write-QLog ("Running action: {0} ({1})" -f $label, $ActionId) "INFO" } catch { }
    try {
        & $scriptPath -Window $Window
        try { Write-QLog ("Action complete: {0} ({1})" -f $label, $ActionId) "INFO" } catch { }
        Write-QOTActionConsoleLog -ActionId $ActionId -Status "SUCCESS" -Message $label
        return $true
    }
    catch {
        try { Write-QLog ("Action failed ({0}): {1}" -f $label, $_.Exception.Message) "ERROR" } catch { }
        Write-QOTActionConsoleLog -ActionId $ActionId -Status "ERROR" -Message $_.Exception.Message
        return $false
    }
}

function Write-QOTActionConsoleLog {
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)][string]$Status,
        [string]$Message
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[{0}] [{1}] {2}" -f $timestamp, $ActionId, $Status
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $entry = "{0} - {1}" -f $entry, $Message
    }
    try { Write-Host $entry } catch { }
}

function Clear-QOTActionGroups {
    $script:QOT_ActionGroups = New-Object System.Collections.Generic.List[object]
}

function Register-QOTActionGroup {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$GetItems
    )

    Initialize-QOTActionGroups

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
    Initialize-QOTActionGroups
    try {
        return $script:QOT_ActionGroups.ToArray()
    }
    catch {
        Initialize-QOTActionGroups
        return @()
    }
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
        [Parameter(Mandatory)]$Window,
        [scriptblock]$OnProgress
    )
    $selectedItems = Get-QOTSelectedActionsInExecutionOrder -Window $Window

    if ($selectedItems.Count -eq 0) {
        try { Write-QLog "No actions selected." "INFO" } catch { }
        return [pscustomobject]@{ Success = $true; Executed = 0; FailedActionId = $null; ErrorMessage = $null }
    }
    
    $actionIds = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $selectedItems) {
        $item = $entry.Item
        $actionId = $null
        try { $actionId = $item.ActionId } catch { $actionId = $null }
        if ([string]::IsNullOrWhiteSpace($actionId)) {
            try { $actionId = $item.Id } catch { $actionId = $null }
        }
        if (-not [string]::IsNullOrWhiteSpace($actionId)) {
            $actionIds.Add($actionId)
        } else {
            try { Write-QLog ("Skipping selected entry in group '{0}' because ActionId is missing." -f $entry.Group) "WARN" } catch { }
        }
    }

    if ($actionIds.Count -eq 0) {
        try { Write-QLog "No valid ActionIds found for selected actions." "WARN" } catch { }
        return [pscustomobject]@{ Success = $false; Executed = 0; FailedActionId = $null; ErrorMessage = "No valid actions selected." }
    }

    try { Write-QLog ("Executing ActionIds: {0}" -f ($actionIds -join ", ")) "DEBUG" } catch { }
    $executed = 0
    for ($i = 0; $i -lt $actionIds.Count; $i++) {
        $actionId = $actionIds[$i]

        if ($OnProgress) {
            try { & $OnProgress ($i + 1) $actionIds.Count $actionId } catch { }
        }

        $ok = Invoke-QOTActionById -ActionId $actionId -Window $Window
        if (-not $ok) {
            return [pscustomobject]@{ Success = $false; Executed = $executed; FailedActionId = $actionId; ErrorMessage = "Action failed." }
        }

        $executed++
    }

    return [pscustomobject]@{ Success = $true; Executed = $executed; FailedActionId = $null; ErrorMessage = $null }
}

function Get-QOTSelectedActionsInExecutionOrder {
    param(
        [Parameter(Mandatory)]$Window
    )

    $selectedItems = @(Get-QOTSelectedActions -Window $Window)
    if ($selectedItems.Count -eq 0) { return $selectedItems }

    $groupOrder = @{
        "Tweaks & Cleaning" = 1
        "Apps" = 2
        "Advanced" = 3
    }

    $ordered = $selectedItems | Sort-Object @{ Expression = {
        if ($groupOrder.ContainsKey($_.Group)) { $groupOrder[$_.Group] } else { 999 }
    } }, @{ Expression = { $_.Group } }

    return @($ordered)
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
                $actionId = $null
                try { $actionId = $item.ActionId } catch { $actionId = $null }
                if ([string]::IsNullOrWhiteSpace($actionId)) {
                    try { $actionId = $item.Id } catch { $actionId = $null }
                }
                $selectedItems.Add([pscustomobject]@{
                    Group    = $group.Name
                    ActionId = $actionId
                    Item     = $item
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

Export-ModuleMember -Function Clear-QOTActionGroups, Clear-QOTActionDefinitions, Register-QOTActionDefinition, Get-QOTActionDefinition, Invoke-QOTActionById, Register-QOTActionGroup, Get-QOTActionGroups, Invoke-QOTRegisteredActions, Get-QOTSelectedActions, Get-QOTSelectedActionsInExecutionOrder, Test-QOTAnyActionsSelected
