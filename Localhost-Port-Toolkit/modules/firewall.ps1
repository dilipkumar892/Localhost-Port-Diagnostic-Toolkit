# ==============================================================================
# Localhost & Port Diagnostic Toolkit - Windows Firewall Module
# File: modules/firewall.ps1
# Description: Windows Firewall status inspection, dev port rules analysis,
#              and safe scoped firewall rule creation with explicit confirmation.
# ==============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) "lib"
. (Join-Path $libDir "common.ps1")
. (Join-Path $libDir "logging.ps1")
. (Join-Path $libDir "validation.ps1")
. (Join-Path $libDir "safety.ps1")

function Get-FirewallProfilesSummary {
    $profiles = [System.Collections.Generic.List[PSCustomObject]]::new()
    try {
        $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($p in $fwProfiles) {
            $profiles.Add([PSCustomObject]@{
                Name                  = $p.Name
                Enabled               = $p.Enabled
                DefaultInboundAction  = $p.DefaultInboundAction
                DefaultOutboundAction = $p.DefaultOutboundAction
            })
        }
    }
    catch {
        Write-Log -Level "WARN" -Module "FIREWALL" -Message "Get-NetFirewallProfile failed. Falling back to netsh advfirewall."
        $netshOut = netsh advfirewall show allprofiles
        $currProfile = "Unknown"
        foreach ($line in $netshOut) {
            if ($line -match 'Profile Settings:') {
                $currProfile = ($line -split 'Profile Settings:')[0].Trim()
            }
            if ($line -match 'State\s+ON') {
                $profiles.Add([PSCustomObject]@{
                    Name                  = $currProfile
                    Enabled               = $true
                    DefaultInboundAction  = "Block"
                    DefaultOutboundAction = "Allow"
                })
            }
        }
    }
    return $profiles
}

function Get-InboundRulesForPort {
    param (
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [string]$Protocol = "TCP"
    )

    $matchingRules = [System.Collections.Generic.List[PSCustomObject]]::new()
    try {
        $rules = Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction Stop
        foreach ($rule in $rules) {
            $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
            if ($portFilter -and ($portFilter.Protocol -eq $Protocol -or $portFilter.Protocol -eq "Any")) {
                $localPorts = $portFilter.LocalPort
                if ($localPorts -contains [string]$Port -or $localPorts -contains "Any") {
                    $matchingRules.Add([PSCustomObject]@{
                        DisplayName = $rule.DisplayName
                        Action      = $rule.Action
                        Profiles    = ($rule.Profile.ToString())
                        Protocol    = $portFilter.Protocol
                        LocalPort   = ($portFilter.LocalPort -join ", ")
                        RuleName    = $rule.Name
                    })
                }
            }
        }
    }
    catch {
        Write-Log -Level "WARN" -Module "FIREWALL" -Message "Get-NetFirewallRule failed: $_"
    }

    return ,@($matchingRules.ToArray())
}

function Add-SafeDevFirewallRule {
    param (
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [string]$Protocol = "TCP",
        [string]$Profile = "Private"
    )

    if (-not (Test-IsAdmin)) {
        Write-ErrorMsg "Elevation Required: Adding a firewall rule requires running PowerShell/Toolkit as Administrator."
        return $false
    }

    Write-Host ""
    Write-Section "FIREWALL RULE CREATION SAFEGUARD"
    Write-Host "You are about to allow inbound network traffic on:" -ForegroundColor Yellow
    Write-Host "  - Port: $Port ($Protocol)"
    Write-Host "  - Profile: $Profile (Restricted to Private/Home/Work networks. Public Wi-Fi remains protected!)"
    Write-Host "  - Direction: Inbound"
    Write-Host "  - Action: Allow"
    Write-Host ""
    Write-Host "Notice: Windows Firewall will NOT be disabled. Only this single port on private networks is opened." -ForegroundColor Cyan

    $confirmed = Confirm-Action `
        -PromptMessage "Do you confirm creating this scoped inbound firewall rule?" `
        -ExpectedConfirmation "ALLOW" `
        -WarningDetails "Never allow unknown ports on untrusted networks."

    if (-not $confirmed) {
        Write-Info "Firewall rule creation cancelled by user."
        return $false
    }

    $ruleName = "LocalhostToolkit-Dev-$Protocol-$Port"
    $displayName = "Localhost Diagnostic Toolkit - Dev Port $Port ($Protocol)"

    try {
        $existing = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
        if ($existing) {
            Remove-NetFirewallRule -Name $ruleName -ErrorAction Stop
        }

        New-NetFirewallRule `
            -Name $ruleName `
            -DisplayName $displayName `
            -Description "Created by Localhost & Port Diagnostic Toolkit for local web development testing on Private LAN." `
            -Direction Inbound `
            -Action Allow `
            -Protocol $Protocol `
            -LocalPort $Port `
            -Profile $Profile `
            -ErrorAction Stop | Out-Null

        Write-Success "Inbound firewall rule successfully created and enabled for Port $Port ($Profile profile)."
        Write-Log -Level "INFO" -Module "FIREWALL" -Message "Created inbound rule '$ruleName' for port $Port ($Protocol, $Profile)."
        return $true
    }
    catch {
        Write-ErrorMsg "Failed to create firewall rule: $_"
        Write-Log -Level "ERROR" -Module "FIREWALL" -Message "Failed to create rule: $_"
        return $false
    }
}

