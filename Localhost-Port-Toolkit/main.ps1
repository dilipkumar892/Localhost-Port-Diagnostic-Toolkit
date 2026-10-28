# ==============================================================================
# Localhost & Port Diagnostic Toolkit - Main Engine & Console Dashboard
# File: main.ps1
# Description: Central orchestrator, dashboard UI, and numbered menu router (1-16)
# ==============================================================================

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$Option = "",
    [switch]$NoColor
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$Host.UI.RawUI.WindowTitle = "Localhost & Port Diagnostic Toolkit"

$rootDir = $PSScriptRoot
$libDir = Join-Path $rootDir "lib"
$modDir = Join-Path $rootDir "modules"

. (Join-Path $libDir "common.ps1")
. (Join-Path $libDir "logging.ps1")
. (Join-Path $libDir "validation.ps1")
. (Join-Path $libDir "safety.ps1")

Initialize-Logger -BaseDir (Join-Path $rootDir "logs")

. (Join-Path $modDir "ports.ps1")
. (Join-Path $modDir "processes.ps1")
. (Join-Path $modDir "http.ps1")
. (Join-Path $modDir "network.ps1")
. (Join-Path $modDir "firewall.ps1")
. (Join-Path $modDir "ipv4.ps1")
. (Join-Path $modDir "ipv6.ps1")
. (Join-Path $modDir "projects.ps1")
. (Join-Path $modDir "hosting.ps1")
. (Join-Path $modDir "reports.ps1")

function Show-DashboardHeader {
    $sys = Get-SystemOverview
    $config = Get-ToolkitConfig

    Clear-Host
    Write-Host "$($global:Style.Bold)$($global:Style.BrightCyan)"
    Write-Host " ============================================================================== "
    Write-Host "      LOCAL HOST & PORT DIAGNOSTIC TOOLKIT (Windows 10 / 11 / Server)           "
    Write-Host " ============================================================================== $($global:Style.Reset)"
    
    $adminBadge = if ($sys.IsAdmin) {
        "$($global:Style.BgGreen)$($global:Style.BrightWhite) ELEVATED (Admin) $($global:Style.Reset)"
    } else {
        "$($global:Style.BgYellow)$($global:Style.Black) STANDARD USER $($global:Style.Reset)"
    }

    Write-Host " Host: $($global:Style.BrightWhite)$($sys.Hostname)$($global:Style.Reset) | User: $($sys.User) | $adminBadge"
    Write-Host " OS: $($sys.OSName) (Build $($sys.OSBuild)) | PS: v$($sys.PowerShellVer)" -ForegroundColor DarkGray
    Write-Host "$($global:Style.Gray)$('-' * 78)$($global:Style.Reset)"
}

function Show-MainMenu {
    Show-DashboardHeader

    Write-Host "$($global:Style.Bold)$($global:Style.BrightYellow) DIAGNOSTIC & MANAGEMENT OPTIONS:$($global:Style.Reset)"
    Write-Host ""
    Write-Host "  $($global:Style.BrightCyan) 1.$($global:Style.Reset) Localhost Connectivity Test               $($global:Style.BrightCyan) 9.$($global:Style.Reset) Firewall Diagnostics"
    Write-Host "  $($global:Style.BrightCyan) 2.$($global:Style.Reset) TCP Port Scanner - Local Machine          $($global:Style.BrightCyan)10.$($global:Style.Reset) IPv4 Diagnostics"
    Write-Host "  $($global:Style.BrightCyan) 3.$($global:Style.Reset) Port Usage Inspector                      $($global:Style.BrightCyan)11.$($global:Style.Reset) IPv6 Diagnostics"
    Write-Host "  $($global:Style.BrightCyan) 4.$($global:Style.Reset) Process Identification                    $($global:Style.BrightCyan)12.$($global:Style.Reset) Port Conflict Resolution"
    Write-Host "  $($global:Style.BrightCyan) 5.$($global:Style.Reset) HTTP Server Diagnostics                  $($global:Style.BrightCyan)13.$($global:Style.Reset) Project Hosting Assistant"
    Write-Host "  $($global:Style.BrightCyan) 6.$($global:Style.Reset) Python Dev Server Diagnostics            $($global:Style.BrightCyan)14.$($global:Style.Reset) Generate Diagnostic Report"
    Write-Host "  $($global:Style.BrightCyan) 7.$($global:Style.Reset) Node.js / npm Dev Server Diagnostics     $($global:Style.BrightCyan)15.$($global:Style.Reset) View Logs"
    Write-Host "  $($global:Style.BrightCyan) 8.$($global:Style.Reset) LAN Accessibility Test                    $($global:Style.BrightCyan)16.$($global:Style.Reset) Exit"
    Write-Host ""
    Write-Host "$($global:Style.Gray)$('-' * 78)$($global:Style.Reset)"
}

function Invoke-MenuOption {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Selection
    )

    $clean = $Selection.Trim().ToLower()
    Write-Log -Level "INFO" -Module "ROUTER" -Message "Menu option selected: $clean"

    switch ($clean) {
        "1"  { Show-LocalhostTestUI }
        "2"  { Show-PortScannerUI }
        "3"  { Show-PortUsageInspectorUI }
        "4"  { Show-ProcessIdentificationUI }
        "5"  { Show-HttpDiagnosticsUI }
        "6"  { Show-PythonDiagnosticsUI }
        "7"  { Show-NodeDiagnosticsUI }
        "8"  { Show-LanTestUI }
        "9"  { Show-FirewallDiagnosticsUI }
        "10" { Show-IPv4DiagnosticsUI }
        "11" { Show-IPv6DiagnosticsUI }
        "12" { Show-PortConflictResolutionUI }
        "13" { Show-HostingAssistantUI }
        "14" { Show-ReportGeneratorUI }
        "15" { Show-LogsViewer }
        { $_ -in @("16", "q", "exit", "quit") } {
            Write-Host ""
            Write-Info "Thank you for using the Localhost & Port Diagnostic Toolkit. Exiting."
            exit 0
        }
        default {
            Write-Host ""
            Write-ErrorMsg "Invalid selection '$Selection'. Please choose an option between 1 and 16."
            Start-Sleep -Seconds 2
        }
    }
}

if (-not [string]::IsNullOrWhiteSpace($Option)) {
    Invoke-MenuOption -Selection $Option
    exit 0
}

while ($true) {
    Show-MainMenu
    Write-Styled "Select an option [1-16]: " -Color "Yellow" -NoNewline
    $userInput = [System.Console]::ReadLine()

    if ($null -eq $userInput -or [string]::IsNullOrWhiteSpace($userInput)) {
        continue
    }

    Invoke-MenuOption -Selection $userInput
}
