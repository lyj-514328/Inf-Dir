[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Http', 'Socks5')]
    [string]$Protocol = 'Auto',

    [ValidateRange(1, 65535)]
    [int]$Port = 0,

    [string]$ProxyHost = '127.0.0.1',

    [switch]$Clear
)

# Usage: . .\set-proxy.ps1
# Use -Port when the local proxy is not discoverable automatically.

$proxyVariableNames = @(
    'http_proxy', 'https_proxy', 'all_proxy',
    'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY'
)

function Resolve-ProxyProtocol {
    param(
        [string]$RequestedProtocol,
        [int]$CandidatePort,
        [string]$Hint = ''
    )

    if ($RequestedProtocol -ne 'Auto') {
        return $RequestedProtocol.ToLowerInvariant()
    }

    if ($Hint -match '(?i)(mixed-port|http-port|http-proxy|mixed)') {
        return 'http'
    }

    if ($Hint -match '(?i)(socks-port|socks5|socks)') {
        return 'socks5'
    }

    switch ($CandidatePort) {
        7891 { return 'socks5' }
        10808 { return 'socks5' }
        1080 { return 'socks5' }
        default { return 'http' }
    }
}

function New-ProxyCandidate {
    param(
        [string]$CandidateHost,
        [int]$CandidatePort,
        [string]$RequestedProtocol,
        [string]$Hint,
        [string]$Source,
        [int]$Score
    )

    if ([string]::IsNullOrWhiteSpace($CandidateHost)) {
        return $null
    }

    if ($CandidatePort -lt 1 -or $CandidatePort -gt 65535) {
        return $null
    }

    [pscustomobject]@{
        Host     = $CandidateHost.TrimStart('[').TrimEnd(']')
        Port     = $CandidatePort
        Protocol = Resolve-ProxyProtocol -RequestedProtocol $RequestedProtocol -CandidatePort $CandidatePort -Hint $Hint
        Source   = $Source
        Score    = $Score
    }
}

function ConvertTo-ProxyCandidate {
    param(
        [string]$Value,
        [string]$RequestedProtocol = 'Auto',
        [string]$Source = 'unknown',
        [int]$Score = 0
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $endpoint = $Value.Trim().TrimEnd(';').TrimEnd('/')
    $match = [regex]::Match(
        $endpoint,
        '^(?:(?<scheme>https?|socks5?h?|socks)://)?(?<host>\[[^\]]+\]|[^:/\s]+):(?<port>\d{1,5})$'
    )
    if (-not $match.Success) {
        return $null
    }

    $candidatePort = 0
    if (-not [int]::TryParse($match.Groups['port'].Value, [ref]$candidatePort)) {
        return $null
    }

    $protocolHint = $RequestedProtocol
    if ($match.Groups['scheme'].Success) {
        $protocolHint = $match.Groups['scheme'].Value
        if ($protocolHint -match '(?i)^socks') {
            $protocolHint = 'Socks5'
        } else {
            $protocolHint = 'Http'
        }
    }

    New-ProxyCandidate `
        -CandidateHost $match.Groups['host'].Value `
        -CandidatePort $candidatePort `
        -RequestedProtocol $protocolHint `
        -Hint $endpoint `
        -Source $Source `
        -Score $Score
}

function Get-ListeningProxyCandidates {
    $knownPorts = @{
        7890 = 25  # Clash HTTP
        7891 = 25  # Clash SOCKS
        7897 = 25  # Mihomo/Clash Verge mixed
        1080  = 15 # Common SOCKS
        10808 = 20 # v2rayN SOCKS
        10809 = 25 # v2rayN HTTP
        2080  = 15 # Common sing-box mixed
    }
    $proxyProcessPattern = '(?i)(clash|mihomo|v2ray|xray|sing-box|shadowsocks|ss-local|nekoray|hiddify|surge|tun2socks|leaf)'
    $candidates = @()
    $processes = @{}

    try {
        Get-CimInstance Win32_Process -ErrorAction Stop | ForEach-Object {
            $processes[[int]$_.ProcessId] = $_
        }
    } catch {
        # Process names are only used to improve the candidate score.
    }

    $listeners = @()
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        try {
            $listeners = @(
                Get-NetTCPConnection -State Listen -ErrorAction Stop |
                    Where-Object {
                        $_.LocalAddress -in @('127.0.0.1', '::1', '0.0.0.0', '::')
                    }
            )
        } catch {
            $listeners = @()
        }
    }

    if ($listeners.Count -eq 0) {
        netstat.exe -ano -p tcp 2>$null | ForEach-Object {
            if ($_ -match '^\s*TCP\s+(?<address>\S+):(?<port>\d+)\s+\S+\s+LISTENING\s+(?<pid>\d+)\s*$') {
                $address = $Matches['address']
                if ($address -in @('127.0.0.1', '0.0.0.0', '[::1]', '[::]')) {
                    $listeners += [pscustomobject]@{
                        LocalAddress   = $address.TrimStart('[').TrimEnd(']')
                        LocalPort      = [int]$Matches['port']
                        OwningProcess  = [int]$Matches['pid']
                    }
                }
            }
        }
    }

    foreach ($listener in $listeners) {
        $candidatePort = [int]$listener.LocalPort
        $process = $processes[[int]$listener.OwningProcess]
        $processName = if ($null -ne $process) { [string]$process.Name } else { '' }
        $commandLine = if ($null -ne $process) { [string]$process.CommandLine } else { '' }
        $hint = "$processName $commandLine"
        $isProxyProcess = $hint -match $proxyProcessPattern
        $isKnownPort = $knownPorts.ContainsKey($candidatePort)

        if (-not $isProxyProcess -and -not $isKnownPort) {
            continue
        }

        $score = if ($isProxyProcess) { 100 } else { 20 }
        if ($isKnownPort) {
            $score += $knownPorts[$candidatePort]
        }
        if ($commandLine -match '(?i)(mixed-port|http-port|socks-port|proxy-port)') {
            $score += 20
        }

        $candidate = New-ProxyCandidate `
            -CandidateHost '127.0.0.1' `
            -CandidatePort $candidatePort `
            -RequestedProtocol $Protocol `
            -Hint $hint `
            -Source "listening process: $processName" `
            -Score $score
        if ($null -ne $candidate) {
            $candidates += $candidate
        }
    }

    $candidates
}

