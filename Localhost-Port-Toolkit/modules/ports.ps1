# ==============================================================================
# Localhost & Port Diagnostic Toolkit - Port Diagnostics Module
# File: modules/ports.ps1
# Description: TCP/UDP enumeration, port-to-process mapping, conflict detection
# ==============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) "lib"
. (Join-Path $libDir "common.ps1")
. (Join-Path $libDir "logging.ps1")
. (Join-Path $libDir "validation.ps1")
. (Join-Path $libDir "safety.ps1")

function Get-ProcessCommandLineSafe {
    param ([int]$PID)
    if ($PID -le 4) { return "System Kernel" }
    try {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction SilentlyContinue
        if ($proc -and $proc.CommandLine) {
            return $proc.CommandLine
        }
    }
    catch {}
    return "N/A"
}

function Get-PortProcessMap {
    param (
        [switch]$IncludeUDP
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $procCache = @{}

    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        $procCache[$_.Id] = $_
    }

    try {
        $tcpConns = Get-NetTCPConnection -State Listen -ErrorAction Stop
        foreach ($conn in $tcpConns) {
            $pidVal = $conn.OwningProcess
            $procName = "Unknown"
            $procPath = "N/A"

            if ($procCache.ContainsKey($pidVal)) {
                $proc = $procCache[$pidVal]
                $procName = $proc.ProcessName
                try { $procPath = $proc.Path } catch { $procPath = "Access Denied" }
            } elseif ($pidVal -eq 0) {
                $procName = "System Idle"
            } elseif ($pidVal -eq 4) {
                $procName = "System"
            }

            $results.Add([PSCustomObject]@{
                Protocol       = "TCP"
                LocalAddress   = $conn.LocalAddress
                LocalPort      = [int]$conn.LocalPort
                State          = "LISTENING"
                PID            = $pidVal
                ProcessName    = $procName
                ExecutablePath = $procPath
                CommandLine    = $null
            })
        }
    }
    catch {
        Write-Log -Level "WARN" -Module "PORTS" -Message "Get-NetTCPConnection failed. Falling back to netstat -ano."
        $netstatOut = netstat -ano
        foreach ($line in $netstatOut) {
            if ($line -match '^\s*TCP\s+(\S+):(\d+)\s+(\S+)\s+LISTENING\s+(\d+)') {
                $localAddr = $matches[1]
                [int]$localPort = [int]$matches[2]
                [int]$pidVal = [int]$matches[4]
                $procName = if ($procCache.ContainsKey($pidVal)) { $procCache[$pidVal].ProcessName } else { "Unknown" }
                $procPath = if ($procCache.ContainsKey($pidVal)) {
                    try { $procCache[$pidVal].Path } catch { "Access Denied" }
                } else { "N/A" }

                $results.Add([PSCustomObject]@{
                    Protocol       = "TCP"
                    LocalAddress   = $localAddr
                    LocalPort      = $localPort
                    State          = "LISTENING"
                    PID            = $pidVal
                    ProcessName    = $procName
                    ExecutablePath = $procPath
                    CommandLine    = $null
                })
            }
        }
    }

    if ($IncludeUDP) {
        try {
            $udpEndpoints = Get-NetUDPEndpoint -ErrorAction Stop
            foreach ($udp in $udpEndpoints) {
                $pidVal = $udp.OwningProcess
                $procName = if ($procCache.ContainsKey($pidVal)) { $procCache[$pidVal].ProcessName } else { "Unknown" }
                $procPath = if ($procCache.ContainsKey($pidVal)) {
                    try { $procCache[$pidVal].Path } catch { "Access Denied" }
                } else { "N/A" }

                $results.Add([PSCustomObject]@{
                    Protocol       = "UDP"
                    LocalAddress   = $udp.LocalAddress
                    LocalPort      = [int]$udp.LocalPort
                    State          = "ACTIVE"
                    PID            = $pidVal
                    ProcessName    = $procName
                    ExecutablePath = $procPath
                    CommandLine    = $null
                })
            }
        }
        catch {
            $netstatOut = netstat -ano
            foreach ($line in $netstatOut) {
                if ($line -match '^\s*UDP\s+(\S+):(\d+)\s+\*:\*\s+(\d+)') {
                    $results.Add([PSCustomObject]@{
                        Protocol       = "UDP"
                        LocalAddress   = $matches[1]
                        LocalPort      = [int]$matches[2]
                        State          = "ACTIVE"
                        PID            = [int]$matches[3]
                        ProcessName    = if ($procCache.ContainsKey([int]$matches[3])) { $procCache[[int]$matches[3]].ProcessName } else { "Unknown" }
                        ExecutablePath = "N/A"
                        CommandLine    = $null
                    })
                }
            }
        }
    }

    return $results
}

