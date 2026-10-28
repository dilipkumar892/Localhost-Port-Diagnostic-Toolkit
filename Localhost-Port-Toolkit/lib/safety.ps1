# ==============================================================================
# Localhost & Port Diagnostic Toolkit - Safety & Safeguards Library
# File: lib/safety.ps1
# Description: Guardrails against accidental termination of critical system
#              processes, safe firewall policies, and user confirmation protocols.
# ==============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$global:ProtectedProcessNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
@(
    "system",
    "system idle process",
    "idle",
    "smss",
    "csrss",
    "wininit",
    "services",
    "lsass",
    "lsm",
    "svchost",
    "explorer",
    "winlogon",
    "spoolsv",
    "dwm",
    "audiodg",
    "fontdrvhost",
    "sihost",
    "taskhostw",
    "securityhealthservice",
    "searchhost",
    "startmenuexperiencehost",
    "shellexperiencehost"
) | ForEach-Object { [void]$global:ProtectedProcessNames.Add($_) }

$global:ProtectedPIDs = @(0, 4)

function Test-IsCriticalProcess {
    param (
        [int]$ProcessId,
        [string]$ProcessName = ""
    )

    if ($global:ProtectedPIDs -contains $ProcessId) {
        return $true
    }

    if (-not [string]::IsNullOrWhiteSpace($ProcessName)) {
        $cleanName = [System.IO.Path]::GetFileNameWithoutExtension($ProcessName).ToLower().Trim()
        if ($global:ProtectedProcessNames.Contains($cleanName)) {
            return $true
        }
    }

    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
        $procBaseName = $proc.ProcessName.ToLower()
        if ($global:ProtectedProcessNames.Contains($procBaseName)) {
            return $true
        }
        if ($proc.Path) {
            $winDir = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Windows)
            $sys32 = Join-Path $winDir "System32"
            if ($proc.Path.StartsWith($sys32, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($global:ProtectedProcessNames.Contains($proc.ProcessName.ToLower())) {
                    return $true
                }
            }
        }
    }
    catch {
        return $false
    }

    return $false
}

function Confirm-Action {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PromptMessage,
        [string]$ExpectedConfirmation = "Y",
        [string]$WarningDetails = ""
    )

    Write-Host ""
    if (-not [string]::IsNullOrWhiteSpace($WarningDetails)) {
        Write-Warning "$WarningDetails"
    }

    Write-Host "$($global:Style.Bold)$($global:Style.Yellow)$PromptMessage$($global:Style.Reset)" -NoNewline
    Write-Host " (Type '$ExpectedConfirmation' to confirm, any other key to cancel): " -ForegroundColor Cyan -NoNewline

    $userInput = [System.Console]::ReadLine()
    if ($null -eq $userInput) { return $false }

    $userInput = $userInput.Trim()
    if ($userInput -eq $ExpectedConfirmation -or $userInput.Equals($ExpectedConfirmation, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    return $false
}

function Assert-SafeProcessKill {
    param (
        [Parameter(Mandatory = $true)]
        [int]$ProcessId,
        [string]$ProcessName = ""
    )

    if (Test-IsCriticalProcess -ProcessId $ProcessId -ProcessName $ProcessName) {
        return [PSCustomObject]@{
            Allowed = $false
            Reason  = "CRITICAL SYSTEM PROCESS: Process '$ProcessName' (PID $ProcessId) is protected by Windows. Terminating this process could cause instant BSOD or system instability."
        }
    }

    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
        return [PSCustomObject]@{
            Allowed = $true
            Process = $proc
            Reason  = "Process '$($proc.ProcessName)' (PID $ProcessId) is a user-space application and eligible for termination."
        }
    }
    catch {
        return [PSCustomObject]@{
            Allowed = $false
            Reason  = "Process PID $ProcessId is not currently running or cannot be located."
        }
    }
}

function Get-AlternativePort {
    param (
        [int]$StartingPort = 3000,
        [int]$MaxOffset = 100
    )

    $usedPorts = [System.Collections.Generic.HashSet[int]]::new()
    try {
        Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
            [void]$usedPorts.Add($_.LocalPort)
        }
    }
    catch {
        $lines = netstat -ano
        foreach ($line in $lines) {
            if ($line -match 'TCP\s+\S+:(\d+)\s+.*LISTENING') {
                [void]$usedPorts.Add([int]$matches[1])
            }
        }
    }

    for ($i = 0; $i -le $MaxOffset; $i++) {
        $candidate = $StartingPort + $i
        if ($candidate -le 65535 -and -not $usedPorts.Contains($candidate)) {
            return $candidate
        }
    }

    return $null
}

function Safe-OpenTaskManager {
    try {
        Start-Process "taskmgr.exe"
        Write-Success "Windows Task Manager launched successfully."
    }
    catch {
        Write-ErrorMsg "Failed to launch Task Manager: $_"
    }
}

function Explain-BindAddressRisk {
    Write-Host ""
    Write-Host "$($global:Style.Bold)$($global:Style.BrightCyan)NETWORK BINDING SECURITY OVERVIEW:$($global:Style.Reset)"
    Write-Host "  $($global:Style.BrightGreen)127.0.0.1 (Loopback):$($global:Style.Reset)"
    Write-Host "    - Restricts server access strictly to the local PC."
    Write-Host "    - Safest for development. Invisible to your Wi-Fi/LAN peers and mobile devices."
    Write-Host ""
    Write-Host "  $($global:Style.BrightYellow)0.0.0.0 (All Interfaces / Wildcard):$($global:Style.Reset)"
    Write-Host "    - Binds to every network interface on your computer (Ethernet, Wi-Fi, VPN, WSL)."
    Write-Host "    - Allows other devices on your LAN (phones, tablets, coworkers) to reach your server."
    Write-Host "    - Requires Windows Firewall inbound permission."
    Write-Host "    - $($global:Style.BrightRed)CAUTION:$($global:Style.Reset) Never run unauthenticated debug/admin consoles on 0.0.0.0 when connected to public/untrusted networks!"
    Write-Host ""
}
