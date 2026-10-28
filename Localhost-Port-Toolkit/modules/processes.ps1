# ==============================================================================
# Localhost & Port Diagnostic Toolkit - Process Identification & Conflict Resolution
# File: modules/processes.ps1
# Description: Deep process inspection, ownership, and safe conflict resolution
# ==============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) "lib"
. (Join-Path $libDir "common.ps1")
. (Join-Path $libDir "logging.ps1")
. (Join-Path $libDir "validation.ps1")
. (Join-Path $libDir "safety.ps1")
. (Join-Path $PSScriptRoot "ports.ps1")

function Get-ProcessDetailedInfo {
    param (
        [Parameter(Mandatory = $true)]
        [int]$ProcessId
    )

    $details = [PSCustomObject]@{
        PID              = $ProcessId
        Name             = "Unknown"
        ExecutablePath   = "N/A"
        CommandLine      = "N/A"
        ParentPID        = "N/A"
        ParentName       = "N/A"
        StartTime        = "N/A"
        UserAccount      = "N/A"
        MemoryMB         = 0
        CPUSeconds       = 0
        IsSystemCritical = (Test-IsCriticalProcess -ProcessId $ProcessId)
        ListeningPorts   = @()
    }

    if ($ProcessId -eq 0) {
        $details.Name = "System Idle Process"
        $details.IsSystemCritical = $true
        return $details
    }
    if ($ProcessId -eq 4) {
        $details.Name = "System Kernel"
        $details.IsSystemCritical = $true
        return $details
    }

    try {
        $p = Get-Process -Id $ProcessId -ErrorAction Stop
        $details.Name = $p.ProcessName
        try { $details.ExecutablePath = $p.Path } catch { $details.ExecutablePath = "Access Denied" }
        try { $details.StartTime = $p.StartTime.ToString("yyyy-MM-dd HH:mm:ss") } catch {}
        try { $details.MemoryMB = [math]::Round($p.WorkingSet64 / 1MB, 2) } catch {}
        try { $details.CPUSeconds = [math]::Round($p.TotalProcessorTime.TotalSeconds, 2) } catch {}
    }
    catch {
        Write-Log -Level "WARN" -Module "PROCESS" -Message ("Could not open process PID {0}: {1}" -f $ProcessId, $_)
        return $details
    }

    try {
        $cimProc = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
        if ($cimProc) {
            if ($cimProc.CommandLine) { $details.CommandLine = $cimProc.CommandLine }
            if ($cimProc.ParentProcessId) {
                $details.ParentPID = $cimProc.ParentProcessId
                try {
                    $parentP = Get-Process -Id $cimProc.ParentProcessId -ErrorAction SilentlyContinue
                    if ($parentP) { $details.ParentName = $parentP.ProcessName }
                } catch {}
            }
            try {
                $owner = Invoke-CimMethod -InputObject $cimProc -MethodName GetOwner -ErrorAction SilentlyContinue
                if ($owner -and $owner.User) {
                    $details.UserAccount = "$($owner.Domain)\$($owner.User)"
                }
            } catch {}
        }
    }
    catch {}

    $allPorts = Get-PortProcessMap -IncludeUDP
    $ports = $allPorts | Where-Object { $_.PID -eq $ProcessId }
    $portStrings = @()
    foreach ($pt in $ports) {
        $portStrings += "$($pt.Protocol):$($pt.LocalPort) ($($pt.LocalAddress))"
    }
    $details.ListeningPorts = $portStrings

    return $details
}

