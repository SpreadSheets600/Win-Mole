# WinMole - UI Module
# Provides interactive UI components (menus, confirmations, etc.)

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Prevent multiple sourcing
if ((Get-Variable -Name 'WINMOLE_UI_LOADED' -Scope Script -ErrorAction SilentlyContinue) -and $script:WINMOLE_UI_LOADED) { return }
$script:WINMOLE_UI_LOADED = $true

# Import dependencies
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\base.ps1"
. "$scriptDir\log.ps1"

# ============================================================================
# Terminal Utilities
# ============================================================================

function Get-TerminalSize {
    <#
    .SYNOPSIS
        Get terminal width and height
    #>
    try {
        return @{
            Width  = $Host.UI.RawUI.WindowSize.Width
            Height = $Host.UI.RawUI.WindowSize.Height
        }
    }
    catch {
        return @{ Width = 80; Height = 24 }
    }
}

function Clear-Line {
    <#
    .SYNOPSIS
        Clear the current line
    #>
    $width = (Get-TerminalSize).Width
    Write-Host -NoNewline ("`r" + (" " * ($width - 1)) + "`r")
}

function Move-CursorUp {
    <#
    .SYNOPSIS
        Move cursor up N lines
    #>
    param([int]$Lines = 1)
    Write-Host -NoNewline "$([char]27)[$Lines`A"
}

function Move-CursorDown {
    <#
    .SYNOPSIS
        Move cursor down N lines
    #>
    param([int]$Lines = 1)
    Write-Host -NoNewline "$([char]27)[$Lines`B"
}

function Write-MenuFrame {
    <#
    .SYNOPSIS
        Render a frame of an interactive menu in place
    .DESCRIPTION
        Writes the given lines as a single buffered block. When PreviousLineCount
        is greater than zero, the cursor is first moved back to the start of the
        previous frame and everything below is cleared, so the new frame
        overwrites the old one instead of stacking below it. This avoids
        Clear-Host, which is a no-op in some terminal hosts and causes
        full-screen flicker in the rest.
    .PARAMETER Lines
        The lines making up the frame
    .PARAMETER PreviousLineCount
        Number of lines the previous frame occupied (0 for the first frame)
    .OUTPUTS
        [int] The number of lines rendered; pass it back on the next call
    #>
    param(
        [array]$Lines = @(),
        [int]$PreviousLineCount = 0
    )

    $esc = [char]27
    $sb = [System.Text.StringBuilder]::new()

    if ($PreviousLineCount -gt 0) {
        # Cursor to start of the previous frame's first line, then clear to end of screen
        [void]$sb.Append("$esc[${PreviousLineCount}F$esc[0J")
    }

    foreach ($line in $Lines) {
        [void]$sb.Append([string]$line).Append("`n")
    }

    Write-Host -NoNewline $sb.ToString()
    return @($Lines).Count
}

# ============================================================================
# Confirmation Dialogs
# ============================================================================

function Read-Confirmation {
    <#
    .SYNOPSIS
        Ask for yes/no confirmation
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        
        [bool]$Default = $false
    )
    
    $cyan = $script:Colors.Cyan
    $nc = $script:Colors.NC
    $hint = if ($Default) { "[Y/n]" } else { "[y/N]" }
    
    Write-Host -NoNewline "  ${cyan}$($script:Icons.Confirm)${nc} $Prompt $hint "
    
    $response = Read-Host
    
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }
    
    return $response -match '^[Yy]'
}

function Read-ConfirmationDestructive {
    <#
    .SYNOPSIS
        Ask for confirmation on destructive operations (requires typing 'yes')
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        
        [string]$ConfirmText = "yes"
    )
    
    $red = $script:Colors.Red
    $nc = $script:Colors.NC
    
    Write-Host ""
    Write-Host "  ${red}$($script:Icons.Warning) WARNING: $Prompt${nc}"
    Write-Host "  Type '$ConfirmText' to confirm: " -NoNewline
    
    $response = Read-Host
    return $response -eq $ConfirmText
}

# ============================================================================
# Menu Components
# ============================================================================

