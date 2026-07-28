# WinMole - Logging Module
# Provides consistent logging functions with colors and icons

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Prevent multiple sourcing
if ((Get-Variable -Name 'WINMOLE_LOG_LOADED' -Scope Script -ErrorAction SilentlyContinue) -and $script:WINMOLE_LOG_LOADED) { return }
$script:WINMOLE_LOG_LOADED = $true

# Import base module
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\base.ps1"

# Fallbacks in case base.ps1 did not initialize icons/colors in this scope
if (-not ($script:Icons -is [hashtable])) {
    $script:Icons = @{}
}

$iconDefaults = @{
    List    = "*"
    Success = "+"
    Warning = "!"
    Error   = "x"
    DryRun  = ">"
    Arrow   = ">"
}

foreach ($key in $iconDefaults.Keys) {
    if (-not $script:Icons.ContainsKey($key)) {
        $script:Icons[$key] = $iconDefaults[$key]
    }
}

if (-not ($script:Colors -is [hashtable])) {
    $script:Colors = @{}
}

$colorDefaults = @{
    Cyan       = ""
    Green      = ""
    Yellow     = ""
    Red        = ""
    Gray       = ""
    PurpleBold = ""
    NC         = ""
}

foreach ($key in $colorDefaults.Keys) {
    if (-not $script:Colors.ContainsKey($key)) {
        $script:Colors[$key] = $colorDefaults[$key]
    }
}

# ============================================================================
# Log Configuration
# ============================================================================

$script:LogConfig = @{
    DebugEnabled = $env:WINMOLE_DEBUG -eq "1"
    LogFile      = $null
    Verbose      = $false
}

# ============================================================================
# Core Logging Functions
# ============================================================================