function Show-FirewallDiagnosticsUI {
    Clear-Host
    Write-Header -Title "Windows Firewall Diagnostics" -Subtitle "Inspect profile states, verify inbound dev rules, and audit network boundaries"

    $isAdmin = Test-IsAdmin
    if (-not $isAdmin) {
        Write-Warning "Running in non-elevated user mode. Diagnostic inspection is fully supported, but rule creation requires Administrator privileges."
    }

    Write-Info "Inspecting Windows Firewall profile status..."
    $profiles = Get-FirewallProfilesSummary

    Write-Host ""
    Write-Section "Windows Firewall Profile Status"
    foreach ($p in $profiles) {
        $stateTag = if ($p.Enabled) { "OK" } else { "WARN" }
        $stateText = if ($p.Enabled) { "ACTIVE (Enabled)" } else { "DISABLED (Exposed!)" }
        Write-Badge -Status $stateTag -Label "$($p.Name) Profile" -Value "$stateText | Inbound: $($p.DefaultInboundAction)"
    }

    Write-Host ""
    Write-Section "Port Inbound Rule Inspection"
    Write-Styled "Enter a port number to check firewall rules (e.g. 3000, 5173, 8000, 8080): " -Color "Yellow" -NoNewline
    $portStr = [System.Console]::ReadLine().Trim()

    if ($portStr -match '^\d+$') {
        [int]$port = [int]$portStr
        Write-Info "Querying active inbound rules for TCP port $port..."
        $matching = Get-InboundRulesForPort -Port $port -Protocol "TCP"

        if ($matching.Count -gt 0) {
            Write-Host ""
            Write-Success ("Found {0} matching inbound rule(s) for Port {1}:" -f $matching.Count, $port)
            foreach ($r in $matching) {
                Write-Host "  - Rule: $($r.DisplayName)" -ForegroundColor Cyan
                Write-Host "    Action: $($r.Action) | Profiles: $($r.Profiles) | LocalPort: $($r.LocalPort)" -ForegroundColor Gray
            }
        } else {
            Write-Host ""
            Write-Warning "NO explicit inbound firewall rule found for Port $port."
            Write-Host "  - Localhost (127.0.0.1) connections: Windows automatically allows loopback, so this port works locally." -ForegroundColor Gray
            Write-Host "  - LAN / Remote devices (192.168.x.x): Traffic will be BLOCKED by the default inbound policy!" -ForegroundColor Yellow

            if ($isAdmin) {
                Write-Host ""
                Write-Host "Would you like to safely add a scoped inbound rule for this port on Private networks?"
                Write-Styled "Open rule wizard? (Y/N): " -Color "Yellow" -NoNewline
                $wz = [System.Console]::ReadLine().Trim()
                if ($wz -eq "Y" -or $wz -eq "y") {
                    Add-SafeDevFirewallRule -Port $port -Protocol "TCP" -Profile "Private"
                }
            } else {
                Write-Host "  To allow LAN access, rerun this toolkit as Administrator to create a scoped Private rule." -ForegroundColor Gray
            }
        }
    }

    Write-Log -Level "INFO" -Module "FIREWALL" -Message "Firewall diagnostics completed."
    Pause-Console
}