function Show-Menu {
    <#
    .SYNOPSIS
        Display an interactive menu and return selected option
    .PARAMETER Title
        Menu title
    .PARAMETER Options
        Array of menu options (hashtables with Name and optionally Description, Action)
    .PARAMETER AllowBack
        Show back/exit option
    #>
    param(
        [string]$Title = "Menu",
        
        [Parameter(Mandatory)]
        [array]$Options,
        
        [switch]$AllowBack
    )
    
    $selected = 0
    $maxIndex = $Options.Count - 1
    
    # Add back option if allowed
    if ($AllowBack) {
        $Options = $Options + @{ Name = "Back"; Description = "Return to previous menu" }
        $maxIndex++
    }
    
    $purple = $script:Colors.PurpleBold
    $cyan = $script:Colors.Cyan
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    # Hide cursor
    Write-Host -NoNewline "$([char]27)[?25l"

    $frameLines = 0

    try {
        while ($true) {
            # Build the frame and render it in place over the previous one
            $lines = @(
                ""
                "  ${purple}$($script:Icons.Arrow) $Title${nc}"
                ""
            )

            for ($i = 0; $i -le $maxIndex; $i++) {
                $option = $Options[$i]
                $name = if ($option -is [hashtable]) { $option.Name } else { $option.ToString() }
                $desc = if ($option -is [hashtable] -and $option.Description) { " - $($option.Description)" } else { "" }

                if ($i -eq $selected) {
                    $lines += "  ${cyan}> $name${nc}${gray}$desc${nc}"
                }
                else {
                    $lines += "    $name${gray}$desc${nc}"
                }
            }

            $lines += ""
            $lines += "  ${gray}Use arrows or j/k to navigate, Enter to select, q to quit${nc}"

            $frameLines = Write-MenuFrame -Lines $lines -PreviousLineCount $frameLines
            
            # Read key - handle both VirtualKeyCode and escape sequences
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            
            # Handle escape sequences for arrow keys (some terminals send these)
            $moved = $false
            if ($key.VirtualKeyCode -eq 0 -or $key.Character -eq [char]27) {
                # Escape sequence - read the next characters
                if ($Host.UI.RawUI.KeyAvailable) {
                    $key2 = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    if ($key2.Character -eq '[' -and $Host.UI.RawUI.KeyAvailable) {
                        $key3 = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        switch ($key3.Character) {
                            'A' { # Up arrow escape sequence
                                $selected = if ($selected -gt 0) { $selected - 1 } else { $maxIndex }
                                $moved = $true
                            }
                            'B' { # Down arrow escape sequence
                                $selected = if ($selected -lt $maxIndex) { $selected + 1 } else { 0 }
                                $moved = $true
                            }
                        }
                    }
                }
            }
            
            if (-not $moved) {
                switch ($key.VirtualKeyCode) {
                    38 { # Up arrow
                        $selected = if ($selected -gt 0) { $selected - 1 } else { $maxIndex }
                    }
                    40 { # Down arrow
                        $selected = if ($selected -lt $maxIndex) { $selected + 1 } else { 0 }
                    }
                    13 { # Enter
                        # Show cursor
                        Write-Host -NoNewline "$([char]27)[?25h"
                        
                        if ($AllowBack -and $selected -eq $maxIndex) {
                            return $null  # Back selected
                        }
                        return $Options[$selected]
                    }
                    default {
                        switch ($key.Character) {
                            'k' { $selected = if ($selected -gt 0) { $selected - 1 } else { $maxIndex } }
                            'j' { $selected = if ($selected -lt $maxIndex) { $selected + 1 } else { 0 } }
                            'q' { 
                                Write-Host -NoNewline "$([char]27)[?25h"
                                return $null 
                            }
                        }
                    }
                }
            }
        }
    }
    finally {
        # Ensure cursor is shown
        Write-Host -NoNewline "$([char]27)[?25h"
    }
}

