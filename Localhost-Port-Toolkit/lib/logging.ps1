# ==============================================================================
# Localhost & Port Diagnostic Toolkit - Logging Library
# File: lib/logging.ps1
# Description: Thread-safe timestamped file logging, log viewing, and rotation
# ==============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$global:LogDirectory = $null
$global:CurrentLogFile = $null

function Initialize-Logger {
    param (
        [string]$BaseDir = ""
    )
    if ([string]::IsNullOrWhiteSpace($BaseDir)) {
        $parent = Split-Path -Parent $PSScriptRoot
        $BaseDir = Join-Path $parent "logs"
    }

    if (-not (Test-Path $BaseDir)) {
        New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
    }

    $global:LogDirectory = $BaseDir
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $global:CurrentLogFile = Join-Path $BaseDir "diagnostic_$today.log"

    if (-not (Test-Path $global:CurrentLogFile)) {
        $initHeader = @"
# ==============================================================================
# Localhost & Port Diagnostic Toolkit Session Log - $today
# Machine: $([System.Environment]::MachineName) | User: $([System.Environment]::UserName)
# ==============================================================================
"@
        Set-Content -Path $global:CurrentLogFile -Value $initHeader -Encoding utf8
    }

    Write-Log -Level "INFO" -Module "SYSTEM" -Message "Logger initialized at $global:CurrentLogFile"
}

function Write-Log {
    param (
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")]
        [string]$Level = "INFO",
        [Parameter(Mandatory = $true)]
        [string]$Module,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($null -eq $global:CurrentLogFile -or -not (Test-Path (Split-Path -Parent $global:CurrentLogFile))) {
        Initialize-Logger
    }

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $entry = "[{0}] [{1,-5}] [{2,-12}] {3}" -f $timestamp, $Level, $Module.ToUpper(), $Message

    try {
        Add-Content -Path $global:CurrentLogFile -Value $entry -Encoding utf8 -ErrorAction SilentlyContinue
    }
    catch {
        Write-Debug "Log writing failed: $_"
    }
}

function Get-RecentLogs {
    param (
        [int]$Count = 50,
        [string]$Filter = ""
    )

    if ($null -eq $global:CurrentLogFile -or -not (Test-Path $global:CurrentLogFile)) {
        Initialize-Logger
    }

    if (Test-Path $global:CurrentLogFile) {
        $lines = Get-Content -Path $global:CurrentLogFile -Encoding utf8
        if (-not [string]::IsNullOrWhiteSpace($Filter)) {
            $lines = $lines | Where-Object { $_ -match $Filter }
        }
        return ($lines | Select-Object -Last $Count)
    }
    return @()
}

function Show-LogsViewer {
    param (
        [int]$DefaultLines = 35
    )

    Clear-Host
    Write-Header -Title "Diagnostic System Logs Viewer" -Subtitle "Inspecting log: $global:CurrentLogFile"
    
    $logs = Get-RecentLogs -Count $DefaultLines
    if ($logs.Count -eq 0) {
        Write-Warning "No logs recorded for today yet."
    } else {
        foreach ($line in $logs) {
            if ($line.StartsWith("#")) {
                Write-Host $line -ForegroundColor DarkGray
            } elseif ($line -match '\[ERROR\]') {
                Write-Host $line -ForegroundColor Red
            } elseif ($line -match '\[WARN \]') {
                Write-Host $line -ForegroundColor Yellow
            } elseif ($line -match '\[INFO \]') {
                Write-Host $line -ForegroundColor Cyan
            } else {
                Write-Host $line -ForegroundColor Gray
            }
        }
    }

    Write-Host ""
    Write-Info "Total lines displayed: $($logs.Count) (File: $global:CurrentLogFile)"
    Pause-Console
}