function Test-PortInUse {
    param (
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [string]$Protocol = "TCP"
    )

    $all = Get-PortProcessMap -IncludeUDP ($Protocol -eq "UDP" -or $Protocol -eq "ALL")
    $matchedConns = @($all | Where-Object { $_.LocalPort -eq $Port })
    if ($Protocol -ne "ALL") {
        $matchedConns = @($matchedConns | Where-Object { $_.Protocol -eq $Protocol })
    }
    return ($matchedConns.Count -gt 0)
}

function Scan-PortsList {
    param (
        [Parameter(Mandatory = $true)]
        [int[]]$Ports,
        [switch]$ShowCommandLine
    )

    $activeListeners = Get-PortProcessMap -IncludeUDP
    $config = Get-ToolkitConfig
    $descriptions = $config.port_descriptions

    $scanResults = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($port in $Ports) {
        $listeners = @($activeListeners | Where-Object { $_.LocalPort -eq $port })
        $desc = if ($descriptions -and $descriptions.PSObject.Properties[$port.ToString()]) {
            $descriptions.$($port.ToString())
        } else {
            "Custom User Port"
        }

        if ($listeners.Count -gt 0) {
            foreach ($entry in $listeners) {
                $cmd = if ($ShowCommandLine) { Get-ProcessCommandLineSafe -PID $entry.PID } else { "N/A" }
                $scanResults.Add([PSCustomObject]@{
                    Port        = $port
                    Protocol    = $entry.Protocol
                    Address     = $entry.LocalAddress
                    Status      = "IN USE"
                    PID         = $entry.PID
                    Process     = $entry.ProcessName
                    Path        = $entry.ExecutablePath
                    CommandLine = $cmd
                    Description = $desc
                })
            }
        } else {
            $scanResults.Add([PSCustomObject]@{
                Port        = $port
                Protocol    = "TCP"
                Address     = "-"
                Status      = "AVAILABLE"
                PID         = "-"
                Process     = "-"
                Path        = "-"
                CommandLine = "-"
                Description = $desc
            })
        }
    }

    return $scanResults
}

function Detect-PortConflicts {
    $active = Get-PortProcessMap -IncludeUDP
    $conflicts = @($active | Group-Object -Property LocalPort | Where-Object { $_.Count -gt 1 })
    
    $conflictList = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($grp in $conflicts) {
        $pids = @($grp.Group | Select-Object -ExpandProperty PID -Unique)
        $names = ($grp.Group | Select-Object -ExpandProperty ProcessName -Unique) -join ", "
        $addresses = ($grp.Group | Select-Object -ExpandProperty LocalAddress) -join ", "
        $conflictList.Add([PSCustomObject]@{
            Port           = $grp.Name
            ListenerCount  = $grp.Count
            DistinctPIDs   = ($pids -join ", ")
            ProcessNames   = $names
            BoundAddresses = $addresses
            IsMultiProcess = ($pids.Count -gt 1)
        })
    }
    return $conflictList
}


