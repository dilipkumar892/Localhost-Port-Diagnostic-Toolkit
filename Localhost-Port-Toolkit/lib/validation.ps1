# ==============================================================================
# Localhost & Port Diagnostic Toolkit - Validation Library
# File: lib/validation.ps1
# Description: Input validation for ports, ranges, IP addresses, URLs, and paths
# ==============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

function Test-ValidPort {
    param (
        [Parameter(Mandatory = $true)]
        $Port,
        [ref]$ErrorMessage
    )

    $portStr = "$Port".Trim()

    if ($portStr -notmatch '^\d+$') {
        if ($ErrorMessage) { $ErrorMessage.Value = "Port '$Port' is not a valid positive integer." }
        return $false
    }

    [int]$portNum = 0
    if (-not [int]::TryParse($portStr, [ref]$portNum)) {
        if ($ErrorMessage) { $ErrorMessage.Value = "Port '$Port' could not be parsed as an integer." }
        return $false
    }

    if ($portNum -lt 1 -or $portNum -gt 65535) {
        if ($ErrorMessage) { $ErrorMessage.Value = "Port $portNum is out of valid range (1 - 65535)." }
        return $false
    }

    return $true
}

function Parse-PortInput {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputString
    )

    $resultPorts = [System.Collections.Generic.List[int]]::new()
    $tokens = $InputString -split '[,;\s]+'

    foreach ($token in $tokens) {
        $clean = $token.Trim()
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }

        if ($clean -match '^(\d+)-(\d+)$') {
            [int]$start = [int]$matches[1]
            [int]$end = [int]$matches[2]

            if ($start -gt $end) {
                $temp = $start
                $start = $end
                $end = $temp
            }

            if ($start -ge 1 -and $end -le 65535) {
                if (($end - $start) -gt 500) {
                    $end = $start + 500
                }
                for ($p = $start; $p -le $end; $p++) {
                    if (-not $resultPorts.Contains($p)) { $resultPorts.Add($p) }
                }
            }
        }
        else {
            $err = ""
            if (Test-ValidPort -Port $clean -ErrorMessage ([ref]$err)) {
                [int]$p = [int]$clean
                if (-not $resultPorts.Contains($p)) { $resultPorts.Add($p) }
            }
        }
    }

    return ($resultPorts | Sort-Object)
}

function Test-ValidIP {
    param (
        [Parameter(Mandatory = $true)]
        [string]$IPString
    )

    $clean = $IPString.Trim()
    [System.Net.IPAddress]$parsed = $null
    return [System.Net.IPAddress]::TryParse($clean, [ref]$parsed)
}

function Test-ValidUrl {
    param (
        [Parameter(Mandatory = $true)]
        [string]$UrlString
    )

    $clean = $UrlString.Trim()
    if ($clean -notmatch '^https?://') {
        $clean = "http://$clean"
    }

    [System.Uri]$uri = $null
    $valid = [System.Uri]::TryCreate($clean, [System.UriKind]::Absolute, [ref]$uri)
    if ($valid -and ($uri.Scheme -eq 'http' -or $uri.Scheme -eq 'https')) {
        return $true
    }
    return $false
}

function Test-ValidDirectory {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        return (Test-Path -Path $Path -PathType Container)
    }
    catch {
        return $false
    }
}
