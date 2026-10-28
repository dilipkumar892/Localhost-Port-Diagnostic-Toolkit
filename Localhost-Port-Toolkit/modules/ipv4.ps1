# ==============================================================================
# Localhost & Port Diagnostic Toolkit - IPv4 Diagnostics Module
# File: modules/ipv4.ps1
# Description: IPv4 configuration, subnetting, DHCP status, APIPA detection,
#              default gateway reachability, and DNS resolution validation.
# ==============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) "lib"
. (Join-Path $libDir "common.ps1")
. (Join-Path $libDir "logging.ps1")
. (Join-Path $libDir "validation.ps1")

function Get-IPv4DetailedReport {
    $report = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        $ipEntries = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" }

        foreach ($entry in $ipEntries) {
            $ifIndex = $entry.InterfaceIndex
            $ad = Get-NetAdapter -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue

            $gateway = (Get-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty NextHop) -join ", "
            if (-not $gateway) { $gateway = "None" }

            $dns = (Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses) -join ", "
            if (-not $dns) { $dns = "None" }

            $gwReachable = "N/A"
            if ($gateway -ne "None" -and $gateway -match '^\d+\.\d+\.\d+\.\d+$') {
                try {
                    $p = [System.Net.NetworkInformation.Ping]::new()
                    $rep = $p.Send($gateway, 1000)
                    $gwReachable = if ($rep.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { "$($rep.RoundtripTime) ms" } else { "Unreachable" }
                } catch {
                    $gwReachable = "Ping Failed"
                }
            }

            $isApipa = $entry.IPAddress.StartsWith("169.254.")

            $report.Add([PSCustomObject]@{
                InterfaceAlias  = $entry.InterfaceAlias
                AdapterName     = if ($ad) { $ad.Name } else { "Unknown" }
                Status          = if ($ad) { $ad.Status } else { "Unknown" }
                IPAddress       = $entry.IPAddress
                PrefixLength    = $entry.PrefixLength
                DefaultGateway  = $gateway
                GatewayLatency  = $gwReachable
                DnsServers      = $dns
                IsAPIPA         = $isApipa
            })
        }
    }
    catch {
        Write-Log -Level "ERROR" -Module "IPV4" -Message "Failed to query IPv4 configuration: $_"
    }

    return $report
}

function Show-IPv4DiagnosticsUI {
    Clear-Host
    Write-Header -Title "IPv4 Subsystem Diagnostics" -Subtitle "Inspect adapter configurations, gateway routing, and DNS servers"

    Write-Info "Inspecting active IPv4 network interfaces and testing gateway latency..."
    $adapters = Get-IPv4DetailedReport

    if ($adapters.Count -eq 0) {
        Write-Warning "No active IPv4 interfaces detected."
        Pause-Console
        return
    }

    foreach ($a in $adapters) {
        Write-Host ""
        Write-Section "Interface: $($a.InterfaceAlias) ($($a.Status))"

        $ipTag = if ($a.IsAPIPA) { "FAIL" } else { "OK" }
        $ipNote = if ($a.IsAPIPA) { "$($a.IPAddress) [APIPA - DHCP failed to assign an address!]" } else { "$($a.IPAddress)/$($a.PrefixLength)" }
        Write-Badge -Status $ipTag -Label "IPv4 Address" -Value $ipNote

        $gwTag = if ($a.DefaultGateway -eq "None") { "WARN" } elseif ($a.GatewayLatency -eq "Unreachable") { "FAIL" } else { "OK" }
        Write-Badge -Status $gwTag -Label "Default Gateway" -Value "$($a.DefaultGateway) (Latency: $($a.GatewayLatency))"

        $dnsTag = if ($a.DnsServers -eq "None") { "WARN" } else { "INFO" }
        Write-Badge -Status $dnsTag -Label "DNS Server(s)" -Value "$($a.DnsServers)"

        if ($a.IsAPIPA) {
            Write-Host ""
            Write-Warning "CRITICAL: This adapter has self-assigned an APIPA address (169.254.x.x)."
            Write-Host "  Cause: DHCP server or router did not respond to lease requests." -ForegroundColor Yellow
            Write-Host "  Effect: You will NOT have Internet connectivity or LAN access on this adapter." -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Section "IPv4 Routing Table Check"
    try {
        $routes = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
        if ($routes) {
            foreach ($r in $routes) {
                Write-Host "  -> Default Route: Gateway $($r.NextHop) on Interface $($r.InterfaceAlias) (Metric: $($r.RouteMetric))" -ForegroundColor Cyan
            }
        } else {
            Write-Warning "No default IPv4 route (0.0.0.0/0) found. Outbound Internet routing is unavailable."
        }
    } catch {}

    Write-Log -Level "INFO" -Module "IPV4" -Message "Completed IPv4 diagnostics for $($adapters.Count) interfaces."
    Pause-Console
}
