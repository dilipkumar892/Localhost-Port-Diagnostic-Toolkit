# Advanced Localhost & Port Diagnostic Toolkit for Windows

An enterprise-grade diagnostic utility, network troubleshooting dashboard, and port conflict resolution toolkit tailored for full-stack developers, DevOps engineers, IT support specialists, and system administrators running Windows 10, Windows 11, or Windows Server.

Designed specifically to diagnose and resolve connectivity bottlenecks in local development environments including **Python** (Django, Flask, FastAPI, Uvicorn, SimpleHTTPServer), **Node.js** (Vite, Next.js, Express, React, Angular, Vue), Docker containers, WSL2 virtual adapters, and local microservices.

---

## Key Capabilities

- **Zero-Dependency Architecture**: Runs out of the box with native Windows Batch and PowerShell 5.1 / 7+. Neither Python nor Node.js is required to run the diagnostics.
- **Localhost & Loopback Validation**: Evaluates IPv4 (`127.0.0.1`), IPv6 (`::1`), Windows hosts file overrides, and DNS resolver precedence (mitigating the RFC 6724 dual-stack bug in Node.js v17+).
- **Deep Port & Process Mapping**: Identifies every listening TCP socket and UDP endpoint, mapping them to exact PID, process executable paths, command-line arguments, memory footprint, and owner accounts.
- **Port Conflict Resolution**: Safely resolves `EADDRINUSE` / WinSock error 10048. Discovers the next available alternative port, integrates with Task Manager, and allows safe user-confirmed termination while strictly protecting system-critical processes (`System`, `Idle`, `smss`, `csrss`, `lsass`, `svchost`, `explorer`).
- **HTTP / HTTPS Diagnostics**: Tests HTTP GET/HEAD requests, measures latency down to the millisecond, extracts CORS and server headers, detects redirects, analyzes self-signed dev SSL/TLS certificates, and provides root-cause explanations for error codes (404, 403, 500, 10061 Connection Refused, 10060 Timeout).
- **LAN Sharing & Mobile Testing**: Automatically detects active LAN adapters, identifies Wi-Fi/Ethernet IP addresses, warns when servers bind only to `127.0.0.1` vs `0.0.0.0`, and outputs shareable URLs for remote testing on phones and tablets.
- **Windows Firewall Auditing & Scoped Rules**: Inspects Domain, Private, and Public profile states and inbound port rules. Offers safe, scoped rule creation restricted to Private networks with mandatory confirmation (never disables the firewall, never opens unrestricted global ports).
- **Offline HTML5 Diagnostic Reports**: Generates responsive, standalone HTML reports complete with system health badges, port tables, network interfaces, and developer recommendations.
- **Persistent Audit Logging**: Timestamped logging of all operations to `logs/diagnostic_YYYY-MM-DD.log`.

---

## Project Structure

```
Localhost-Port-Toolkit/
├── launcher.bat                   # Robust native Windows Batch entrypoint with bug-free menu
├── main.ps1                       # Central PowerShell dashboard orchestrator & menu dispatcher
├── README.md                      # Comprehensive user guide & network troubleshooting handbook
├── LICENSE                        # Open-source MIT license
├── config/
│   └── settings.json              # Configurable ports, timeouts, and process whitelists
├── modules/
│   ├── ports.ps1                  # TCP/UDP enumeration, port-to-process mapping, conflict detection
│   ├── processes.ps1              # Deep process inspection & safe conflict resolution workflow
│   ├── http.ps1                   # HTTP/HTTPS requests, latency, headers, TLS certs, error explanations
│   ├── network.ps1                # Localhost loopback health, hosts file, LAN adapter discovery
│   ├── firewall.ps1               # Firewall profile queries, inbound rule auditing, scoped rule creation
│   ├── ipv4.ps1                   # IPv4 config, DHCP/APIPA detection, gateway latency, routing table
│   ├── ipv6.ps1                   # IPv6 configuration, prefix policy table, dual-stack gotchas
│   ├── projects.ps1               # Python & Node runtime detection, active server scanner
│   ├── hosting.ps1                # Guided dev server hosting assistant (Python, Node, static web)
│   └── reports.ps1                # Self-contained HTML5 diagnostic report generator
├── lib/
│   ├── common.ps1                 # ANSI styling, administrative checks, system inspection helpers
│   ├── logging.ps1                # Timestamped file logging, log viewing, and rotation
│   ├── validation.ps1             # Input validation for ports, ranges, IP addresses, and URLs
│   └── safety.ps1                 # Critical process blacklist & confirmation guardrails
├── reports/                       # Exported HTML diagnostic reports
├── logs/                          # Daily audit logs
└── tests/
    └── run_tests.ps1              # 40-test automated verification suite
```

