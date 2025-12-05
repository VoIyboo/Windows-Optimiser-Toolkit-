# ------------------------------
# App scan and risk logic
# ------------------------------
$Global:AppWhitelistPatterns = @(
    ...
)

function Get-InstalledApps { ... }

function Get-AppRisk { ... }

# ------------------------------
# Install apps (winget) helpers
# ------------------------------
function Test-AppInstalledWinget { ... }

function Install-AppWithWinget { ... }

function Initialise-InstallAppsList { ... }

function Install-SelectedCommonApps { ... }

Export-ModuleMember -Variable AppWhitelistPatterns -Function `
    Get-InstalledApps, `
    Get-AppRisk, `
    Test-AppInstalledWinget, `
    Install-AppWithWinget, `
    Initialise-InstallAppsList, `
    Install-SelectedCommonApps
