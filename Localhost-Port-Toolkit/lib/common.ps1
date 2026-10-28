# ==============================================================================
# Localhost & Port Diagnostic Toolkit - Common Library
# File: lib/common.ps1
# Description: Global helpers, ANSI styling, environment detection, configuration
# ==============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

# ANSI Color Code Definitions
$global:ESC = [char]27
$global:Style = @{
    Reset       = "$([char]27)[0m"
    Bold        = "$([char]27)[1m"
    Dim         = "$([char]27)[2m"
    Underline   = "$([char]27)[4m"
    Black       = "$([char]27)[30m"
    Red         = "$([char]27)[31m"
    Green       = "$([char]27)[32m"
    Yellow      = "$([char]27)[33m"
    Blue        = "$([char]27)[34m"
    Magenta     = "$([char]27)[35m"
    Cyan        = "$([char]27)[36m"
    White       = "$([char]27)[37m"
    Gray        = "$([char]27)[90m"
    BrightRed   = "$([char]27)[91m"
    BrightGreen = "$([char]27)[92m"
    BrightYellow= "$([char]27)[93m"
    BrightBlue  = "$([char]27)[94m"
    BrightMagenta= "$([char]27)[95m"
    BrightCyan  = "$([char]27)[96m"
    BrightWhite = "$([char]27)[97m"
    BgRed       = "$([char]27)[41m"
    BgGreen     = "$([char]27)[42m"
    BgYellow    = "$([char]27)[43m"
    BgBlue      = "$([char]27)[44m"
    BgDarkGray  = "$([char]27)[100m"
}

function Write-Styled {
    param (
        [string]$Text,
        [string]$Color = "White",
        [switch]$NoNewline
    )
    $styleCode = if ($global:Style.ContainsKey($Color)) { $global:Style[$Color] } else { "" }
    $out = "$styleCode$Text$($global:Style.Reset)"
    if ($NoNewline) {
        Write-Host -NoNewline $out
    } else {
        Write-Host $out
    }
}

function Write-Header {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Subtitle = ""
    )
    $line = "=" * 76
    Write-Host ""
    Write-Host "$($global:Style.Bold)$($global:Style.BrightCyan)$line$($global:Style.Reset)"
    Write-Host "$($global:Style.Bold)$($global:Style.BrightWhite)  $Title$($global:Style.Reset)"
    if ($Subtitle -ne "") {
        Write-Host "$($global:Style.Gray)  $Subtitle$($global:Style.Reset)"
    }
    Write-Host "$($global:Style.Bold)$($global:Style.BrightCyan)$line$($global:Style.Reset)"
    Write-Host ""
}

function Write-Section {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Title
    )
    Write-Host ""
    Write-Host "$($global:Style.Bold)$($global:Style.Yellow)[#] $Title$($global:Style.Reset)"
    Write-Host "$($global:Style.Gray)$('-' * ($Title.Length + 4))$($global:Style.Reset)"
}

function Write-Success {
    param ([string]$Message)
    Write-Host "$($global:Style.BrightGreen)[OK]   $($global:Style.Reset)$Message"
}

function Write-Warning {
    param ([string]$Message)
    Write-Host "$($global:Style.BrightYellow)[WARN] $($global:Style.Reset)$Message"
}

function Write-ErrorMsg {
    param ([string]$Message)
    Write-Host "$($global:Style.BrightRed)[FAIL] $($global:Style.Reset)$Message"
}

function Write-Info {
    param ([string]$Message)
    Write-Host "$($global:Style.BrightCyan)[INFO] $($global:Style.Reset)$Message"
}

function Write-Badge {
    param (
        [string]$Status,
        [string]$Label,
        [string]$Value
    )
    $tag = switch ($Status.ToUpper()) {
        "OK"   { "$($global:Style.BgGreen)$($global:Style.BrightWhite) PASS $($global:Style.Reset)" }
        "WARN" { "$($global:Style.BgYellow)$($global:Style.Black) WARN $($global:Style.Reset)" }
        "FAIL" { "$($global:Style.BgRed)$($global:Style.BrightWhite) FAIL $($global:Style.Reset)" }
        default{ "$($global:Style.BgBlue)$($global:Style.BrightWhite) INFO $($global:Style.Reset)" }
    }
    Write-Host ("  {0}  {1,-30} : {2}" -f $tag, $Label, $Value)
}

function Test-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-ToolkitRoot {
    $current = $PSScriptRoot
    if ($current -match '[\\/]lib$') {
        return (Split-Path -Parent $current)
    }
    return $current
}

function Get-ToolkitConfig {
    $rootDir = Get-ToolkitRoot
    $configPath = Join-Path $rootDir "config\settings.json"
    if (Test-Path $configPath) {
        try {
            $json = Get-Content -Path $configPath -Raw -ErrorAction Stop
            return ($json | ConvertFrom-Json)
        }
        catch {
            Write-Warning "Could not parse settings.json. Using built-in defaults."
        }
    }
    return [PSCustomObject]@{
        toolkit_name         = "Localhost & Port Diagnostic Toolkit"
        version              = "1.0.0"
        safe_mode            = $true
        http_timeout_seconds = 5
        common_ports         = @(3000, 3001, 4173, 4200, 5000, 5173, 5500, 8000, 8080, 8081, 8888, 9000)
        critical_processes   = @("system", "idle", "smss", "csrss", "wininit", "services", "lsass", "svchost", "explorer", "winlogon", "spoolsv", "dwm")
    }
}

function Get-SystemOverview {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $isAdmin = Test-IsAdmin
    $hostname = [System.Environment]::MachineName
    $user = [System.Environment]::UserName
    $domain = [System.Environment]::UserDomainName
    $psVer = $PSVersionTable.PSVersion.ToString()
    
    return [PSCustomObject]@{
        Hostname       = $hostname
        User           = "$domain\$user"
        OSName         = if ($os) { $os.Caption } else { [System.Environment]::OSVersion.VersionString }
        OSBuild        = if ($os) { $os.BuildNumber } else { [System.Environment]::OSVersion.Version.Build }
        OSArchitecture = if ($os) { $os.OSArchitecture } else { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment').PROCESSOR_ARCHITECTURE }
        PowerShellVer  = $psVer
        IsAdmin        = $isAdmin
        Timestamp      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
}

function Pause-Console {
    param ([string]$Prompt = "Press Enter to return to main menu...")
    Write-Host ""
    Write-Styled "$Prompt" -Color "Gray" -NoNewline
    [void][System.Console]::ReadLine()
}