if ($Clear) {
    foreach ($name in $proxyVariableNames) {
        Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    }
    Write-Host 'Proxy environment variables cleared for this PowerShell process.'
    return
}

$candidates = @()

if ($Port -gt 0) {
    $explicitCandidate = New-ProxyCandidate `
        -CandidateHost $ProxyHost `
        -CandidatePort $Port `
        -RequestedProtocol $Protocol `
        -Hint '' `
        -Source 'explicit -Port' `
        -Score 1000
    if ($null -ne $explicitCandidate) {
        $candidates += $explicitCandidate
    }
}

# Windows Internet Settings can contain entries such as http=127.0.0.1:7890.
try {
    $internetSettings = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
    if ($internetSettings.ProxyEnable -eq 1 -and $internetSettings.ProxyServer) {
        foreach ($entry in ([string]$internetSettings.ProxyServer -split ';')) {
            $entry = $entry.Trim()
            if ([string]::IsNullOrWhiteSpace($entry)) {
                continue
            }

            $entryProtocol = 'Auto'
            $entryValue = $entry
            if ($entry -match '^(?<kind>[^=]+)=(?<value>.+)$') {
                $entryKind = $Matches['kind'].Trim().ToLowerInvariant()
                $entryValue = $Matches['value'].Trim()
                if ($entryKind -match '^socks') {
                    $entryProtocol = 'Socks5'
                } elseif ($entryKind -match '^https?$') {
                    $entryProtocol = 'Http'
                }
            }

            $systemCandidate = ConvertTo-ProxyCandidate `
                -Value $entryValue `
                -RequestedProtocol $entryProtocol `
                -Source 'Windows system proxy' `
                -Score 200
            if ($null -ne $systemCandidate) {
                $candidates += $systemCandidate
            }
        }
    }
} catch {
    # The registry lookup is unavailable on non-Windows PowerShell hosts.
}

# Existing proxy variables are useful when a parent shell already discovered the endpoint.
foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy')) {
    $existingValue = [Environment]::GetEnvironmentVariable($name, 'Process')
    $existingCandidate = ConvertTo-ProxyCandidate `
        -Value $existingValue `
        -RequestedProtocol 'Auto' `
        -Source "existing $name" `
        -Score 60
    if ($null -ne $existingCandidate) {
        $candidates += $existingCandidate
    }
}

$candidates += @(Get-ListeningProxyCandidates)

if ($candidates.Count -eq 0) {
    Write-Error 'No proxy endpoint was found. Use . .\set-proxy.ps1 -Port <port> or specify -ProxyHost.'
    return
}

$selected = $candidates |
    Sort-Object -Property @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Port'; Descending = $false } |
    Select-Object -First 1

$selectedHost = $selected.Host
if ($selectedHost -match ':') {
    $selectedHost = "[$selectedHost]"
}
$proxyUrl = '{0}://{1}:{2}' -f $selected.Protocol, $selectedHost, $selected.Port

foreach ($name in $proxyVariableNames) {
    Set-Item -Path "Env:$name" -Value $proxyUrl
}

Write-Host "Proxy set to $proxyUrl ($($selected.Source))."
if ($MyInvocation.InvocationName -ne '.') {
    Write-Warning 'Run this script with dot-sourcing to keep the variables in the current PowerShell session:'
    Write-Host '  . .\set-proxy.ps1'
}
