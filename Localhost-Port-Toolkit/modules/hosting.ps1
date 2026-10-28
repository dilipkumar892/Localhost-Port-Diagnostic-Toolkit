# ==============================================================================
# Localhost & Port Diagnostic Toolkit - Project Hosting Assistant Module
# File: modules/hosting.ps1
# Description: Interactive guided hosting for Python, Node.js, and static sites
#              with safe verification, port pre-flight checks, and confirmation.
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

function Analyze-ProjectDirectory {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $analysis = [PSCustomObject]@{
        Path           = $Path
        Type           = "Unknown"
        Framework      = "None"
        SuggestedPort  = 8000
        RecommendedCmd = ""
        PackageScripts = @()
        ConfigFiles    = @()
    }

    if (-not (Test-Path $Path)) {
        return $analysis
    }

    $files = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name

    if ($files -contains "package.json") {
        $analysis.Type = "Node.js"
        $analysis.SuggestedPort = 3000
        $analysis.RecommendedCmd = "npm run dev -- --host 0.0.0.0"
        $analysis.ConfigFiles += "package.json"

        if ($files -match 'vite\.config') {
            $analysis.Framework = "Vite"
            $analysis.SuggestedPort = 5173
            $analysis.RecommendedCmd = "npx vite --host 0.0.0.0"
        } elseif ($files -match 'next\.config') {
            $analysis.Framework = "Next.js"
            $analysis.SuggestedPort = 3000
            $analysis.RecommendedCmd = "npx next dev -H 0.0.0.0 -p 3000"
        } elseif ($files -match 'angular\.json') {
            $analysis.Framework = "Angular"
            $analysis.SuggestedPort = 4200
            $analysis.RecommendedCmd = "npx ng serve --host 0.0.0.0"
        } else {
            $analysis.Framework = "Standard Node / npm"
        }

        try {
            $pkgJson = Get-Content -Path (Join-Path $Path "package.json") -Raw | ConvertFrom-Json
            if ($pkgJson.scripts) {
                foreach ($prop in $pkgJson.scripts.PSObject.Properties) {
                    $analysis.PackageScripts += "$($prop.Name): $($prop.Value)"
                }
            }
        } catch {}
    }
    elseif ($files -contains "manage.py") {
        $analysis.Type = "Python"
        $analysis.Framework = "Django"
        $analysis.SuggestedPort = 8000
        $analysis.RecommendedCmd = "python manage.py runserver 0.0.0.0:8000"
        $analysis.ConfigFiles += "manage.py"
    } elseif ($files -match '^(app|main|server)\.py$' -or $files -contains "requirements.txt" -or $files -contains "pyproject.toml") {
        $analysis.Type = "Python"
        $analysis.Framework = "Python Web / API"
        $analysis.SuggestedPort = 8000
        $analysis.RecommendedCmd = "python -m http.server 8000 --bind 0.0.0.0"
        if ($files -contains "requirements.txt") { $analysis.ConfigFiles += "requirements.txt" }
        if ($files -contains "pyproject.toml") { $analysis.ConfigFiles += "pyproject.toml" }
    }
    elseif ($files -contains "index.html") {
        $analysis.Type = "Static Web"
        $analysis.Framework = "HTML5 / CSS / JS"
        $analysis.SuggestedPort = 8000
        $analysis.RecommendedCmd = "python -m http.server 8000 --bind 0.0.0.0"
        $analysis.ConfigFiles += "index.html"
    }

    return $analysis
}