function Show-PortScannerUI {
    Clear-Host
    Write-Header -Title "TCP Port Scanner - Local Machine" -Subtitle "Scans common development and custom ports"

    Write-Host "Select scanning mode:"
    Write-Host "  [1] Scan Standard Dev Ports (3000, 3001, 4173, 4200, 5000, 5173, 5500, 8000, 8080, 8081, 8888, 9000)"
    Write-Host "  [2] Scan Custom Port or Range (e.g. 8000, 8080 or 3000-3010)"
    Write-Host "  [3] Scan All Currently Listening TCP Ports on Machine"
    Write-Host "  [B] Back to Main Menu"
    Write-Host ""
    Write-Styled "Enter choice: " -Color "Yellow" -NoNewline
    $opt = [System.Console]::ReadLine()

    $config = Get-ToolkitConfig
    $portsToScan = @()

    switch ($opt.Trim()) {
        "1" {
            $portsToScan = $config.common_ports
        }
        "2" {
            Write-Host ""
            Write-Styled "Enter port(s) or range to scan: " -Color "Cyan" -NoNewline
            $inputPorts = [System.Console]::ReadLine()
            $parsed = Parse-PortInput -InputString $inputPorts
            if ($parsed.Count -eq 0) {
                Write-ErrorMsg "No valid ports entered."
                Pause-Console
                return
            }
            $portsToScan = $parsed
        }
        "3" {
            $allListening = Get-AllListeningPortsDetailed
            Show-ListeningPortsTable -Ports $allListening
            Pause-Console
            return
        }
        default {
            return
        }
    }

    Write-Host ""
    Write-Info "Scanning $($portsToScan.Count) port(s)..."
    $results = Scan-PortsList -Ports $portsToScan

    Write-Host ""
    $fmt = "{0,-7} {1,-5} {2,-15} {3,-11} {4,-7} {5,-18} {6,-25}"
    Write-Host ($fmt -f "PORT", "PROTO", "ADDRESS", "STATUS", "PID", "PROCESS", "DESCRIPTION") -ForegroundColor Cyan
    Write-Host ($fmt -f ("-"*6), ("-"*5), ("-"*14), ("-"*10), ("-"*6), ("-"*17), ("-"*24)) -ForegroundColor DarkGray

    foreach ($r in $results) {
        $statusColored = if ($r.Status -eq "IN USE") {
            "$($global:Style.BrightRed)IN USE     $($global:Style.Reset)"
        } else {
            "$($global:Style.BrightGreen)AVAILABLE  $($global:Style.Reset)"
        }
        $procClean = ($r.Process -split '\.')[0]
        $line = "{0,-7} {1,-5} {2,-15} {3} {4,-7} {5,-18} {6,-25}" -f $r.Port, $r.Protocol, $r.Address, $statusColored, $r.PID, $procClean, $r.Description
        Write-Host $line
    }

    $inUseCount = ($results | Where-Object { $_.Status -eq "IN USE" }).Count
    Write-Host ""
    Write-Info "Scan complete. In Use: $inUseCount | Available: $($results.Count - $inUseCount)"
    Write-Log -Level "INFO" -Module "PORTS" -Message "Scanned $($results.Count) ports. $inUseCount in use."

    Pause-Console
}

function Get-AllListeningPortsDetailed {
    $active = Get-PortProcessMap -IncludeUDP
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($item in $active) {
        $cmd = Get-ProcessCommandLineSafe -PID $item.PID
        $results.Add([PSCustomObject]@{
            Protocol    = $item.Protocol
            LocalAddress= $item.LocalAddress
            Port        = $item.LocalPort
            PID         = $item.PID
            ProcessName = $item.ProcessName
            Path        = $item.ExecutablePath
            CommandLine = $cmd
        })
    }
    return ($results | Sort-Object Port)
}

function Show-ListeningPortsTable {
    param ($Ports)
    Write-Host ""
    $fmt = "{0,-5} {1,-18} {2,-7} {3,-7} {4,-20} {5,-30}"
    Write-Host ($fmt -f "PROTO", "LOCAL ADDRESS", "PORT", "PID", "PROCESS", "COMMAND LINE (TRUNC)") -ForegroundColor Cyan
    Write-Host ($fmt -f ("-"*5), ("-"*17), ("-"*6), ("-"*6), ("-"*19), ("-"*29)) -ForegroundColor DarkGray

    foreach ($p in $Ports) {
        $shortCmd = "-"
        if ($p.CommandLine) {
            if ($p.CommandLine.Length -gt 30) {
                $shortCmd = $p.CommandLine.Substring(0, 27) + "..."
            } else {
                $shortCmd = $p.CommandLine
            }
        }
        Write-Host ($fmt -f $p.Protocol, $p.LocalAddress, $p.Port, $p.PID, $p.ProcessName, $shortCmd)
    }
}
