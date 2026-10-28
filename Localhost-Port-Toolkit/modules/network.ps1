# ==============================================================================
# Localhost & Port Diagnostic Toolkit - Network & Connectivity Module
# File: modules/network.ps1
# Description: Localhost loopback diagnostics, hosts file analysis, LAN adapter
#              enumeration, LAN URL generation, and interface binding comparison.
# ==============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) "lib"
. (Join-Path $libDir "common.ps1")
. (Join-Path $libDir "logging.ps1")
. (Join-Path $libDir "validation.ps1")
. (Join-Path $libDir "safety.ps1")
. (Join-Path $PSScriptRoot "ports.ps1")

function Test-SocketConnectivity {
    param (
        [string]$Address,
        [int]$Port,
        [int]$TimeoutMs = 2000
    )
    $tcpClient = [System.Net.Sockets.TcpClient]::new()
    try {
        $ar = $tcpClient.BeginConnect($Address, $Port, $null, $null)
        $wh = $ar.AsyncWaitHandle
        if (-not $wh.WaitOne($TimeoutMs, $false)) {
            $tcpClient.Close()
            return $false
        }
        $tcpClient.EndConnect($ar)
        $tcpClient.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Test-LocalhostStack {
    $results = [PSCustomObject]@{
        IPv4LoopbackPing       = $false
        IPv6LoopbackPing       = $false
        LocalhostResolvesTo    = @()
        PreferredFamily        = "Unknown"
        HostsFileHasLocalhost  = $false
        HostsFileOverrides     = @()
        PotentialIssues        = @()
    }

    try {
        $ping = [System.Net.NetworkInformation.Ping]::new()
        $reply = $ping.Send("127.0.0.1", 1000)
        $results.IPv4LoopbackPing = ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
    } catch {}

    try {
        $ping6 = [System.Net.NetworkInformation.Ping]::new()
        $reply6 = $ping6.Send("::1", 1000)
        $results.IPv6LoopbackPing = ($reply6.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
    } catch {}

    try {
        $resolved = [System.Net.Dns]::GetHostAddresses("localhost")
        foreach ($addr in $resolved) {
            $results.LocalhostResolvesTo += $addr.IPAddressToString
        }
        if ($results.LocalhostResolvesTo.Count -gt 0) {
            $first = $results.LocalhostResolvesTo[0]
            if ($first -eq "::1") {
                $results.PreferredFamily = "IPv6 (::1)"
            } elseif ($first -eq "127.0.0.1") {
                $results.PreferredFamily = "IPv4 (127.0.0.1)"
            } else {
                $results.PreferredFamily = $first
            }
        }
    } catch {
        $results.PotentialIssues += "Failed to resolve hostname 'localhost' via system DNS resolver."
    }

    $hostsPath = "C:\Windows\System32\drivers\etc\hosts"
    if (Test-Path $hostsPath) {
        $hostsLines = Get-Content -Path $hostsPath -ErrorAction SilentlyContinue
        foreach ($line in $hostsLines) {
            $clean = $line.Trim()
            if ($clean.StartsWith("#") -or [string]::IsNullOrWhiteSpace($clean)) { continue }
            if ($clean -match '\blocalhost\b') {
                $results.HostsFileHasLocalhost = $true
                $results.HostsFileOverrides += $clean
            }
        }
    }

    if ($results.PreferredFamily -like "*IPv6*" -and -not ($results.LocalhostResolvesTo -contains "127.0.0.1")) {
        $results.PotentialIssues += "Localhost resolves exclusively to IPv6 (::1). Servers listening only on 127.0.0.1 (IPv4) may appear offline in browsers navigating to 'http://localhost'."
    }

    return $results
}

function Get-ActiveNetworkAdapters {
    $adapterList = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
        foreach ($ad in $adapters) {
            $ipProps = Get-NetIPAddress -InterfaceIndex $ad.InterfaceIndex -ErrorAction SilentlyContinue
            $ipv4 = ($ipProps | Where-Object { $_.AddressFamily -eq "IPv4" } | Select-Object -ExpandProperty IPAddress) -join ", "
            $ipv6 = ($ipProps | Where-Object { $_.AddressFamily -eq "IPv6" -and $_.IPAddress -notmatch '^fe80' } | Select-Object -ExpandProperty IPAddress) -join ", "
            $linkLocal = ($ipProps | Where-Object { $_.IPAddress -match '^fe80' } | Select-Object -ExpandProperty IPAddress) -join ", "

            $gateway = (Get-NetRoute -InterfaceIndex $ad.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty NextHop) -join ", "

            $adapterList.Add([PSCustomObject]@{
                Name           = $ad.Name
                Description    = $ad.InterfaceDescription
                InterfaceIndex = $ad.InterfaceIndex
                Type           = $ad.MediaType
                LinkSpeed      = $ad.LinkSpeed
                IPv4           = if ($ipv4) { $ipv4 } else { "None" }
                IPv6           = if ($ipv6) { $ipv6 } else { "None" }
                LinkLocalIPv6  = if ($linkLocal) { $linkLocal } else { "None" }
                Gateway        = if ($gateway) { $gateway } else { "None" }
                MacAddress     = $ad.MacAddress
            })
        }
    }
    catch {
        Write-Log -Level "WARN" -Module "NETWORK" -Message "Get-NetAdapter query failed: $_"
    }

    return $adapterList
}

function Show-LocalhostTestUI {
    Clear-Host
    Write-Header -Title "Localhost Connectivity Test" -Subtitle "Verify IPv4/IPv6 loopback adapters, DNS resolution, and hosts file configuration"

    Write-Info "Executing comprehensive loopback diagnostic tests..."
    $diag = Test-LocalhostStack

    Write-Host ""
    Write-Section "Loopback Subsystem Health"
    
    $v4Status = if ($diag.IPv4LoopbackPing) { "OK" } else { "FAIL" }
    Write-Badge -Status $v4Status -Label "IPv4 Loopback (127.0.0.1)" -Value $(if ($diag.IPv4LoopbackPing) { "Operational (Responding to ICMP)" } else { "Failed (Ping returned no reply)" })

    $v6Status = if ($diag.IPv6LoopbackPing) { "OK" } else { "WARN" }
    Write-Badge -Status $v6Status -Label "IPv6 Loopback (::1)" -Value $(if ($diag.IPv6LoopbackPing) { "Operational (Responding to ICMP)" } else { "Inactive / Filtered" })

    Write-Host ""
    Write-Section "Name Resolution and Hosts File"
    $resStr = if ($diag.LocalhostResolvesTo.Count -gt 0) { $diag.LocalhostResolvesTo -join ", " } else { "Failed to resolve" }
    Write-Badge -Status "INFO" -Label "'localhost' Resolves To" -Value $resStr
    Write-Badge -Status "INFO" -Label "Preferred IP Family" -Value $diag.PreferredFamily

    if ($diag.HostsFileOverrides.Count -gt 0) {
        Write-Badge -Status "WARN" -Label "Hosts File Overrides" -Value ($diag.HostsFileOverrides -join "; ")
    } else {
        Write-Badge -Status "OK" -Label "Hosts File Status" -Value "Clean (Default Windows DNS handling)"
    }

    if ($diag.PotentialIssues.Count -gt 0) {
        Write-Host ""
        Write-Section "Diagnostic Findings and Guidance"
        foreach ($issue in $diag.PotentialIssues) {
            Write-Warning "$issue"
        }
    } else {
        Write-Host ""
        Write-Success "Localhost networking stack is healthy and ready for local development."
    }

    Write-Log -Level "INFO" -Module "LOCALHOST" -Message "Localhost test completed. IPv4: $($diag.IPv4LoopbackPing), IPv6: $($diag.IPv6LoopbackPing)"
    Pause-Console
}

function Show-LanTestUI {
    Clear-Host
    Write-Header -Title "LAN Accessibility and Remote Device Diagnostics" -Subtitle "Find local IP addresses, generate shareable LAN URLs, and test interface binding"

    Explain-BindAddressRisk

    Write-Info "Scanning active network adapters..."
    $adapters = Get-ActiveNetworkAdapters

    if ($adapters.Count -eq 0) {
        Write-Warning "No active network adapters with 'Up' status were detected."
        Pause-Console
        return
    }

    Write-Host ""
    Write-Section "Active Network Interfaces"
    foreach ($ad in $adapters) {
        Write-Host "$($global:Style.Bold)$($global:Style.BrightCyan)[Adapter] $($ad.Name) ($($ad.Description))$($global:Style.Reset)"
        Write-Host "  Type: $($ad.Type) | Link Speed: $($ad.LinkSpeed) | MAC: $($ad.MacAddress)" -ForegroundColor DarkGray
        Write-Badge -Status "INFO" -Label "IPv4 Address" -Value "$($ad.IPv4)"
        Write-Badge -Status "INFO" -Label "Default Gateway" -Value "$($ad.Gateway)"
        if ($ad.IPv6 -ne "None") {
            Write-Badge -Status "INFO" -Label "IPv6 Address" -Value "$($ad.IPv6)"
        }
        Write-Host ""
    }

    Write-Styled "Enter the port number your dev server is running on (e.g. 3000, 5173, 8000): " -Color "Yellow" -NoNewline
    $portInput = [System.Console]::ReadLine().Trim()

    if ($portInput -match '^\d+$') {
        [int]$port = [int]$portInput
        Write-Host ""
        Write-Section "LAN Hosting Diagnostics for Port $port"

        $activeListeners = Get-PortProcessMap | Where-Object { $_.LocalPort -eq $port }

        if ($activeListeners.Count -eq 0) {
            Write-Warning "No server is currently listening on port $port."
        } else {
            $isBoundAll = $false
            $isBoundLoopbackOnly = $false

            foreach ($l in $activeListeners) {
                if ($l.LocalAddress -in @("0.0.0.0", "::")) {
                    $isBoundAll = $true
                } elseif ($l.LocalAddress -in @("127.0.0.1", "::1", "localhost")) {
                    $isBoundLoopbackOnly = $true
                }
            }

            if ($isBoundAll) {
                Write-Success "Server is bound to ALL INTERFACES ($($activeListeners[0].LocalAddress)). It is ready for LAN access!"
            } elseif ($isBoundLoopbackOnly) {
                Write-Warning "SERVER BOUND TO LOOPBACK ONLY ($($activeListeners[0].LocalAddress))!"
                Write-Host "  Other devices on your Wi-Fi/LAN (mobile phones, tablets) CANNOT reach this server." -ForegroundColor Yellow
                Write-Host "  Solution: Start your server bound to 0.0.0.0 (e.g. 'npm run dev -- --host 0.0.0.0' or 'python -m http.server $port --bind 0.0.0.0')." -ForegroundColor Cyan
            }
        }

        Write-Host ""
        Write-Host "$($global:Style.Bold)$($global:Style.BrightGreen)SHAREABLE LAN URLS FOR MOBILE/REMOTE TESTING:$($global:Style.Reset)"
        foreach ($ad in $adapters) {
            if ($ad.IPv4 -ne "None") {
                $ips = $ad.IPv4 -split ',\s*'
                foreach ($singleIp in $ips) {
                    if ($singleIp -notmatch '^169\.254') {
                        Write-Host "  -> http://${singleIp}:$port/  ($($ad.Name))" -ForegroundColor Cyan
                    }
                }
            }
        }
    }

    Write-Log -Level "INFO" -Module "LAN" -Message "Inspected active adapters and generated LAN URLs."
    Pause-Console
}
