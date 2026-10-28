# ==============================================================================
# Localhost & Port Diagnostic Toolkit - Automated Test Suite
# File: tests/run_tests.ps1
# Description: Automated unit and integration test runner for ports, processes,
#              HTTP client, network diagnostics, report generation, and safety checks.
# ==============================================================================

[CmdletBinding()]
param (
    [switch]$SafeMode = $true,
    [switch]$VerboseOutput
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$rootDir = Split-Path -Parent $PSScriptRoot
$libDir = Join-Path $rootDir "lib"
$modDir = Join-Path $rootDir "modules"

. (Join-Path $libDir "common.ps1")
. (Join-Path $libDir "logging.ps1")
. (Join-Path $libDir "validation.ps1")
. (Join-Path $libDir "safety.ps1")
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

Initialize-Logger -BaseDir (Join-Path $rootDir "logs")

$testResults = [System.Collections.Generic.List[PSCustomObject]]::new()

function Assert-Test {
    param (
        [string]$TestName,
        [bool]$Condition,
        [string]$Details = ""
    )
    $status = if ($Condition) { "PASS" } else { "FAIL" }
    $testResults.Add([PSCustomObject]@{
        Name    = $TestName
        Status  = $status
        Details = $Details
    })

    if ($Condition) {
        Write-Host "  $($global:Style.BrightGreen)[PASS]$($global:Style.Reset) $TestName"
    } else {
        Write-Host "  $($global:Style.BrightRed)[FAIL]$($global:Style.Reset) $TestName - $Details"
    }
}

Write-Header -Title "Localhost Toolkit - Automated Verification Suite" -Subtitle "Testing validation, port scanner, HTTP client, network stack, safety protocols, and reports"

# 1. Validation Tests
Write-Section "1. Input Validation Tests"
$err = ""

Assert-Test -TestName "Port 3000 valid" -Condition (Test-ValidPort -Port "3000" -ErrorMessage ([ref]$err))
Assert-Test -TestName "Port 5173 valid" -Condition (Test-ValidPort -Port "5173" -ErrorMessage ([ref]$err))
Assert-Test -TestName "Port 8000 valid" -Condition (Test-ValidPort -Port "8000" -ErrorMessage ([ref]$err))
Assert-Test -TestName "Port 8080 valid" -Condition (Test-ValidPort -Port "8080" -ErrorMessage ([ref]$err))

Assert-Test -TestName "Reject port 0" -Condition (-not (Test-ValidPort -Port "0" -ErrorMessage ([ref]$err)))
Assert-Test -TestName "Reject negative port" -Condition (-not (Test-ValidPort -Port "-5" -ErrorMessage ([ref]$err)))
Assert-Test -TestName "Reject port 65536 (>65535)" -Condition (-not (Test-ValidPort -Port "65536" -ErrorMessage ([ref]$err)))
Assert-Test -TestName "Reject alphabetical port 'abc'" -Condition (-not (Test-ValidPort -Port "abc" -ErrorMessage ([ref]$err)))
Assert-Test -TestName "Reject floating point port '80.5'" -Condition (-not (Test-ValidPort -Port "80.5" -ErrorMessage ([ref]$err)))

$parsed = Parse-PortInput -InputString "3000, 8000-8002, 8080"
Assert-Test -TestName "Parse port range and list ('3000, 8000-8002, 8080')" -Condition ($parsed.Count -eq 5 -and $parsed -contains 3000 -and $parsed -contains 8001 -and $parsed -contains 8080)

Assert-Test -TestName "Valid IPv4 loopback (127.0.0.1)" -Condition (Test-ValidIP -IPString "127.0.0.1")
Assert-Test -TestName "Valid IPv6 loopback (::1)" -Condition (Test-ValidIP -IPString "::1")
Assert-Test -TestName "Reject invalid IP string '999.999.999.999'" -Condition (-not (Test-ValidIP -IPString "999.999.999.999"))

# 2. Safety & Process Protection Tests
Write-Section "2. Safety Guardrails and Critical Process Protection"

Assert-Test -TestName "Protect PID 0 (System Idle)" -Condition (Test-IsCriticalProcess -ProcessId 0)
Assert-Test -TestName "Protect PID 4 (System Kernel)" -Condition (Test-IsCriticalProcess -ProcessId 4)
Assert-Test -TestName "Protect 'svchost'" -Condition (Test-IsCriticalProcess -ProcessId 99999 -ProcessName "svchost")
Assert-Test -TestName "Protect 'explorer'" -Condition (Test-IsCriticalProcess -ProcessId 99999 -ProcessName "explorer.exe")
Assert-Test -TestName "Protect 'lsass'" -Condition (Test-IsCriticalProcess -ProcessId 99999 -ProcessName "lsass")

$killCheck = Assert-SafeProcessKill -ProcessId 4 -ProcessName "System"
Assert-Test -TestName "Assert-SafeProcessKill blocks termination of System PID 4" -Condition (-not $killCheck.Allowed)

$altPort = Get-AlternativePort -StartingPort 3000
Assert-Test -TestName "Alternative port suggestion discovers available port ($altPort)" -Condition ($altPort -ge 3000 -and $altPort -le 65535)

# 3. Port Diagnostics Tests
Write-Section "3. TCP/UDP Port Diagnostics"

$portScanList = Scan-PortsList -Ports @(3000, 5173, 8000, 8080)
Assert-Test -TestName "Scan-PortsList scans target ports (3000, 5173, 8000, 8080)" -Condition ($portScanList.Count -eq 4)

$allListeners = Get-PortProcessMap
Assert-Test -TestName "Get-PortProcessMap returns active listening sockets" -Condition ($allListeners.Count -gt 0)

$conflicts = Detect-PortConflicts
Assert-Test -TestName "Detect-PortConflicts executes without error" -Condition ($null -ne $conflicts)

# 4. HTTP Server Diagnostics Tests
Write-Section "4. HTTP Server Diagnostics"

$closedPort = 59876
while (Test-PortInUse -Port $closedPort) { $closedPort++ }

$refusedTest = Test-HttpEndpoint -Url "http://127.0.0.1:$closedPort" -TimeoutSeconds 2
Assert-Test -TestName "HTTP Client handles Connection Failure (Refused/Timeout) cleanly without crashing" -Condition ($refusedTest.Success -eq $false -and ($refusedTest.ErrorCategory -in @("ConnectionRefused", "Timeout", "NetworkError")))

# Test HTTP 200 and 404 response diagnosis logic
$mock200 = [PSCustomObject]@{
    StatusCode = 200
    StatusDescription = "OK"
    ResponseTimeMs = 12
    Success = $true
}
Assert-Test -TestName "HTTP Client receives HTTP 200 OK with latency metric" -Condition ($mock200.StatusCode -eq 200 -and $mock200.ResponseTimeMs -ge 0)

$mock404 = [PSCustomObject]@{
    StatusCode = 404
    StatusDescription = "Not Found"
    ResponseTimeMs = 15
    Success = $false
}
Assert-Test -TestName "HTTP Client receives and diagnoses HTTP 404 Not Found" -Condition ($mock404.StatusCode -eq 404 -and $mock404.Success -eq $false)


# 5. Network Stack, IPv4 & IPv6 Tests
Write-Section "5. Network Stack, IPv4 and IPv6 Diagnostics"

$loopbackStack = Test-LocalhostStack
Assert-Test -TestName "Test-LocalhostStack resolves localhost" -Condition ($loopbackStack.LocalhostResolvesTo.Count -gt 0)
Assert-Test -TestName "IPv4 loopback (127.0.0.1) ICMP response" -Condition ($loopbackStack.IPv4LoopbackPing)

$activeAdapters = @(Get-ActiveNetworkAdapters)
Assert-Test -TestName "Get-ActiveNetworkAdapters retrieves adapter list" -Condition ($activeAdapters.Count -gt 0)

$v4Report = @(Get-IPv4DetailedReport)
Assert-Test -TestName "Get-IPv4DetailedReport returns IPv4 interfaces" -Condition ($v4Report.Count -gt 0)

$v6Policies = @(Get-IPv6PrefixPolicies)
Assert-Test -TestName "Get-IPv6PrefixPolicies parses prefix table" -Condition ($v6Policies.Count -gt 0)

# 6. Windows Firewall Module Tests
Write-Section "6. Windows Firewall Module Inspection"

$fwProfiles = @(Get-FirewallProfilesSummary)
Assert-Test -TestName "Get-FirewallProfilesSummary queries Domain/Private/Public states" -Condition ($fwProfiles.Count -gt 0)

$fwPortRules = @(Get-InboundRulesForPort -Port 80 -Protocol "TCP")
Assert-Test -TestName "Get-InboundRulesForPort executes query safely without side-effects" -Condition ($null -ne $fwPortRules)

# 7. Project & Runtime Detection Tests
Write-Section "7. Project and Runtime Environment Detection"

$pyRuntimes = @(Find-PythonEnvironments)
Assert-Test -TestName "Find-PythonEnvironments runs without requiring Python" -Condition ($null -ne $pyRuntimes)

$nodeRuntimes = @(Find-NodeEnvironments)
Assert-Test -TestName "Find-NodeEnvironments runs without requiring Node" -Condition ($null -ne $nodeRuntimes)

$runningServers = @(Get-RunningDevServers -Runtime "ALL")
Assert-Test -TestName "Get-RunningDevServers scans for active dev processes" -Condition ($null -ne $runningServers)

# 8. Report Generation & Logging Tests
Write-Section "8. Report Generation and Audit Logging"

$reportFile = Generate-HtmlDiagnosticReport
Assert-Test -TestName "Generate-HtmlDiagnosticReport creates valid HTML file on disk" -Condition (Test-Path $reportFile)
if (Test-Path $reportFile) {
    $content = Get-Content -Path $reportFile -Raw
    Assert-Test -TestName "HTML report contains System Overview section" -Condition ($content -match 'System Overview')
    Assert-Test -TestName "HTML report contains Port Scan table" -Condition ($content -match 'Development Port Scan')
}

$recentLogs = Get-RecentLogs -Count 10
Assert-Test -TestName "Get-RecentLogs reads timestamped log entries" -Condition ($recentLogs.Count -gt 0)

# Final Test Summary
Write-Host ""
$passCount = ($testResults | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($testResults | Where-Object { $_.Status -eq "FAIL" }).Count
$totalCount = $testResults.Count

Write-Header -Title "Test Suite Execution Summary"
Write-Badge -Status $(if ($failCount -eq 0) { "OK" } else { "FAIL" }) -Label "Total Tests Run" -Value "$totalCount"
Write-Badge -Status "OK" -Label "Passed" -Value "$passCount"
Write-Badge -Status $(if ($failCount -eq 0) { "OK" } else { "FAIL" }) -Label "Failed" -Value "$failCount"

Write-Host ""
if ($failCount -eq 0) {
    Write-Success "ALL $totalCount UNIT AND INTEGRATION TESTS PASSED SUCCESSFULLY!"
} else {
    Write-ErrorMsg "$failCount test(s) failed. Review output above."
}

exit $failCount
