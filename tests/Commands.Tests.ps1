#!/usr/bin/env pwsh
# WinMole - command entry point tests and repo-wide script validation
# Run with: Invoke-Pester -Path .\tests\

#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    # Pester 5 runs each test file in its own scope, so this setup is repeated
    # per suite. It cannot live in a helper function: dot-sourcing the modules
    # inside one would scope those definitions to the function.
    $script:ROOT = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
    $script:LIB_DIR = Join-Path $script:ROOT "lib"
    $script:BIN_DIR = Join-Path $script:ROOT "bin"

    . "$script:LIB_DIR\core\base.ps1"
    . "$script:LIB_DIR\core\log.ps1"
    . "$script:LIB_DIR\core\file_ops.ps1"

    $script:TEST_TEMP = Join-Path $env:TEMP "WinMole_Tests_Commands_$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TEST_TEMP -Force | Out-Null
}

AfterAll {
    if ($script:TEST_TEMP -and (Test-Path $script:TEST_TEMP)) {
        Remove-Item -Path $script:TEST_TEMP -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# Script Validation
# ============================================================================

Describe "Script Validation" {

    Context "PowerShell Scripts Syntax" {

        BeforeDiscovery {
            $rootDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
            $script:AllScripts = Get-ChildItem -Path $rootDir -Include "*.ps1" -Recurse
        }

        It "validates: <_.Name>" -ForEach $AllScripts {
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $_.FullName,
                [ref]$null,
                [ref]$parseErrors
            )
            $parseErrors.Count | Should -Be 0
        }
    }
}

# ============================================================================
# Command Entry Points
# ============================================================================

Describe "Commands" {

    Context "winmole.ps1" {
        It "exists at root" {
            Test-Path (Join-Path $script:ROOT "winmole.ps1") | Should -Be $true
        }

        It "shows version with -Version flag" {
            $output = & (Join-Path $script:ROOT "winmole.ps1") -Version 6>&1 | Out-String
            $output | Should -Match "WinMole"
        }

        It "shows help with -ShowHelp flag" {
            $output = & (Join-Path $script:ROOT "winmole.ps1") -ShowHelp 6>&1 | Out-String
            $output | Should -Match "COMMANDS"
        }
    }

    Context "bin/clean.ps1" {
        It "exists" {
            Test-Path (Join-Path $script:BIN_DIR "clean.ps1") | Should -Be $true
        }

        It "shows help with -Help flag" {
            $output = & (Join-Path $script:BIN_DIR "clean.ps1") -Help 6>&1 | Out-String
            $output | Should -Match "USAGE"
        }
    }

    Context "bin/purge.ps1" {
        It "exists" {
            Test-Path (Join-Path $script:BIN_DIR "purge.ps1") | Should -Be $true
        }
    }

    Context "bin/optimize.ps1" {
        It "exists" {
            Test-Path (Join-Path $script:BIN_DIR "optimize.ps1") | Should -Be $true
        }
    }

    Context "bin/uninstall.ps1" {
        It "exists" {
            Test-Path (Join-Path $script:BIN_DIR "uninstall.ps1") | Should -Be $true
        }
    }
}