function Show-SelectionList {
    <#
    .SYNOPSIS
        Display a multi-select list
    #>
    param(
        [string]$Title = "Select Items",
        
        [Parameter(Mandatory)]
        [array]$Items,
        
        [switch]$MultiSelect
    )
    
    $cursor = 0
    $selected = @{}
    $maxIndex = $Items.Count - 1
    
    $purple = $script:Colors.PurpleBold
    $cyan = $script:Colors.Cyan
    $green = $script:Colors.Green
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    Write-Host -NoNewline "$([char]27)[?25l"

    $frameLines = 0

    try {
        while ($true) {
            # Build the frame and render it in place over the previous one
            $lines = @(
                ""
                "  ${purple}$($script:Icons.Arrow) $Title${nc}"
            )
            if ($MultiSelect) {
                $lines += "  ${gray}Space to toggle, Enter to confirm${nc}"
            }
            $lines += ""

            for ($i = 0; $i -le $maxIndex; $i++) {
                $item = $Items[$i]
                $name = if ($item -is [hashtable]) { $item.Name } else { $item.ToString() }
                $check = if ($selected[$i]) { "$($script:Icons.Success)" } else { "$($script:Icons.Empty)" }

                if ($i -eq $cursor) {
                    $lines += "  ${cyan}> ${check} $name${nc}"
                }
                else {
                    $checkColor = if ($selected[$i]) { $green } else { $gray }
                    $lines += "    ${checkColor}${check}${nc} $name"
                }
            }

            $lines += ""
            $lines += "  ${gray}j/k or arrows to navigate, space to select, Enter to confirm, q to cancel${nc}"

            $frameLines = Write-MenuFrame -Lines $lines -PreviousLineCount $frameLines
            
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            
            # Handle escape sequences for arrow keys (some terminals send these)
            $moved = $false
            if ($key.VirtualKeyCode -eq 0 -or $key.Character -eq [char]27) {
                # Escape sequence - read the next characters
                if ($Host.UI.RawUI.KeyAvailable) {
                    $key2 = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    if ($key2.Character -eq '[' -and $Host.UI.RawUI.KeyAvailable) {
                        $key3 = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        switch ($key3.Character) {
                            'A' { # Up arrow escape sequence
                                $cursor = if ($cursor -gt 0) { $cursor - 1 } else { $maxIndex }
                                $moved = $true
                            }
                            'B' { # Down arrow escape sequence
                                $cursor = if ($cursor -lt $maxIndex) { $cursor + 1 } else { 0 }
                                $moved = $true
                            }
                        }
                    }
                }
            }
            
            if (-not $moved) {
                switch ($key.VirtualKeyCode) {
                    38 { $cursor = if ($cursor -gt 0) { $cursor - 1 } else { $maxIndex } }
                    40 { $cursor = if ($cursor -lt $maxIndex) { $cursor + 1 } else { 0 } }
                    32 { # Space
                        if ($MultiSelect) {
                            $selected[$cursor] = -not $selected[$cursor]
                        }
                        else {
                            $selected = @{ $cursor = $true }
                        }
                    }
                    13 { # Enter
                        Write-Host -NoNewline "$([char]27)[?25h"
                        $result = @()
                        foreach ($selKey in $selected.Keys) {
                            if ($selected[$selKey]) {
                                $result += $Items[$selKey]
                            }
                        }
                        return $result
                    }
                    default {
                        switch ($key.Character) {
                            'k' { $cursor = if ($cursor -gt 0) { $cursor - 1 } else { $maxIndex } }
                            'j' { $cursor = if ($cursor -lt $maxIndex) { $cursor + 1 } else { 0 } }
                            ' ' { 
                                if ($MultiSelect) {
                                    $selected[$cursor] = -not $selected[$cursor]
                                }
                                else {
                                    $selected = @{ $cursor = $true }
                                }
                            }
                            'q' {
                                Write-Host -NoNewline "$([char]27)[?25h"
                                return @()
                            }
                        }
                    }
                }
            }
        }
    }
    finally {
        Write-Host -NoNewline "$([char]27)[?25h"
    }
}

# ============================================================================
# Banner / Header
# ============================================================================

function Show-Banner {
    <#
    .SYNOPSIS
        Display the WinMole ASCII banner
    #>
    $purple = $script:Colors.Purple
    $cyan = $script:Colors.Cyan
    $nc = $script:Colors.NC
    
    $banner = @"

  ${purple}██╗    ██╗██╗███╗   ██╗${cyan}███╗   ███╗ ██████╗ ██╗     ███████╗${nc}
  ${purple}██║    ██║██║████╗  ██║${cyan}████╗ ████║██╔═══██╗██║     ██╔════╝${nc}
  ${purple}██║ █╗ ██║██║██╔██╗ ██║${cyan}██╔████╔██║██║   ██║██║     █████╗  ${nc}
  ${purple}██║███╗██║██║██║╚██╗██║${cyan}██║╚██╔╝██║██║   ██║██║     ██╔══╝  ${nc}
  ${purple}╚███╔███╔╝██║██║ ╚████║${cyan}██║ ╚═╝ ██║╚██████╔╝███████╗███████╗${nc}
  ${purple} ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝${cyan}╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚══════╝${nc}

"@
    
    Write-Host $banner
}

function Show-Header {
    <#
    .SYNOPSIS
        Display a section header
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        
        [string]$Subtitle = ""
    )
    
    $purple = $script:Colors.PurpleBold
    $gray = $script:Colors.Gray
    $nc = $script:Colors.NC
    
    Write-Host ""
    Write-Host "  ${purple}$Title${nc}"
    if ($Subtitle) {
        Write-Host "  ${gray}$Subtitle${nc}"
    }
    Write-Host ""
}

# ============================================================================
# Summary Display
# ============================================================================

function Show-Summary {
    <#
    .SYNOPSIS
        Display cleanup summary
    #>
    param(
        [long]$SizeBytes = 0,
        [int]$ItemCount = 0,
        [string]$Action = "Cleaned"
    )
    
    $green = $script:Colors.Green
    $cyan = $script:Colors.Cyan
    $nc = $script:Colors.NC
    
    $sizeHuman = Format-ByteSize -Bytes $SizeBytes
    
    Write-Host ""
    Write-Host "  $($green)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$($nc)"
    Write-Host "  $($green)$($script:Icons.Success)$($nc) $($Action): $($cyan)$($sizeHuman)$($nc) across $($cyan)$($ItemCount)$($nc) items"
    Write-Host "  $($green)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$($nc)"
    Write-Host ""
}

# ============================================================================
# Exports (functions are available via dot-sourcing)
# ============================================================================
# Functions: Show-Menu, Show-Banner, Read-Confirmation, etc.