---

## Setup & Quick Start

### Prerequisites
- **Operating System**: Windows 10, Windows 11, or Windows Server 2016/2019/2022.
- **PowerShell**: Windows PowerShell 5.1 (built into Windows) or PowerShell 7+.
- **Privileges**: Standard user permissions for all read-only diagnostic tests. Administrative elevation is only prompted when you choose to create a firewall rule or terminate an elevated process.

### Launching the Toolkit

#### Method 1: Double-Click or Command Prompt (Batch)
Double-click `launcher.bat` or run from Command Prompt:
```cmd
launcher.bat
```
To run an option directly:
```cmd
launcher.bat 1     REM Localhost Connectivity Test
launcher.bat 2     REM TCP Port Scanner
launcher.bat 14    REM Generate Diagnostic Report
```

#### Method 2: PowerShell Console
```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File .\main.ps1
```
Or directly trigger an option:
```powershell
.\main.ps1 -Option 14
```

---

## Main Menu Overview

```
==============================================================================
      LOCAL HOST & PORT DIAGNOSTIC TOOLKIT (Windows 10 / 11 / Server)
==============================================================================

  DIAGNOSTIC & MANAGEMENT OPTIONS:

   1. Localhost Connectivity Test               9. Firewall Diagnostics
   2. TCP Port Scanner - Local Machine         10. IPv4 Diagnostics
   3. Port Usage Inspector                     11. IPv6 Diagnostics
   4. Process Identification                   12. Port Conflict Resolution
   5. HTTP Server Diagnostics                 13. Project Hosting Assistant
   6. Python Dev Server Diagnostics           14. Generate Diagnostic Report
   7. Node.js / npm Dev Server Diagnostics    15. View Logs
   8. LAN Accessibility Test                   16. Exit
```

### Menu Options Detail
1. **Localhost Connectivity Test**: Tests `127.0.0.1` and `::1` ICMP pings, evaluates DNS resolution order of `localhost`, and audits the Windows hosts file (`C:\Windows\System32\drivers\etc\hosts`) for stale redirects.
2. **TCP Port Scanner**: Quick-scans standard web development ports (`3000`, `3001`, `4173`, `4200`, `5000`, `5173`, `5500`, `8000`, `8080`, `8081`, `8888`, `9000`), custom ports/ranges (e.g., `8000-8010`), or all active listeners on the machine.
3. **Port Usage Inspector**: Prompts for any port number and exposes the exact listening PID, process name, executable path, memory footprint, user account, and full command line.
4. **Process Identification**: Look up any running process by PID or wildcard name to inspect its listening ports, start time, parent process, and command line.
5. **HTTP Server Diagnostics**: Sends GET or HEAD requests, calculates response latency, inspects headers, analyzes TLS certificates, and identifies connection failures.
6. **Python Dev Server Diagnostics**: Detects `py`, `python`, and `python3` installations in PATH and Registry. Scans for active Django, Flask, FastAPI, Uvicorn, and `http.server` instances.
7. **Node.js / npm Dev Server Diagnostics**: Detects Node, npm, and npx. Audits active Vite, Next.js, Express, React, and Angular development servers.
8. **LAN Accessibility Test**: Audits all active network adapters (Ethernet, Wi-Fi, Hyper-V, WSL). Evaluates whether your dev server is bound to loopback only or wildcard `0.0.0.0`, and outputs clickable URLs for testing from phones and remote devices on the same Wi-Fi.
9. **Firewall Diagnostics**: Audits Domain, Private, and Public Windows Firewall profiles and active inbound rules. Provides a safe wizard to create scoped Private rules with confirmation.
10. **IPv4 Diagnostics**: Inspects adapter addresses, subnet masks, default gateways, and DNS servers. Flags APIPA autoconfiguration (`169.254.x.x`) DHCP failures and tests gateway ping latency.
11. **IPv6 Diagnostics**: Inspects IPv6 loopback, link-local, and global addresses. Displays the Windows prefix policy precedence table (`netsh interface ipv6 show prefixpolicies`).
12. **Port Conflict Resolution**: Solves port collisions (`EADDRINUSE`). Suggests the next free port, offers Task Manager integration, or safely terminates the blocking process with explicit confirmation.
13. **Project Hosting Assistant**: Inspects any directory, detects framework config markers (`package.json`, `manage.py`, `vite.config.*`), reviews binding risks, verifies port availability, and launches the dev server in a new window.
14. **Generate Diagnostic Report**: Compiles a comprehensive offline HTML5 report and saves it to `reports/diagnostic_report_YYYYMMDD_HHMMSS.html`.
15. **View Logs**: Interactive console log viewer displaying recent audit events with color-coded severity levels.
16. **Exit**: Gracefully exits the toolkit.

