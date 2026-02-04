# src\UI\HelpWindow.UI.psm1
# Help window UI for the Quinn Optimiser Toolkit

$ErrorActionPreference = "Stop"

$script:QOTHelp_AssembliesLoaded = $false

function Initialize-QOTHelpUIAssemblies {
    if ($script:QOTHelp_AssembliesLoaded) { return }
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    $script:QOTHelp_AssembliesLoaded = $true
}

function Get-QOTHelpSections {
    return @(
        [pscustomobject]@{
            Title = "How Quinn Optimiser Toolkit works"
            Body  = "Quinn Optimiser Toolkit groups maintenance tasks into tabs such as Tweaks & Cleaning, Apps, and Advanced. Each section presents selectable tasks so you can build a custom run list for the current machine."
        }
        [pscustomobject]@{
            Title = "Checkboxes map directly to actions"
            Body  = "Each checkbox represents a specific action in the toolkit. Selecting a checkbox queues that action, and clearing it removes the action from the run list. You can mix actions across tabs - every checked item is included."
        }
        [pscustomobject]@{
            Title = 'What "Run selected actions" does'
            Body  = "The Run selected actions button executes every checked item in sequence. It only runs what is selected at the time you click the button and leaves unchecked actions untouched."
        }
        [pscustomobject]@{
            Title = "Important safety notes"
            Body  = "* Review selections before running any actions.`n* Close important apps to avoid file locks or conflicts.`n* Some actions change system settings - use a maintenance window when possible.`n* If you are unsure about an action, leave it unchecked and review it first."
        }
    )
}

function Show-QOTHelpWindow {
    param(
        [System.Windows.Window]$Owner
    )

    Initialize-QOTHelpUIAssemblies

    $xamlPath = Join-Path $PSScriptRoot "HelpWindow.xaml"
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "HelpWindow.xaml not found at $xamlPath"
    }

    $xaml   = Get-Content -LiteralPath $xamlPath -Raw
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    if (-not $window) {
        throw "Failed to load HelpWindow.xaml"
    }

    if ($Owner) {
        $window.Owner = $Owner
    }

    $sectionsControl = $window.FindName("HelpSections")
    if ($sectionsControl) {
        $sectionsControl.ItemsSource = (Get-QOTHelpSections)
    }

    $window.ShowDialog() | Out-Null
}

Export-ModuleMember -Function Show-QOTHelpWindow