function Write-LogMessage {
    <#
    .SYNOPSIS
        Internal function to write formatted log message
    #>
    param(
        [string]$Message,
        [string]$Level,
        [string]$Color,
        [string]$Icon
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $colorCode = $script:Colors[$Color]
    $nc = $script:Colors.NC
    
    $formattedIcon = if ($Icon) { "$Icon " } else { "" }
    $output = "  ${colorCode}${formattedIcon}${nc}${Message}"
    
    Write-Host $output
    
    # Also write to log file if configured
    if ($script:LogConfig.LogFile) {
        "$timestamp [$Level] $Message" | Out-File -Append -FilePath $script:LogConfig.LogFile -Encoding UTF8
    }
}

function Write-Info {
    <#
    .SYNOPSIS
        Write an informational message
    #>
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "INFO" -Color "Cyan" -Icon $script:Icons.List
}

function Write-Success {
    <#
    .SYNOPSIS
        Write a success message
    #>
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "SUCCESS" -Color "Green" -Icon $script:Icons.Success
}

function Write-WinMoleWarning {
    <#
    .SYNOPSIS
        Write a warning message (named to avoid conflict with built-in Write-Warning cmdlet)
    #>
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "WARN" -Color "Yellow" -Icon $script:Icons.Warning
}

function Write-WinMoleError {
    <#
    .SYNOPSIS
        Write an error message (named to avoid conflict with built-in Write-Error cmdlet)
    #>
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "ERROR" -Color "Red" -Icon $script:Icons.Error
}

function Write-Debug {
    <#
    .SYNOPSIS
        Write a debug message (only if debug mode is enabled)
    #>
    param([string]$Message)
    
    if ($script:LogConfig.DebugEnabled) {
        $gray = $script:Colors.Gray
        $nc = $script:Colors.NC
        Write-Host "  ${gray}[DEBUG] $Message${nc}"
    }
}

function Write-DryRun {
    <#
    .SYNOPSIS
        Write a dry-run message (action that would be taken)
    #>
    param([string]$Message)
    Write-LogMessage -Message $Message -Level "DRYRUN" -Color "Yellow" -Icon $script:Icons.DryRun
}

# ============================================================================
# Section Functions (for progress indication)
# ============================================================================

$script:CurrentSection = @{
    Active   = $false
    Activity = $false
    Name     = ""
}

function Start-Section {
    <#
    .SYNOPSIS
        Start a new section with a title
    #>
    param([string]$Title)
    
    $script:CurrentSection.Active = $true
    $script:CurrentSection.Activity = $false
    $script:CurrentSection.Name = $Title
    
    $purple = $script:Colors.PurpleBold
    $nc = $script:Colors.NC
    $arrow = $script:Icons.Arrow
    
    Write-Host ""
    Write-Host "${purple}${arrow} ${Title}${nc}"
}

function Stop-Section {
    <#
    .SYNOPSIS
        End the current section
    #>
    if ($script:CurrentSection.Active -and -not $script:CurrentSection.Activity) {
        Write-Success "Nothing to tidy"
    }
    $script:CurrentSection.Active = $false
}

function Set-SectionActivity {
    <#
    .SYNOPSIS
        Mark that activity occurred in current section
    #>
    if ($script:CurrentSection.Active) {
        $script:CurrentSection.Activity = $true
    }
}

# ============================================================================
# Progress Spinner
# ============================================================================

$script:SpinnerFrames = @('|', '/', '-', '\')
$script:SpinnerIndex = 0
$script:SpinnerJob = $null

function Start-Spinner {
    <#
    .SYNOPSIS
        Start an inline spinner with message
    #>
    param([string]$Message = "Working...")
    
    $script:SpinnerIndex = 0
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    Write-Host -NoNewline "  ${gray}$($script:SpinnerFrames[0]) $Message${nc}"
}

function Update-Spinner {
    <#
    .SYNOPSIS
        Update the spinner animation
    #>
    param([string]$Message)
    
    $script:SpinnerIndex = ($script:SpinnerIndex + 1) % $script:SpinnerFrames.Count
    $frame = $script:SpinnerFrames[$script:SpinnerIndex]
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    # Move cursor to beginning of line and clear
    Write-Host -NoNewline "`r  ${gray}$frame $Message${nc}    "
}

function Stop-Spinner {
    <#
    .SYNOPSIS
        Stop the spinner and clear the line
    #>
    Write-Host -NoNewline "`r                                                            `r"
}

# ============================================================================
# Progress Bar
# ============================================================================

# Deliberately NOT named Write-Progress. Functions outrank cmdlets in PowerShell
# command resolution, so a function by that name silently shadows the built-in
# cmdlet for every script that dot-sources this file. Callers passing the
# cmdlet's parameters (-Activity/-Status/-PercentComplete) then bound here
# instead, and because the function was not an advanced function those arguments
# were absorbed into $args and discarded, leaving the bar frozen at 0%.
function Write-ProgressBar {
    <#
    .SYNOPSIS
        Write an inline progress bar
    .PARAMETER Current
        Items completed so far.
    .PARAMETER Total
        Total items expected. Values below 1 render as 0%.
    #>
    [CmdletBinding()]
    param(
        [int]$Current,
        [int]$Total,
        [string]$Message = "",
        [int]$Width = 30
    )

    $percent = if ($Total -gt 0) { [Math]::Round(($Current / $Total) * 100) } else { 0 }

    # Clamp before building the bar: "=" * -1 throws, and $Current can exceed
    # $Total when a caller discovers more items partway through a scan.
    $filled = [Math]::Round(($Width * $Current) / [Math]::Max($Total, 1))
    if ($filled -lt 0) { $filled = 0 }
    if ($filled -gt $Width) { $filled = $Width }
    $empty = $Width - $filled

    $bar = ("[" + ("=" * $filled) + (" " * $empty) + "]")
    $cyan = $script:Colors.Cyan
    $nc = $script:Colors.NC

    Write-Host -NoNewline "`r  ${cyan}$bar${nc} ${percent}% $Message    "
}

function Complete-Progress {
    <#
    .SYNOPSIS
        Clear the progress bar line
    #>
    # The parentheses are required. Without them PowerShell parses this in
    # argument mode and passes "`r", "+", the spaces, "+", "`r" as five separate
    # arguments, printing literal plus signs instead of clearing the line.
    Write-Host -NoNewline ("`r" + (" " * 80) + "`r")
}

# ============================================================================
# Log File Management
# ============================================================================

function Set-LogFile {
    <#
    .SYNOPSIS
        Set a log file for persistent logging
    #>
    param([string]$Path)
    
    $script:LogConfig.LogFile = $Path
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Enable-DebugMode {
    <#
    .SYNOPSIS
        Enable debug logging
    #>
    $script:LogConfig.DebugEnabled = $true
}

function Disable-DebugMode {
    <#
    .SYNOPSIS
        Disable debug logging
    #>
    $script:LogConfig.DebugEnabled = $false
}

# ============================================================================
# Exports (functions are available via dot-sourcing)
# ============================================================================
# Functions: Write-Info, Write-Success, Write-WinMoleWarning, Write-WinMoleError, etc.