---

## Network Troubleshooting Guide

### 1. "Address already in use" (EADDRINUSE / WinSock 10048)
- **Root Cause**: Another application is already bound to that exact port. Often caused by an orphaned Node.js or Python background process from an earlier session.
- **Resolution**:
  1. Open toolkit and select **Option 12 (Port Conflict Resolution)**.
  2. Enter the conflicted port (e.g. `3000`).
  3. Inspect the owning PID and executable path.
  4. Either accept the suggested alternative port (e.g. `3001`), or choose Action 3 to stop the offending process after confirmation.

### 2. "Connection Refused" (WSAECONNREFUSED / WinSock 10061)
- **Root Cause**: The client sent a TCP SYN packet, but no application on the target IP was listening on that port, causing Windows to send back an immediate TCP RST.
- **Resolution**:
  1. Verify the dev server is actively running with **Option 2** or **Option 6/7**.
  2. Check for the **IPv6 / IPv4 mismatch**: Node.js v17+ resolves `localhost` to `::1` (IPv6), but Python or legacy servers bind to `127.0.0.1` (IPv4).
  3. Workaround: Connect directly to `http://127.0.0.1:PORT` instead of `http://localhost:PORT`.

### 3. "Connection Timed Out" (WSAETIMEDOUT / WinSock 10060)
- **Root Cause**: Sent TCP SYN packet, but received no response before timeout expired. This indicates packets are being silently dropped by a firewall or routing failure.
- **Resolution**:
  1. Run **Option 9 (Firewall Diagnostics)** to check if Windows Firewall is blocking inbound connections.
  2. Verify if the server is bound to `127.0.0.1` instead of `0.0.0.0`. Loopback bindings will silently reject remote LAN packets.
  3. Check if the testing phone/device is on a different Wi-Fi subnet or if router "AP Client Isolation" is enabled.

### 4. APIPA Address Assigned (`169.254.x.x`)
- **Root Cause**: Your network adapter requested an IP address from the DHCP server (router), but received no reply within the timeout period.
- **Resolution**:
  1. Run **Option 10 (IPv4 Diagnostics)** to locate the affected adapter.
  2. Reconnect the Ethernet cable or reconnect to Wi-Fi.
  3. Open an administrative PowerShell and run: `ipconfig /release` followed by `ipconfig /renew`.

---

## Safety & Security Architecture