function Show-PortUsageInspectorUI {
    Clear-Host
    Write-Header -Title "Port Usage Inspector" -Subtitle "Identify the exact process and service occupying any port"

    Write-Styled "Enter the port number to inspect (e.g. 3000, 8000, 8080): " -Color "Yellow" -NoNewline
    $inputStr = [System.Console]::ReadLine()

    $errMsg = ""
    if (-not (Test-ValidPort -Port $inputStr -ErrorMessage ([ref]$errMsg))) {
        Write-ErrorMsg $errMsg
        Pause-Console
        return
    }

    [int]$port = [int]$inputStr
    Write-Info "Inspecting port $port..."

    $active = Get-PortProcessMap -IncludeUDP
    $listeners = $active | Where-Object { $_.LocalPort -eq $port }

    if ($listeners.Count -eq 0) {
        Write-Host ""
        Write-Success "Port $port is currently FREE and AVAILABLE."
        Write-Host "No process is currently listening on this port." -ForegroundColor Gray
        Pause-Console
        return
    }

    Write-Host ""
    Write-Warning "Port $port is IN USE by $($listeners.Count) endpoint(s):"

    foreach ($l in $listeners) {
        $procInfo = Get-ProcessDetailedInfo -ProcessId $l.PID
        Write-Host ""
        Write-Section "Listener Details: $($l.Protocol) Port $port"
        Write-Badge -Status "WARN" -Label "Protocol / Binding" -Value "$($l.Protocol) on $($l.LocalAddress):$port"
        Write-Badge -Status "INFO" -Label "Process Name" -Value "$($procInfo.Name)"
        Write-Badge -Status "INFO" -Label "Process ID (PID)" -Value "$($procInfo.PID)"
        Write-Badge -Status "INFO" -Label "User Account" -Value "$($procInfo.UserAccount)"
        Write-Badge -Status "INFO" -Label "Memory Working Set" -Value "$($procInfo.MemoryMB) MB"
        Write-Badge -Status "INFO" -Label "Executable Path" -Value "$($procInfo.ExecutablePath)"
        Write-Badge -Status "INFO" -Label "Command Line" -Value "$($procInfo.CommandLine)"
        Write-Badge -Status $(if ($procInfo.IsSystemCritical) { "FAIL" } else { "OK" }) -Label "System Critical Process" -Value $(if ($procInfo.IsSystemCritical) { "YES (PROTECTED - Cannot terminate)" } else { "NO (User Application)" })
    }

    Pause-Console
}

function Show-ProcessIdentificationUI {
    Clear-Host
    Write-Header -Title "Process Identification and Inspection" -Subtitle "Locate process details by Process ID (PID) or Process Name"

    Write-Host "Search by:"
    Write-Host "  [1] Process ID (PID)"
    Write-Host "  [2] Process Name (e.g. node, python, uvicorn, chrome)"
    Write-Host "  [B] Back to Main Menu"
    Write-Host ""
    Write-Styled "Enter choice: " -Color "Yellow" -NoNewline
    $choice = [System.Console]::ReadLine()

    switch ($choice.Trim()) {
        "1" {
            Write-Styled "Enter PID: " -Color "Cyan" -NoNewline
            $pidStr = [System.Console]::ReadLine()
            if ($pidStr -notmatch '^\d+$') {
                Write-ErrorMsg "Invalid PID."
                Pause-Console
                return
            }
            [int]$targetPID = [int]$pidStr
            $info = Get-ProcessDetailedInfo -ProcessId $targetPID
            Display-ProcessCard -ProcessInfo $info
        }
        "2" {
            Write-Styled "Enter process name (e.g. node, python): " -Color "Cyan" -NoNewline
            $nameStr = [System.Console]::ReadLine().Trim()
            if ([string]::IsNullOrWhiteSpace($nameStr)) {
                Write-ErrorMsg "Process name cannot be empty."
                Pause-Console
                return
            }
            $clean = $nameStr -replace '\.exe$', ''
            $procs = Get-Process -Name "$clean*" -ErrorAction SilentlyContinue
            if (-not $procs -or $procs.Count -eq 0) {
                Write-Warning "No active processes matching '$clean' found."
                Pause-Console
                return
            }
            Write-Host ""
            Write-Info "Found $($procs.Count) matching process(es):"
            foreach ($pr in $procs) {
                $info = Get-ProcessDetailedInfo -ProcessId $pr.Id
                Display-ProcessCard -ProcessInfo $info
            }
        }
        default { return }
    }

    Pause-Console
}

function Display-ProcessCard {
    param ($ProcessInfo)
    Write-Host ""
    Write-Host "$($global:Style.Bold)$($global:Style.BrightCyan)=== Process: $($ProcessInfo.Name) (PID: $($ProcessInfo.PID)) ===$($global:Style.Reset)"
    Write-Badge -Status "INFO" -Label "Executable Path" -Value "$($ProcessInfo.ExecutablePath)"
    Write-Badge -Status "INFO" -Label "Parent PID / Name" -Value "$($ProcessInfo.ParentPID) ($($ProcessInfo.ParentName))"
    Write-Badge -Status "INFO" -Label "User Account" -Value "$($ProcessInfo.UserAccount)"
    Write-Badge -Status "INFO" -Label "Memory (RAM)" -Value "$($ProcessInfo.MemoryMB) MB"
    Write-Badge -Status "INFO" -Label "Start Time" -Value "$($ProcessInfo.StartTime)"
    Write-Badge -Status "INFO" -Label "Command Line" -Value "$($ProcessInfo.CommandLine)"
    $portsStr = if ($ProcessInfo.ListeningPorts.Count -gt 0) { $ProcessInfo.ListeningPorts -join ", " } else { "None" }
    Write-Badge -Status "INFO" -Label "Listening Ports" -Value $portsStr
    Write-Badge -Status $(if ($ProcessInfo.IsSystemCritical) { "FAIL" } else { "OK" }) -Label "System Critical?" -Value $(if ($ProcessInfo.IsSystemCritical) { "YES (DO NOT TERMINATE)" } else { "NO" })
}

