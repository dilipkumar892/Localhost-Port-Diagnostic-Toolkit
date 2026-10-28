# ==============================================================================
# Localhost & Port Diagnostic Toolkit - HTTP/HTTPS Diagnostics Module
# File: modules/http.ps1
# Description: HTTP/HTTPS requests, status code analysis, response times,
#              headers, redirects, TLS certificate checks, and error root causes.
# ==============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) "lib"
. (Join-Path $libDir "common.ps1")
. (Join-Path $libDir "logging.ps1")
. (Join-Path $libDir "validation.ps1")

function Explain-HttpError {
    param (
        [string]$ErrorCategory,
        [int]$StatusCode = 0,
        [string]$RawMessage = ""
    )

    Write-Host ""
    Write-Host "$($global:Style.Bold)$($global:Style.BrightCyan)DIAGNOSTIC EXPLANATION AND TROUBLESHOOTING:$($global:Style.Reset)"

    if ($StatusCode -eq 404) {
        Write-Host "  $($global:Style.BrightYellow)HTTP 404 Not Found:$($global:Style.Reset)"
        Write-Host "  - The server received the request and is running correctly."
        Write-Host "  - However, no route, file, or controller matches the requested URI."
        Write-Host "  - Action: Check URL spelling, router definitions, static directory configuration, or base paths."
        return
    }

    if ($StatusCode -eq 403) {
        Write-Host "  $($global:Style.BrightYellow)HTTP 403 Forbidden:$($global:Style.Reset)"
        Write-Host "  - The server understands the request but refuses to authorize it."
        Write-Host "  - Common causes: Directory listing disabled, missing index.html, CORS restrictions, or authentication required."
        Write-Host "  - Action: Verify file permissions, create an index.html, or review authentication middleware."
        return
    }

    if ($StatusCode -ge 500) {
        Write-Host "  $($global:Style.BrightRed)HTTP $StatusCode Internal Server Error:$($global:Style.Reset)"
        Write-Host "  - The development server crashed or encountered an unhandled exception while processing the request."
        Write-Host "  - Action: Check your server terminal/console for runtime stack traces, unhandled promise rejections, or database connection failures."
        return
    }

    if ($RawMessage -match '10061|refused|actively refused' -or $ErrorCategory -eq "ConnectionRefused") {
        Write-Host "  $($global:Style.BrightRed)Connection Refused (WSAECONNREFUSED / Error 10061):$($global:Style.Reset)"
        Write-Host "  - The network packet reached the target IP, but NO application was listening on that port."
        Write-Host "  - Common causes:"
        Write-Host "    1. Development server has not been started yet."
        Write-Host "    2. Server crashed silently during startup."
        Write-Host "    3. Server is listening on 127.0.0.1 (IPv4), but client connected to ::1 (IPv6 localhost)."
        Write-Host "    4. Server is listening on a different port than the one requested."
        return
    }

    if ($RawMessage -match '10060|timed out|timeout' -or $ErrorCategory -eq "Timeout") {
        Write-Host "  $($global:Style.BrightRed)Connection Timed Out (WSAETIMEDOUT / Error 10060):$($global:Style.Reset)"
        Write-Host "  - Sent SYN packet but received no ACK or RST reply before the timeout expired."
        Write-Host "  - Common causes:"
        Write-Host "    1. Windows Defender Firewall (or third-party antivirus) is silently dropping inbound packets."
        Write-Host "    2. You are trying to connect via LAN IP, but the dev server is bound only to 127.0.0.1 (localhost)."
        Write-Host "    3. Client and server are on different subnets or router client isolation is active."
        return
    }

    if ($RawMessage -match '10048|already in use|Address already in use') {
        Write-Host "  $($global:Style.BrightRed)Address Already in Use (WSAEADDRINUSE / Error 10048):$($global:Style.Reset)"
        Write-Host "  - A process is already bound to this IP:Port combination."
        Write-Host "  - Use Menu Option 12 (Port Conflict Resolution) to identify the offending PID."
        return
    }

    Write-Host "  $($global:Style.BrightYellow)General Diagnostic:$($global:Style.Reset)"
    Write-Host "  - $RawMessage"
}

