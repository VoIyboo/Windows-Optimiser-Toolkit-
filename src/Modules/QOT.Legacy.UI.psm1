function Start-QOTLegacy {
    param(
        [string]$RootPath
    )

    # ------------------------------
    # Admin check and assemblies
    # ------------------------------
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("Please run this script as Administrator.", "Quinn Optimiser Toolkit", 'OK', 'Error') | Out-Null
        return
    }

    Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

    # ------------------------------
    # Logging
    # ------------------------------
    $Global:ToolkitRoot  = "C:\IT"
    if (-not (Test-Path $Global:ToolkitRoot)) { New-Item -Path $Global:ToolkitRoot -ItemType Directory -Force | Out-Null }
    $Global:LogFile      = Join-Path $Global:ToolkitRoot "QuinnOptimiserToolkit.log"

    function Write-Log {
        param([string]$Message, [string]$Level = "INFO")
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $Global:LogFile -Value ("[{0}] [{1}] {2}" -f $timestamp, $Level, $Message)
    }

    Write-Log "===== Quinn Optimiser Toolkit (WPF) started ====="

    # ------------------------------
    # Import other modules
    # ------------------------------
    $srcRoot = Join-Path $RootPath "src"

    Import-Module (Join-Path $srcRoot "Modules\QOT.Actions.Clean.psm1")    -Force
    Import-Module (Join-Path $srcRoot "Modules\QOT.Actions.Tweaks.psm1")   -Force
    Import-Module (Join-Path $srcRoot "Modules\QOT.Actions.Advanced.psm1") -Force
    Import-Module (Join-Path $srcRoot "Modules\QOT.Apps.psm1")             -Force

    # ------------------------------
    # System summary
    # ------------------------------
    function Get-SystemSummaryText {
        $drive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
        if (-not $drive) { return "C drive: not found" }

        $totalBytes = $drive.Used + $drive.Free
        if ($totalBytes -le 0) {
            return "C: capacity could not be calculated"
        }

        $usedGB  = [math]::Round($drive.Used  / 1GB, 1)
        $freeGB  = [math]::Round($drive.Free  / 1GB, 1)
        $totalGB = [math]::Round($totalBytes  / 1GB, 1)
        $freePct = [math]::Round(($drive.Free / $totalBytes) * 100, 1)

        "C: {0} GB used / {1} GB free ({2} GB total, {3}% free)" -f $usedGB, $freeGB, $totalGB, $freePct
    }

    # ------------------------------
    # Load XAML from external file
    # ------------------------------
    $xamlPath = Join-Path (Join-Path $RootPath "src\Legacy") "QuinnOptimiserToolkit-v2.7.xaml"
    $xaml     = Get-Content $xamlPath -Raw

    $window = [Windows.Markup.XamlReader]::Parse($xaml)

    # From here down:
    #   - controls lookup ($StatusLabel, $RunButton, etc)
    #   - Set-Status function
    #   - collections setup
    #   - ModeCombo SelectionChanged
    #   - Apps tab behaviour (Refresh-InstalledApps, button click handlers, Install grid handler)
    #   - Run button logic
    #   - ShowDialog / closing log

    # 👉 Take all of those blocks from your current v2.7 file
    #    and paste them inside this function, *after* $window is created.

    # Example tail:
    # $null = $window.ShowDialog()
    # Write-Log "===== Quinn Optimiser Toolkit closed ====="
}
