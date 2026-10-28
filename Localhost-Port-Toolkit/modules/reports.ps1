# ==============================================================================
# Localhost & Port Diagnostic Toolkit - Diagnostic Reporting Module
# File: modules/reports.ps1
# Description: Generates self-contained, responsive HTML5 diagnostic reports
#              with system overview, port scan tables, firewall status, and audit log.
# ==============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) "lib"
. (Join-Path $libDir "common.ps1")
. (Join-Path $libDir "logging.ps1")
. (Join-Path $libDir "validation.ps1")
. (Join-Path $libDir "safety.ps1")
. (Join-Path $PSScriptRoot "ports.ps1")
. (Join-Path $PSScriptRoot "network.ps1")
. (Join-Path $PSScriptRoot "firewall.ps1")
. (Join-Path $PSScriptRoot "ipv4.ps1")
. (Join-Path $PSScriptRoot "ipv6.ps1")
. (Join-Path $PSScriptRoot "projects.ps1")

function Generate-HtmlDiagnosticReport {
    param (
        [string]$OutputPath = ""
    )

    Write-Info "Gathering full diagnostic snapshot..."

    $sys = Get-SystemOverview
    $loopback = Test-LocalhostStack
    $adapters = Get-ActiveNetworkAdapters
    $fwProfiles = Get-FirewallProfilesSummary
    $config = Get-ToolkitConfig
    $portScan = Scan-PortsList -Ports $config.common_ports -ShowCommandLine
    $pyInstalls = Find-PythonEnvironments
    $nodeInstalls = Find-NodeEnvironments
    $runningDevServers = @(Get-RunningDevServers -Runtime "ALL")

    $toolkitRoot = Get-ToolkitRoot
    $reportsDir = Join-Path $toolkitRoot "reports"
    if (-not (Test-Path $reportsDir)) {
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
    }

    $timestampStr = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $defaultFilename = "diagnostic_report_$timestampStr.html"
    $reportFilePath = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        Join-Path $reportsDir $defaultFilename
    } else {
        $OutputPath
    }

    $portRows = ""
    foreach ($p in $portScan) {
        $statusClass = if ($p.Status -eq "IN USE") { "badge-inuse" } else { "badge-available" }
        $cmdCell = if ($p.CommandLine -and $p.CommandLine -ne "N/A" -and $p.CommandLine -ne "-") {
            [System.Web.HttpUtility]::HtmlEncode($p.CommandLine)
        } else { "-" }

        $portRows += @"
        <tr>
            <td><strong>$($p.Port)</strong></td>
            <td>$($p.Protocol)</td>
            <td>$($p.Address)</td>
            <td><span class="badge $statusClass">$($p.Status)</span></td>
            <td>$($p.PID)</td>
            <td>$([System.Web.HttpUtility]::HtmlEncode($p.Process))</td>
            <td>$([System.Web.HttpUtility]::HtmlEncode($p.Description))</td>
            <td class="cmd-cell"><code>$cmdCell</code></td>
        </tr>
"@
    }

    $adapterRows = ""
    foreach ($ad in $adapters) {
        $adapterRows += @"
        <tr>
            <td><strong>$([System.Web.HttpUtility]::HtmlEncode($ad.Name))</strong></td>
            <td>$([System.Web.HttpUtility]::HtmlEncode($ad.Description))</td>
            <td>$($ad.Type)</td>
            <td><code>$($ad.IPv4)</code></td>
            <td><code>$($ad.IPv6)</code></td>
            <td>$($ad.Gateway)</td>
        </tr>
"@
    }

    $fwCards = ""
    foreach ($fw in $fwProfiles) {
        $fwClass = if ($fw.Enabled) { "card-pass" } else { "card-warn" }
        $fwText = if ($fw.Enabled) { "ACTIVE (Enabled)" } else { "DISABLED" }
        $fwCards += @"
        <div class="card $fwClass">
            <h4>$($fw.Name) Profile</h4>
            <p><strong>Status:</strong> $fwText</p>
            <p><strong>Inbound:</strong> $($fw.DefaultInboundAction)</p>
            <p><strong>Outbound:</strong> $($fw.DefaultOutboundAction)</p>
        </div>
"@
    }

    $runtimeSummary = ""
    if ($pyInstalls.Count -gt 0) {
        $runtimeSummary += "<p><strong>Python:</strong> " + (($pyInstalls | ForEach-Object { "$($_.Command) ($($_.Version))" }) -join "; ") + "</p>"
    } else {
        $runtimeSummary += "<p><strong>Python:</strong> <span class='badge badge-warn'>Not detected in PATH</span></p>"
    }

    if ($nodeInstalls.Count -gt 0) {
        $runtimeSummary += "<p><strong>Node.js:</strong> " + (($nodeInstalls | ForEach-Object { "$($_.Command) ($($_.Version))" }) -join "; ") + "</p>"
    } else {
        $runtimeSummary += "<p><strong>Node.js:</strong> <span class='badge badge-warn'>Not detected in PATH</span></p>"
    }

    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Diagnostic Report - $($sys.Hostname)</title>
    <style>
        :root {
            --bg-color: #0f172a;
            --surface-color: #1e293b;
            --surface-hover: #334155;
            --primary: #38bdf8;
            --success: #22c55e;
            --warning: #f59e0b;
            --danger: #ef4444;
            --text-main: #f8fafc;
            --text-muted: #94a3b8;
            --border-color: #334155;
            --code-bg: #0b1120;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-main);
            line-height: 1.5;
            padding: 24px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        header {
            border-bottom: 2px solid var(--primary);
            padding-bottom: 16px;
            margin-bottom: 24px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
        }
        h1 { color: var(--primary); font-size: 1.8rem; }
        h2 { color: var(--text-main); font-size: 1.3rem; margin: 24px 0 12px 0; border-left: 4px solid var(--primary); padding-left: 10px; }
        .subtitle { color: var(--text-muted); font-size: 0.95rem; }
        .grid-cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
            gap: 16px;
            margin-bottom: 24px;
        }
        .card {
            background-color: var(--surface-color);
            border-radius: 8px;
            padding: 16px;
            border: 1px solid var(--border-color);
        }
        .card h4 { color: var(--primary); margin-bottom: 8px; font-size: 1.05rem; }
        .card p { font-size: 0.9rem; margin-bottom: 4px; color: var(--text-muted); }
        .card p strong { color: var(--text-main); }
        .card-pass { border-top: 3px solid var(--success); }
        .card-warn { border-top: 3px solid var(--warning); }
        .card-fail { border-top: 3px solid var(--danger); }
        table {
            width: 100%;
            border-collapse: collapse;
            background-color: var(--surface-color);
            border-radius: 8px;
            overflow: hidden;
            margin-bottom: 24px;
            border: 1px solid var(--border-color);
        }
        th, td {
            padding: 10px 14px;
            text-align: left;
            font-size: 0.88rem;
            border-bottom: 1px solid var(--border-color);
        }
        th {
            background-color: var(--surface-hover);
            color: var(--primary);
            font-weight: 600;
        }
        tr:hover { background-color: var(--surface-hover); }
        .badge {
            display: inline-block;
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 0.75rem;
            font-weight: bold;
            text-transform: uppercase;
        }
        .badge-available { background-color: rgba(34, 197, 94, 0.2); color: #4ade80; border: 1px solid #22c55e; }
        .badge-inuse { background-color: rgba(239, 68, 68, 0.2); color: #f87171; border: 1px solid #ef4444; }
        .badge-warn { background-color: rgba(245, 158, 11, 0.2); color: #fbbf24; border: 1px solid #f59e0b; }
        code {
            background-color: var(--code-bg);
            padding: 2px 6px;
            border-radius: 4px;
            font-family: Consolas, monospace;
            font-size: 0.82rem;
            color: #38bdf8;
        }
        .cmd-cell { max-width: 300px; word-break: break-all; }
        footer {
            margin-top: 40px;
            border-top: 1px solid var(--border-color);
            padding-top: 16px;
            color: var(--text-muted);
            font-size: 0.85rem;
            text-align: center;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <div>
                <h1>Localhost & Port Diagnostic Toolkit</h1>
                <p class="subtitle">Comprehensive Diagnostic Snapshot & Security Audit</p>
            </div>
            <div>
                <span class="badge badge-available">Engine v$($config.version)</span>
            </div>
        </header>

        <h2>System Overview</h2>
        <div class="grid-cards">
            <div class="card">
                <h4>Host Environment</h4>
                <p><strong>Host:</strong> $($sys.Hostname)</p>
                <p><strong>User:</strong> $($sys.User)</p>
                <p><strong>OS:</strong> $($sys.OSName)</p>
                <p><strong>Build / Arch:</strong> $($sys.OSBuild) ($($sys.OSArchitecture))</p>
                <p><strong>Admin Rights:</strong> $(if ($sys.IsAdmin) { '<span style="color:#22c55e">Elevated (Admin)</span>' } else { '<span style="color:#f59e0b">Standard User</span>' })</p>
                <p><strong>Generated:</strong> $($sys.Timestamp)</p>
            </div>
            <div class="card">
                <h4>Localhost Loopback</h4>
                <p><strong>IPv4 Loopback (127.0.0.1):</strong> $(if ($loopback.IPv4LoopbackPing) { '<span style="color:#22c55e">PASS</span>' } else { '<span style="color:#ef4444">FAIL</span>' })</p>
                <p><strong>IPv6 Loopback (::1):</strong> $(if ($loopback.IPv6LoopbackPing) { '<span style="color:#22c55e">PASS</span>' } else { '<span style="color:#f59e0b">WARN/INACTIVE</span>' })</p>
                <p><strong>localhost Resolves:</strong> $($loopback.LocalhostResolvesTo -join ', ')</p>
                <p><strong>Preferred Family:</strong> $($loopback.PreferredFamily)</p>
            </div>
            <div class="card">
                <h4>Development Runtimes</h4>
                $runtimeSummary
                <p><strong>Active Dev Servers:</strong> $($runningDevServers.Count) running</p>
            </div>
        </div>

        <h2>Windows Firewall Profiles</h2>
        <div class="grid-cards">
            $fwCards
        </div>

        <h2>Active Network Adapters (LAN)</h2>
        <table>
            <thead>
                <tr>
                    <th>Adapter</th>
                    <th>Description</th>
                    <th>Type</th>
                    <th>IPv4 Address</th>
                    <th>IPv6 Address</th>
                    <th>Default Gateway</th>
                </tr>
            </thead>
            <tbody>
                $adapterRows
            </tbody>
        </table>

        <h2>Development Port Scan (Common Web / Dev Ports)</h2>
        <table>
            <thead>
                <tr>
                    <th>Port</th>
                    <th>Proto</th>
                    <th>Address</th>
                    <th>Status</th>
                    <th>PID</th>
                    <th>Process</th>
                    <th>Standard Stack</th>
                    <th>Command Line</th>
                </tr>
            </thead>
            <tbody>
                $portRows
            </tbody>
        </table>

        <footer>
            Generated automatically by Windows Localhost & Port Diagnostic Toolkit &bull; Safe Non-Destructive Inspection
        </footer>
    </div>
</body>
</html>
"@

    Set-Content -Path $reportFilePath -Value $htmlContent -Encoding utf8
    Write-Success "Diagnostic HTML report generated successfully at:"
    Write-Host "  $reportFilePath" -ForegroundColor Cyan
    Write-Log -Level "INFO" -Module "REPORT" -Message "Report generated: $reportFilePath"

    return $reportFilePath
}

function Show-ReportGeneratorUI {
    Clear-Host
    Write-Header -Title "Generate Comprehensive Diagnostic Report" -Subtitle "Export an offline, responsive HTML5 diagnostic report"

    Write-Info "Compiling system diagnostics, port scans, firewall rules, and network status..."
    $reportPath = Generate-HtmlDiagnosticReport

    Write-Host ""
    Write-Styled "Would you like to open the report in your default browser now? (Y/N): " -Color "Yellow" -NoNewline
    $openChoice = [System.Console]::ReadLine().Trim()

    if ($openChoice -eq "Y" -or $openChoice -eq "y") {
        try {
            Start-Process $reportPath
            Write-Success "Opened report in web browser."
        } catch {
            Write-Warning "Could not automatically launch browser: $_"
        }
    }

    Pause-Console
}