function Test-HttpEndpoint {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [ValidateSet("GET", "HEAD")]
        [string]$Method = "GET",
        [int]$TimeoutSeconds = 5
    )

    $cleanUrl = $Url.Trim()
    if ($cleanUrl -notmatch '^https?://') {
        $cleanUrl = "http://$cleanUrl"
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $result = [PSCustomObject]@{
        Url               = $cleanUrl
        Method            = $Method
        Success           = $false
        StatusCode        = 0
        StatusDescription = "None"
        ResponseTimeMs    = 0
        Headers           = @{}
        Redirected        = $false
        RedirectUrl       = ""
        CertSubject       = ""
        CertIssuer        = ""
        CertExpiry        = ""
        CertDaysLeft      = 0
        IsSelfSigned      = $false
        ErrorMessage      = ""
        ErrorCategory     = ""
    }

    $origCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
    $capturedCert = $null

    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {
        param($sender, $certificate, $chain, $sslPolicyErrors)
        $script:capturedCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificate)
        return $true
    }

    try {
        $request = [System.Net.HttpWebRequest]::Create($cleanUrl)
        $request.Method = $Method
        $request.Timeout = $TimeoutSeconds * 1000
        $request.AllowAutoRedirect = $false
        $request.UserAgent = "Localhost-Port-Toolkit/1.0"

        $response = $request.GetResponse()
        $sw.Stop()
        $httpResp = [System.Net.HttpWebResponse]$response

        $result.Success = $true
        $result.StatusCode = [int]$httpResp.StatusCode
        $result.StatusDescription = $httpResp.StatusDescription
        $result.ResponseTimeMs = $sw.ElapsedMilliseconds

        foreach ($key in $httpResp.Headers.AllKeys) {
            $result.Headers[$key] = $httpResp.Headers[$key]
        }

        if ($result.StatusCode -in @(301, 302, 303, 307, 308)) {
            $result.Redirected = $true
            $result.RedirectUrl = $httpResp.Headers["Location"]
        }

        $httpResp.Close()
    }
    catch [System.Net.WebException] {
        $sw.Stop()
        $result.ResponseTimeMs = $sw.ElapsedMilliseconds
        $webEx = $_.Exception

        if ($webEx.Response) {
            $httpResp = [System.Net.HttpWebResponse]$webEx.Response
            $result.StatusCode = [int]$httpResp.StatusCode
            $result.StatusDescription = $httpResp.StatusDescription
            foreach ($key in $httpResp.Headers.AllKeys) {
                $result.Headers[$key] = $httpResp.Headers[$key]
            }
            if ($result.StatusCode -in @(301, 302, 303, 307, 308)) {
                $result.Redirected = $true
                $result.RedirectUrl = $httpResp.Headers["Location"]
            }
            $result.ErrorMessage = "HTTP $($result.StatusCode) $($result.StatusDescription)"
            $result.Success = ($result.StatusCode -lt 400)
            $httpResp.Close()
        } else {
            $innerMsg = if ($webEx.InnerException) { $webEx.InnerException.Message } else { "" }
            $result.ErrorMessage = "$($webEx.Message)$(if ($innerMsg) { " - $innerMsg" })"
            $fullErrText = "$($webEx.Message) $innerMsg"
            if ($webEx.Status -eq [System.Net.WebExceptionStatus]::Timeout -or $fullErrText -match '10060|timed out') {
                $result.ErrorCategory = "Timeout"
            } elseif ($fullErrText -match '10061|actively refused|refused|Unable to connect') {
                $result.ErrorCategory = "ConnectionRefused"
            } else {
                $result.ErrorCategory = "NetworkError"
            }
        }
    }
    catch {
        $sw.Stop()
        $result.ResponseTimeMs = $sw.ElapsedMilliseconds
        $result.ErrorMessage = $_.ToString()
        $result.ErrorCategory = "GeneralError"
    }
    finally {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $origCallback
    }

    if ($capturedCert) {
        $result.CertSubject = $capturedCert.Subject
        $result.CertIssuer = $capturedCert.Issuer
        $result.CertExpiry = $capturedCert.NotAfter.ToString("yyyy-MM-dd HH:mm:ss")
        $days = [math]::Round(($capturedCert.NotAfter - (Get-Date)).TotalDays)
        $result.CertDaysLeft = $days
        $result.IsSelfSigned = ($capturedCert.Subject -eq $capturedCert.Issuer)
    }

    return $result
}

