# ==============================================================================
# Localhost & Port Diagnostic Toolkit - Project & Runtime Diagnostics Module
# File: modules/projects.ps1
# Description: Detects Python and Node.js installations, active development
#              servers, virtual environments, frameworks, and project configurations.
# ==============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) "lib"
. (Join-Path $libDir "common.ps1")
. (Join-Path $libDir "logging.ps1")
. (Join-Path $libDir "validation.ps1")
. (Join-Path $PSScriptRoot "ports.ps1")

function Find-PythonEnvironments {
    $installations = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        $pyCmd = Get-Command "py" -ErrorAction SilentlyContinue
        if ($pyCmd) {
            $ver = (py --version 2>&1).ToString().Trim()
            $installations.Add([PSCustomObject]@{
                Command = "py"
                Path    = $pyCmd.Source
                Version = $ver
                Type    = "Python Launcher for Windows"
            })
        }
    } catch {}

    try {
        $pythonCmd = Get-Command "python" -ErrorAction SilentlyContinue
        if ($pythonCmd) {
            $ver = (python --version 2>&1).ToString().Trim()
            $installations.Add([PSCustomObject]@{
                Command = "python"
                Path    = $pythonCmd.Source
                Version = $ver
                Type    = "System/User PATH"
            })
        }
    } catch {}

    try {
        $python3Cmd = Get-Command "python3" -ErrorAction SilentlyContinue
        if ($python3Cmd -and ($null -eq $pythonCmd -or $python3Cmd.Source -ne $pythonCmd.Source)) {
            $ver = (python3 --version 2>&1).ToString().Trim()
            $installations.Add([PSCustomObject]@{
                Command = "python3"
                Path    = $python3Cmd.Source
                Version = $ver
                Type    = "System/User PATH"
            })
        }
    } catch {}

    return $installations
}

function Find-NodeEnvironments {
    $installations = [System.Collections.Generic.List[PSCustomObject]]::new()

    try {
        $nodeCmd = Get-Command "node" -ErrorAction SilentlyContinue
        if ($nodeCmd) {
            $ver = (node --version 2>&1).ToString().Trim()
            $installations.Add([PSCustomObject]@{
                Command = "node"
                Path    = $nodeCmd.Source
                Version = $ver
                Type    = "Node.js Runtime"
            })
        }
    } catch {}

    try {
        $npmCmd = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
        if (-not $npmCmd) { $npmCmd = Get-Command "npm" -ErrorAction SilentlyContinue }
        if ($npmCmd) {
            $ver = (npm --version 2>&1).ToString().Trim()
            $installations.Add([PSCustomObject]@{
                Command = "npm"
                Path    = $npmCmd.Source
                Version = "v$ver"
                Type    = "Node Package Manager"
            })
        }
    } catch {}

    try {
        $npxCmd = Get-Command "npx.cmd" -ErrorAction SilentlyContinue
        if ($npxCmd) {
            $installations.Add([PSCustomObject]@{
                Command = "npx"
                Path    = $npxCmd.Source
                Version = "Installed"
                Type    = "Node Package Runner"
            })
        }
    } catch {}

    return $installations
}

function Get-RunningDevServers {
    param ([string]$Runtime = "ALL")

    $activeProcesses = Get-PortProcessMap -IncludeUDP
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($entry in $activeProcesses) {
        $pName = $entry.ProcessName.ToLower()
        $isPython = ($pName -match 'python|uvicorn|gunicorn')
        $isNode = ($pName -match 'node|vite|next-server|electron')

        if ($Runtime -eq "PYTHON" -and -not $isPython) { continue }
        if ($Runtime -eq "NODE" -and -not $isNode) { continue }
        if ($Runtime -eq "ALL" -and -not ($isPython -or $isNode)) { continue }

        $cmdLine = Get-ProcessCommandLineSafe -PID $entry.PID

        $runtimeType = if ($isPython) { "Python" } elseif ($isNode) { "Node.js" } else { "Other" }

        $framework = "Generic HTTP"
        if ($cmdLine -match 'manage\.py\s+runserver') { $framework = "Django Dev Server" }
        elseif ($cmdLine -match 'http\.server') { $framework = "Python Simple HTTP Server" }
        elseif ($cmdLine -match 'uvicorn') { $framework = "Uvicorn (FastAPI/Starlette)" }
        elseif ($cmdLine -match 'flask\s+run') { $framework = "Flask Dev Server" }
        elseif ($cmdLine -match 'vite') { $framework = "Vite Dev Server" }
        elseif ($cmdLine -match 'next') { $framework = "Next.js SSR/Dev Server" }
        elseif ($cmdLine -match 'react-scripts') { $framework = "Create React App" }

        $results.Add([PSCustomObject]@{
            Runtime      = $runtimeType
            Framework    = $framework
            PID          = $entry.PID
            ProcessName  = $entry.ProcessName
            Port         = $entry.LocalPort
            LocalAddress = $entry.LocalAddress
            CommandLine  = $cmdLine
        })
    }

    return ,@($results.ToArray())
}