function Show-PortConflictResolutionUI {
    Clear-Host
    Write-Header -Title "Port Conflict Resolution" -Subtitle "Safely resolve 'Address already in use' (EADDRINUSE / 10048) errors"

    Write-Styled "Enter the conflicted port number (e.g. 3000, 8000): " -Color "Yellow" -NoNewline
    $inputStr = [System.Console]::ReadLine()

    $errMsg = ""
    if (-not (Test-ValidPort -Port $inputStr -ErrorMessage ([ref]$errMsg))) {
        Write-ErrorMsg $errMsg
        Pause-Console
        return
    }

    [int]$port = [int]$inputStr
    Write-Info "Checking occupancy of port $port..."

    $active = Get-PortProcessMap -IncludeUDP
    $listeners = $active | Where-Object { $_.LocalPort -eq $port }

    if ($listeners.Count -eq 0) {
        Write-Success "Port $port is currently UNUSED. No conflict detected."
        Pause-Console
        return
    }

    Write-Warning "Port $port is currently OCCUPIED."
    Write-Host ""

    foreach ($l in $listeners) {
        $pInfo = Get-ProcessDetailedInfo -ProcessId $l.PID
        Display-ProcessCard -ProcessInfo $pInfo
        Write-Host ""

        $altPort = Get-AlternativePort -StartingPort ($port + 1)
        Write-Host "$($global:Style.Bold)$($global:Style.BrightGreen)RECOMMENDED RESOLUTION OPTIONS:$($global:Style.Reset)"
        Write-Host "  [1] Suggest Alternative Port: Next available port is $($global:Style.BrightYellow)$altPort$($global:Style.Reset)"
        Write-Host "  [2] Open Windows Task Manager (inspect manually)"
        Write-Host "  [3] Safely Terminate Conflicting Process (PID $($l.PID) - $($pInfo.Name))"
        Write-Host "  [C] Cancel / Return to Menu"
        Write-Host ""
        Write-Styled "Select action: " -Color "Yellow" -NoNewline
        $action = [System.Console]::ReadLine().Trim()

        switch ($action) {
            "1" {
                Write-Host ""
                Write-Success "Alternative Port Suggestion:"
                Write-Host "  Configure your server to bind to port $altPort instead of $port." -ForegroundColor Cyan
                Write-Host "  - Python: python -m http.server $altPort"
                Write-Host "  - Node / Vite: npm run dev -- --port $altPort"
                Write-Host "  - Next.js: npx next dev -p $altPort"
            }
            "2" {
                Safe-OpenTaskManager
            }
            "3" {
                $safetyCheck = Assert-SafeProcessKill -ProcessId $l.PID -ProcessName $pInfo.Name
                if (-not $safetyCheck.Allowed) {
                    Write-ErrorMsg "ACTION PROHIBITED: $($safetyCheck.Reason)"
                    Write-Log -Level "WARN" -Module "SAFETY" -Message "Blocked kill attempt on protected process PID $($l.PID) ($($pInfo.Name))"
                    break
                }

                $confirmed = Confirm-Action `
                    -PromptMessage "Are you ABSOLUTELY CERTAIN you want to stop process '$($pInfo.Name)' (PID $($l.PID))?" `
                    -ExpectedConfirmation "KILL" `
                    -WarningDetails "This will stop the process. Any unsaved data in this application will be lost."

                if ($confirmed) {
                    try {
                        Stop-Process -Id $l.PID -Force -ErrorAction Stop
                        Write-Success "Process $($pInfo.Name) (PID $($l.PID)) was terminated successfully."
                        Write-Log -Level "INFO" -Module "CONFLICT" -Message "User safely terminated process $($pInfo.Name) (PID $($l.PID)) occupying port $port."
                    }
                    catch {
                        Write-ErrorMsg "Failed to terminate process: $_"
                        Write-Log -Level "ERROR" -Module "CONFLICT" -Message "Failed to stop PID $($l.PID): $_"
                    }
                } else {
                    Write-Info "Termination cancelled by user."
                }
            }
            default {
                Write-Info "Operation cancelled."
            }
        }
    }

    Pause-Console
}
