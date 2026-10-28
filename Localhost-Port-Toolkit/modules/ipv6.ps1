# ==============================================================================
# Localhost & Port Diagnostic Toolkit - IPv6 Diagnostics Module
# File: modules/ipv6.ps1
# Description: IPv6 configuration, dual-stack resolution, prefix policy table,
#              and developer server dual-stack mismatch explanations.
# ==============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) "lib"
. (Join-Path $libDir "common.ps1")
. (Join-Path $libDir "logging.ps1")
. (Join-Path $libDir "validation.ps1")

function Get-IPv6PrefixPolicies {
    $policies = [System.Collections.Generic.List[PSCustomObject]]::new()
    try {
        $netsh = netsh interface ipv6 show prefixpolicies
        foreach ($line in $netsh) {
            if ($line -match '^\s*(\d+)\s+(\d+)\s+([a-f0-9\:\/]+)') {
                $precedence = [int]$matches[1]
                $label = [int]$matches[2]
                $prefix = $matches[3]

                $meaning = switch ($prefix) {
                    "::1/128"       { "Loopback (::1)" }
                    "::/0"          { "Native IPv6 Global Unicast" }
                    "::ffff:0:0/96" { "IPv4-Mapped Addresses (IPv4 fallback)" }
                    "2002::/16"     { "6to4 Tunnel" }
                    "2001::/32"     { "Teredo Tunnel" }
                    default         { "Special/Custom" }
                }

                $policies.Add([PSCustomObject]@{
                    Precedence = $precedence
                    Label      = $label
                    Prefix     = $prefix
                    Meaning    = $meaning
                })
            }
        }
    }
    catch {
        Write-Log -Level "WARN" -Module "IPV6" -Message "Failed to query prefix policies: $_"
    }

    return $policies
}

function Show-IPv6DiagnosticsUI {
    Clear-Host
    Write-Header -Title "IPv6 Subsystem and Dual-Stack Diagnostics" -Subtitle "Inspect IPv6 addresses, loopback binding, prefix policy order, and dev server compatibility"

    Write-Info "Scanning IPv6 addresses on all network adapters..."

    try {
        $ipv6Addrs = Get-NetIPAddress -AddressFamily IPv6 -ErrorAction SilentlyContinue
    } catch {
        $ipv6Addrs = @()
    }

    Write-Host ""
    Write-Section "IPv6 Addresses"
    if ($ipv6Addrs.Count -eq 0) {
        Write-Warning "No IPv6 addresses detected or IPv6 stack is disabled."
    } else {
        foreach ($addr in $ipv6Addrs) {
            $type = if ($addr.IPAddress -eq "::1") {
                "Loopback"
            } elseif ($addr.IPAddress.StartsWith("fe80:")) {
                "Link-Local"
            } elseif ($addr.IPAddress.StartsWith("fd") -or $addr.IPAddress.StartsWith("fc")) {
                "Unique Local (ULA)"
            } else {
                "Global Unicast"
            }
            Write-Badge -Status "INFO" -Label "$($addr.InterfaceAlias) [$type]" -Value "$($addr.IPAddress)/$($addr.PrefixLength)"
        }
    }

    Write-Host ""
    Write-Section "IPv6 Prefix Policy Table (Address Selection Precedence)"
    Write-Host "This table defines whether Windows prefers IPv6 or IPv4 when resolving hostnames like 'localhost':" -ForegroundColor Gray

    $policies = Get-IPv6PrefixPolicies
    if ($policies.Count -gt 0) {
        Write-Host ""
        $fmt = "  {0,-12} {1,-8} {2,-18} {3,-30}"
        Write-Host ($fmt -f "PRECEDENCE", "LABEL", "PREFIX", "PURPOSE") -ForegroundColor Cyan
        Write-Host ($fmt -f ("-"*10), ("-"*6), ("-"*16), ("-"*28)) -ForegroundColor DarkGray
        foreach ($p in ($policies | Sort-Object Precedence -Descending)) {
            Write-Host ($fmt -f $p.Precedence, $p.Label, $p.Prefix, $p.Meaning)
        }
    } else {
        Write-Warning "Unable to query netsh prefix policies."
    }

    Write-Host ""
    Write-Section "Dual-Stack Developer Server Gotchas"
    Write-Host "$($global:Style.Bold)$($global:Style.BrightYellow)1. Node.js v17+ / Next.js 'localhost' Issue:$($global:Style.Reset)"
    Write-Host "   Node.js v17 changed DNS resolution order from IPv4-first to IPv6-first (RFC 6724)."
    Write-Host "   If your dev server binds to '127.0.0.1' (IPv4) only, and your browser or API client asks for 'localhost',"
    Write-Host "   Windows resolves 'localhost' to '::1' (IPv6). Because the server isn't listening on ::1, you get ECONNREFUSED!"
    Write-Host "   -> $($global:Style.BrightGreen)Fix:$($global:Style.Reset) Explicitly connect to 'http://127.0.0.1:PORT' or bind server to '0.0.0.0' or dual-stack."
    Write-Host ""
    Write-Host "$($global:Style.Bold)$($global:Style.BrightYellow)2. Python 'http.server' IPv4-only Default:$($global:Style.Reset)"
    Write-Host "   Python's 'python -m http.server' uses TCPServer with AF_INET (IPv4 only) by default."
    Write-Host "   Visiting http://localhost:8000 may fail if the client prefers IPv6."
    Write-Host "   -> $($global:Style.BrightGreen)Fix:$($global:Style.Reset) Always test with http://127.0.0.1:8000 or use dual-stack server scripts."

    Write-Log -Level "INFO" -Module "IPV6" -Message "Completed IPv6 diagnostics."
    Pause-Console
}