1. **System Process Whitelist**:
   The safety subsystem (`lib/safety.ps1`) maintains an immutable protection list of Windows kernel and critical services:
   `System (PID 4)`, `System Idle (PID 0)`, `smss.exe`, `csrss.exe`, `wininit.exe`, `services.exe`, `lsass.exe`, `svchost.exe`, `explorer.exe`, `dwm.exe`.
   Attempting to stop any of these processes is unconditionally blocked with a critical safety alert.

2. **Explicit Two-Step Confirmation**:
   - Terminating any user process requires typing `KILL` to confirm.
   - Creating a firewall rule requires typing `ALLOW` to confirm.
   - Launching a dev server requires typing `RUN` to confirm.

3. **Firewall Boundary Integrity**:
   - The toolkit will **never** disable the Windows Firewall.
   - The toolkit will **never** create unrestricted `0.0.0.0/0` inbound rules.
   - Any rule created via Option 9 is strictly scoped to the `Private` profile (protecting the machine when connecting to public coffee shop Wi-Fi).

4. **Network Exposure Transparency**:
   Before launching any server with `0.0.0.0`, the toolkit provides educational alerts detailing LAN exposure risks.

---

## Automated Verification Suite

The toolkit includes an automated unit and integration test runner in `tests/run_tests.ps1`:
```powershell
powershell -ExecutionPolicy Bypass -NoProfile -File .\tests\run_tests.ps1
```

### Verified Test Matrix (40 Tests Total, 100% Pass)
- **Input Validation**: Valid ports (`3000`, `5173`, `8000`, `8080`), invalid ports (`0`, `-5`, `65536`, `abc`, `80.5`), range parsing (`3000, 8000-8002, 8080`), IPv4 loopback (`127.0.0.1`), IPv6 loopback (`::1`), invalid IP strings.
- **Safety Safeguards**: Process protection for PID 0, PID 4, `svchost`, `explorer`, `lsass`. `Assert-SafeProcessKill` enforcement. Alternative port discovery.
- **Port Diagnostics**: `Scan-PortsList` accuracy across common ports, `Get-PortProcessMap` active socket queries, `Detect-PortConflicts` collision checks.
- **HTTP Client**: Connection refused handling without crashing, HTTP 200 OK detection with millisecond latency measurement, HTTP 404 Not Found diagnosis.
- **Network Stack**: Loopback stack resolution, IPv4 ping response, active network adapter retrieval, IPv4 detailed reporting, IPv6 prefix policy table parsing.
- **Firewall Module**: Profile state queries, non-destructive inbound rule queries.
- **Runtime Detection**: Python environment detection, Node.js environment detection, running dev server process scanner.
- **Report & Logging**: Valid HTML5 report generation on disk, System Overview and Port Scan section verification, timestamped log writing and reading.

---

## Ponytail Review (Minimalism & Simplicity)

This toolkit adheres to the **Ponytail Principle**:
- **Native Platform Utilities**: Replaced third-party socket libraries and heavy npm dependencies with native Windows cmdlets (`Get-NetTCPConnection`, `Get-NetIPAddress`, `Get-NetFirewallRule`, `netsh`, and .NET `System.Net`).
- **Zero Third-Party Packages**: No external npm or pip modules required.
- **Self-Contained Reports**: The HTML report uses pure embedded CSS with standard modern web typography, requiring no external font CDNs or analytics scripts. Works 100% offline in air-gapped environments.
- **Concise Architecture**: Modular separation between pure libraries (`lib/`), functional engines (`modules/`), user configuration (`config/`), and UI launchers.

---

## Future Improvements

1. **WSL2 Automatic Port Proxying**: Integrated detection of WSL2 virtual network bridges (`vEthernet (WSL)`) with one-click `netsh interface portproxy` configuration.
2. **Reverse Proxy & HTTPS Tunnel Integration**: Optional support for inspecting and launching local dev tunnels (e.g. Cloudflare Tunnels, Tailscale Funnel, or ngrok).
3. **mDNS & Bonjour Discovery**: Automated broadcasting of `.local` domains for Zero-Config iOS and Android Wi-Fi testing.
4. **Bandwidth & Socket Throughput Profiler**: Real-time packet throughput monitoring on active development ports.