function Show-HttpDiagnosticsUI {
    Clear-Host
    Write-Header -Title "HTTP Server Diagnostics" -Subtitle "Test endpoints, measure latency, inspect headers, and diagnose failures"

    Write-Styled "Enter target URL or port (e.g. http://localhost:3000, 8000, or http://192.168.1.50:5173): " -Color "Yellow" -NoNewline
    $target = [System.Console]::ReadLine().Trim()

    if ([string]::IsNullOrWhiteSpace($target)) {
        Write-ErrorMsg "No URL or port entered."
        Pause-Console
        return
    }

    if ($target -match '^\d+$') {
        $target = "http://localhost:$target"
    }

    Write-Host ""
    Write-Host "Select HTTP Method: [1] GET (Default)  [2] HEAD"
    Write-Styled "Choice (1/2): " -Color "Cyan" -NoNewline
    $methodChoice = [System.Console]::ReadLine().Trim()
    $method = if ($methodChoice -eq "2") { "HEAD" } else { "GET" }

    Write-Host ""
    Write-Info "Executing $method request to $target (Timeout: 5s)..."
    $diag = Test-HttpEndpoint -Url $target -Method $method -TimeoutSeconds 5

    Write-Host ""
    Write-Section "HTTP Response Summary"
    
    if ($diag.Success -or ($diag.StatusCode -ge 200 -and $diag.StatusCode -lt 400)) {
        Write-Badge -Status "OK" -Label "HTTP Status" -Value "$($diag.StatusCode) $($diag.StatusDescription)"
    } elseif ($diag.StatusCode -gt 0) {
        Write-Badge -Status "WARN" -Label "HTTP Status" -Value "$($diag.StatusCode) $($diag.StatusDescription)"
    } else {
        Write-Badge -Status "FAIL" -Label "Connection" -Value "Failed ($($diag.ErrorCategory))"
    }

    Write-Badge -Status "INFO" -Label "Response Latency" -Value "$($diag.ResponseTimeMs) ms"
    Write-Badge -Status "INFO" -Label "Target URL" -Value "$($diag.Url)"

    if ($diag.Redirected) {
        Write-Badge -Status "WARN" -Label "Redirect Detected" -Value "Points to -> $($diag.RedirectUrl)"
    }

    if (-not [string]::IsNullOrWhiteSpace($diag.CertSubject)) {
        Write-Host ""
        Write-Section "TLS/HTTPS Certificate Inspection"
        Write-Badge -Status "INFO" -Label "Certificate Subject" -Value "$($diag.CertSubject)"
        Write-Badge -Status "INFO" -Label "Issuer" -Value "$($diag.CertIssuer)"
        Write-Badge -Status "INFO" -Label "Expires On" -Value "$($diag.CertExpiry) ($($diag.CertDaysLeft) days remaining)"
        $selfSignedTag = if ($diag.IsSelfSigned) { "WARN" } else { "OK" }
        Write-Badge -Status $selfSignedTag -Label "Self-Signed Certificate" -Value $(if ($diag.IsSelfSigned) { "YES (Common for local dev)" } else { "NO (Issued by CA)" })
    }

    if ($diag.Headers.Count -gt 0) {
        Write-Host ""
        Write-Section "Response Headers"
        foreach ($k in $diag.Headers.Keys) {
            Write-Host ("  {0,-25} : {1}" -f $k, $diag.Headers[$k]) -ForegroundColor Gray
        }
    }

    if (-not $diag.Success -or $diag.StatusCode -ge 400) {
        Explain-HttpError -ErrorCategory $diag.ErrorCategory -StatusCode $diag.StatusCode -RawMessage $diag.ErrorMessage
    }

    Write-Log -Level $(if ($diag.Success) { "INFO" } else { "WARN" }) -Module "HTTP" -Message "Tested $($diag.Url) - Status: $($diag.StatusCode) - Latency: $($diag.ResponseTimeMs)ms"
    Pause-Console
}