function Show-HostingAssistantUI {
    Clear-Host
    Write-Header -Title "Project Hosting Assistant" -Subtitle "Safely configure and launch local development servers for localhost and LAN access"

    Explain-BindAddressRisk

    Write-Host "Select project directory:"
    $currentDir = (Get-Location).Path
    Write-Host "  [1] Current Directory: $currentDir"
    Write-Host "  [2] Specify Custom Path"
    Write-Host "  [B] Back to Main Menu"
    Write-Host ""
    Write-Styled "Enter choice: " -Color "Yellow" -NoNewline
    $dirChoice = [System.Console]::ReadLine().Trim()

    $targetPath = $currentDir
    switch ($dirChoice) {
        "1" { $targetPath = $currentDir }
        "2" {
            Write-Styled "Enter absolute folder path: " -Color "Cyan" -NoNewline
            $customPath = [System.Console]::ReadLine().Trim()
            if (-not (Test-ValidDirectory -Path $customPath)) {
                Write-ErrorMsg "Directory does not exist or is inaccessible: $customPath"
                Pause-Console
                return
            }
            $targetPath = $customPath
        }
        default { return }
    }

    Write-Info "Analyzing project files in '$targetPath'..."
    $proj = Analyze-ProjectDirectory -Path $targetPath

    Write-Host ""
    Write-Section "Project Analysis Result"
    Write-Badge -Status "INFO" -Label "Working Directory" -Value "$($proj.Path)"
    Write-Badge -Status "INFO" -Label "Detected Project Type" -Value "$($proj.Type)"
    Write-Badge -Status "INFO" -Label "Framework / Stack" -Value "$($proj.Framework)"
    Write-Badge -Status "INFO" -Label "Config Markers" -Value $(if ($proj.ConfigFiles.Count -gt 0) { $proj.ConfigFiles -join ", " } else { "None" })

    if ($proj.PackageScripts.Count -gt 0) {
        Write-Host ""
        Write-Host "Available npm package scripts:" -ForegroundColor Gray
        foreach ($s in ($proj.PackageScripts | Select-Object -First 5)) {
            Write-Host "  - $s" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Section "Hosting Configuration"
    Write-Host "Choose binding address:"
    Write-Host "  [1] Localhost Only (127.0.0.1) - $($global:Style.BrightGreen)Safest$($global:Style.Reset). Accessible only from this computer."
    Write-Host "  [2] LAN & Localhost (0.0.0.0)  - $($global:Style.BrightYellow)Exposes to LAN$($global:Style.Reset). Accessible from phones and other devices on Wi-Fi."
    Write-Styled "Selection (1/2): " -Color "Yellow" -NoNewline
    $bindChoice = [System.Console]::ReadLine().Trim()

    $bindAddress = if ($bindChoice -eq "2") { "0.0.0.0" } else { "127.0.0.1" }

    Write-Styled "Select port to host on [Default: $($proj.SuggestedPort)]: " -Color "Yellow" -NoNewline
    $userPort = [System.Console]::ReadLine().Trim()
    $finalPort = if ($userPort -match '^\d+$') { [int]$userPort } else { $proj.SuggestedPort }

    Write-Info "Performing pre-flight check on Port $finalPort..."
    $inUse = Test-PortInUse -Port $finalPort -Protocol "TCP"
    if ($inUse) {
        Write-Warning "PRE-FLIGHT WARNING: Port $finalPort is ALREADY IN USE by another process!"
        $altPort = Get-AlternativePort -StartingPort ($finalPort + 1)
        Write-Host "  Suggested available port: $altPort" -ForegroundColor Cyan
        Write-Styled "Switch to port $altPort? (Y/N): " -Color "Yellow" -NoNewline
        $switchChoice = [System.Console]::ReadLine().Trim()
        if ($switchChoice -eq "Y" -or $switchChoice -eq "y") {
            $finalPort = $altPort
        } else {
            Write-Warning "Continuing with occupied port may result in EADDRINUSE crash."
        }
    } else {
        Write-Success "Port $finalPort is FREE and ready for binding."
    }

    $commandToRun = ""
    if ($proj.Type -eq "Python" -or $proj.Type -eq "Static Web") {
        $commandToRun = "python -m http.server $finalPort --bind $bindAddress"
    } elseif ($proj.Type -eq "Node.js") {
        if ($bindAddress -eq "0.0.0.0") {
            $commandToRun = "npm run dev -- --host 0.0.0.0 --port $finalPort"
        } else {
            $commandToRun = "npm run dev -- --port $finalPort"
        }
    } else {
        $commandToRun = "python -m http.server $finalPort --bind $bindAddress"
    }

    Write-Host ""
    Write-Section "PRE-EXECUTION REVIEW & SAFETY CONFIRMATION"
    Write-Host "  Working Directory: $($proj.Path)" -ForegroundColor Cyan
    Write-Host "  Target Port:       $finalPort" -ForegroundColor Cyan
    Write-Host "  Binding Interface: $bindAddress $(if ($bindAddress -eq '0.0.0.0') { '[EXPOSED TO LOCAL NETWORK]' } else { '[LOCAL ONLY]' })" -ForegroundColor Yellow
    Write-Host "  Exact Command:     $($global:Style.Bold)$($global:Style.BrightGreen)$commandToRun$($global:Style.Reset)"
    Write-Host ""
    Write-Host "Notice: The toolkit will never silently alter your files. The server will launch in a dedicated console window." -ForegroundColor Gray

    $confirmed = Confirm-Action `
        -PromptMessage "Do you wish to launch this server now?" `
        -ExpectedConfirmation "RUN"

    if ($confirmed) {
        try {
            Write-Info "Spawning development server..."
            Start-Process -FilePath "cmd.exe" -ArgumentList "/k title Dev Server: Port $finalPort && cd /d `"$($proj.Path)`" && $commandToRun" -WorkingDirectory $proj.Path
            Write-Success "Server process launched in separate console window."
            Write-Log -Level "INFO" -Module "HOSTING" -Message "Launched '$commandToRun' in '$($proj.Path)'."

            Write-Host ""
            Write-Host "$($global:Style.Bold)$($global:Style.BrightCyan)ACCESS YOUR SERVER AT:$($global:Style.Reset)"
            Write-Host "  -> Localhost:  http://localhost:$finalPort/ or http://127.0.0.1:$finalPort/" -ForegroundColor Green
            if ($bindAddress -eq "0.0.0.0") {
                $adapters = Get-ActiveNetworkAdapters
                foreach ($ad in $adapters) {
                    if ($ad.IPv4 -ne "None") {
                        $ips = $ad.IPv4 -split ',\s*'
                        foreach ($ip in $ips) {
                            if ($ip -notmatch '^169\.254') {
                                Write-Host "  -> LAN Device: http://${ip}:$finalPort/ ($($ad.Name))" -ForegroundColor Yellow
                            }
                        }
                    }
                }
            }
        }
        catch {
            Write-ErrorMsg "Failed to launch server process: $_"
            Write-Log -Level "ERROR" -Module "HOSTING" -Message "Failed to start server: $_"
        }
    } else {
        Write-Info "Launch cancelled by user."
    }

    Pause-Console
}