function Show-PythonDiagnosticsUI {
    Clear-Host
    Write-Header -Title "Python Development Server Diagnostics" -Subtitle "Detect Python runtimes, examine active Python servers, and inspect bind addresses"

    Write-Info "Searching for Python installations on this machine..."
    $pyInstalls = Find-PythonEnvironments

    Write-Host ""
    Write-Section "Installed Python Environments"
    if ($pyInstalls.Count -eq 0) {
        Write-Warning "No Python installation was found in system PATH or Windows Registry."
        Write-Host "  To install Python, visit: https://www.python.org/downloads/ or run 'winget install Python.Python.3.12'" -ForegroundColor Gray
    } else {
        foreach ($inst in $pyInstalls) {
            Write-Badge -Status "OK" -Label "$($inst.Command) ($($inst.Type))" -Value "$($inst.Version) [Path: $($inst.Path)]"
        }
    }

    Write-Host ""
    Write-Section "Active Python Development Servers"
    $running = Get-RunningDevServers -Runtime "PYTHON"

    if ($running.Count -eq 0) {
        Write-Host "No active Python development servers are currently listening on any network port." -ForegroundColor Gray
    } else {
        Write-Success "Found $($running.Count) active Python server process(es):"
        foreach ($srv in $running) {
            Write-Host ""
            Write-Host "$($global:Style.Bold)$($global:Style.BrightCyan)[$($srv.Framework)] PID: $($srv.PID) on Port $($srv.Port)$($global:Style.Reset)"
            Write-Badge -Status "INFO" -Label "Binding Address" -Value "$($srv.LocalAddress):$($srv.Port)"
            Write-Badge -Status "INFO" -Label "Command Line" -Value "$($srv.CommandLine)"

            if ($srv.LocalAddress -eq "127.0.0.1") {
                Write-Host "  Note: Server bound exclusively to 127.0.0.1 (IPv4). Inaccessible to LAN peers and mobile devices." -ForegroundColor Gray
            } elseif ($srv.LocalAddress -in @("0.0.0.0", "::")) {
                Write-Host "  Note: Server bound to all network interfaces. Reachable from LAN devices." -ForegroundColor Green
            }
        }
    }

    Write-Log -Level "INFO" -Module "PYTHON" -Message "Completed Python diagnostics. Found $($pyInstalls.Count) installs, $($running.Count) running servers."
    Pause-Console
}

function Show-NodeDiagnosticsUI {
    Clear-Host
    Write-Header -Title "Node.js / npm Development Server Diagnostics" -Subtitle "Detect Node/npm runtimes, inspect active web servers, and diagnose dev scripts"

    Write-Info "Searching for Node.js and npm in system environment..."
    $nodeInstalls = Find-NodeEnvironments

    Write-Host ""
    Write-Section "Installed Node.js Environments"
    if ($nodeInstalls.Count -eq 0) {
        Write-Warning "Node.js or npm was not found in system PATH."
        Write-Host "  To install Node.js, visit: https://nodejs.org/ or run 'winget install OpenJS.NodeJS.LTS'" -ForegroundColor Gray
    } else {
        foreach ($inst in $nodeInstalls) {
            Write-Badge -Status "OK" -Label "$($inst.Command) ($($inst.Type))" -Value "$($inst.Version) [Path: $($inst.Path)]"
        }
    }

    Write-Host ""
    Write-Section "Active Node.js Development Servers"
    $running = Get-RunningDevServers -Runtime "NODE"

    if ($running.Count -eq 0) {
        Write-Host "No active Node.js / npm dev servers are currently listening on any network port." -ForegroundColor Gray
    } else {
        Write-Success "Found $($running.Count) active Node.js server process(es):"
        foreach ($srv in $running) {
            Write-Host ""
            Write-Host "$($global:Style.Bold)$($global:Style.BrightCyan)[$($srv.Framework)] PID: $($srv.PID) on Port $($srv.Port)$($global:Style.Reset)"
            Write-Badge -Status "INFO" -Label "Binding Address" -Value "$($srv.LocalAddress):$($srv.Port)"
            Write-Badge -Status "INFO" -Label "Command Line" -Value "$($srv.CommandLine)"

            if ($srv.LocalAddress -eq "127.0.0.1") {
                Write-Host "  Note: Server bound exclusively to 127.0.0.1 (IPv4). Inaccessible to mobile devices on Wi-Fi." -ForegroundColor Gray
            } elseif ($srv.LocalAddress -in @("0.0.0.0", "::")) {
                Write-Host "  Note: Server bound to all network interfaces. Reachable from LAN devices." -ForegroundColor Green
            }
        }
    }

    Write-Log -Level "INFO" -Module "NODE" -Message "Completed Node.js diagnostics. Found $($nodeInstalls.Count) installs, $($running.Count) running servers."
    Pause-Console
}
