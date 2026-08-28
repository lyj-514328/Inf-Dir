param(
  [Parameter(Mandatory = $true)]
  [string]$ResultsPath,
  [string]$SamplesRoot = 'D:\BaiduNetdiskDownload\abc\samples',
  [string]$DistRoot = '',
  [int]$TimeoutSeconds = 12,
  [string]$OutputPath = '',
  [switch]$InitialFailuresOnly
)

$ErrorActionPreference = 'Continue'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($DistRoot)) {
  $DistRoot = Join-Path $repoRoot 'plugins\dist'
}
$SamplesRoot = (Resolve-Path $SamplesRoot).Path
$DistRoot = (Resolve-Path $DistRoot).Path
$ResultsPath = (Resolve-Path $ResultsPath).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path (Split-Path -Parent $ResultsPath) 'recheck.jsonl'
}

function Read-TextFile([string]$Path) {
  try {
    if (Test-Path -LiteralPath $Path) {
      return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
    }
  } catch { }
  return ''
}

function Trim-Text([string]$Value, [int]$MaxLength = 2000) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  $clean = $Value.Trim()
  if ($clean.Length -le $MaxLength) { return $clean }
  return $clean.Substring(0, $MaxLength) + ' ...'
}

function Stop-ProcessTree([int]$ProcessId) {
  $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue)
  foreach ($child in $children) {
    Stop-ProcessTree -ProcessId ([int]$child.ProcessId)
  }
  Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

$rawResults = @(Get-Content -LiteralPath $ResultsPath -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
$jobs = [System.Collections.Generic.List[object]]::new()
$targetResults = if ($InitialFailuresOnly) {
  @($rawResults | Where-Object Status -eq 'exit_nonzero')
} else {
  @($rawResults | Where-Object Status -eq 'running_no_window')
}
foreach ($raw in $targetResults) {
  $jobs.Add([pscustomobject]@{
    ViewerId = [string]$raw.ViewerId
    Package = [string]$raw.Package
    Entrypoint = [string]$raw.Entrypoint
    Sample = [string]$raw.Sample
    SamplePath = [string]$raw.SamplePath
    DeclaredKind = [string]$raw.DeclaredKind
    DeclaredValue = [string]$raw.DeclaredValue
    Executable = Join-Path $DistRoot ([string]$raw.Package) | Join-Path -ChildPath ([string]$raw.Entrypoint)
    PackageDirectory = Join-Path $DistRoot ([string]$raw.Package)
    OriginalStatus = [string]$raw.Status
  })
}

# The first run executed this job, but its JSONL append was lost to a file lock.
$missingPath = Join-Path $SamplesRoot 'image\aai\sample_sembiance.aai'
$imagePackage = Join-Path $DistRoot 'inf-dir.image-view'
$imageManifest = Join-Path $imagePackage 'plugin.json'
if (-not $InitialFailuresOnly -and (Test-Path -LiteralPath $missingPath) -and (Test-Path -LiteralPath $imageManifest)) {
  $manifest = Get-Content -LiteralPath $imageManifest -Raw -Encoding UTF8 | ConvertFrom-Json
  $jobs.Add([pscustomobject]@{
    ViewerId = [string]$manifest.id
    Package = 'inf-dir.image-view'
    Entrypoint = [string]$manifest.entrypoint
    Sample = 'image\aai\sample_sembiance.aai'
    SamplePath = $missingPath
    DeclaredKind = 'extension'
    DeclaredValue = '.aai'
    Executable = Join-Path $imagePackage ([string]$manifest.entrypoint)
    PackageDirectory = $imagePackage
    OriginalStatus = 'missing_result'
  })
}

if ($jobs.Count -eq 0) {
  Write-Host 'No anomaly jobs found.'
  exit 0
}

$ioRoot = Join-Path (Split-Path -Parent $OutputPath) 'recheck-io'
New-Item -ItemType Directory -Force -Path $ioRoot | Out-Null
Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
$results = [System.Collections.Generic.List[object]]::new()
$index = 0
foreach ($job in $jobs) {
  $index++
  $safeName = '{0:D3}-{1}' -f $index, ($job.ViewerId -replace '[^A-Za-z0-9_.-]', '_')
  $stderrPath = Join-Path $ioRoot "$safeName.err"
  $stdoutPath = Join-Path $ioRoot "$safeName.out"
  $startedAt = Get-Date
  $process = $null
  $status = 'start_error'
  $exitCode = -1
  $title = ''
  $responding = $false
  $launchError = ''
  try {
    $quotedPath = '"' + $job.SamplePath.Replace('"', '\"') + '"'
    $process = Start-Process -FilePath $job.Executable -ArgumentList $quotedPath -WorkingDirectory $job.PackageDirectory -RedirectStandardError $stderrPath -RedirectStandardOutput $stdoutPath -PassThru -ErrorAction Stop
    $status = 'running_no_window'
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Milliseconds 200
      try { $process.Refresh() } catch { }
      try {
        if ($process.HasExited) {
          try { $process.WaitForExit() } catch { }
          $exitCode = $process.ExitCode
          $status = if ($exitCode -eq 0) { 'exit_zero' } else { 'exit_nonzero' }
          break
        }
        if ($process.MainWindowHandle -ne 0) {
          $title = $process.MainWindowTitle
          $responding = $process.Responding
          if ($responding) {
            $status = 'running_window'
            break
          }
          $status = 'hung'
        }
      } catch { }
    }
    try {
      $process.Refresh()
      if ($process.HasExited) {
        try { $process.WaitForExit() } catch { }
        $exitCode = $process.ExitCode
        if ($status -eq 'running_no_window' -or $status -eq 'hung') {
          $status = if ($exitCode -eq 0) { 'exit_zero' } else { 'exit_nonzero' }
        }
      } elseif ($status -ne 'running_window') {
        Stop-ProcessTree -ProcessId ([int]$process.Id)
      } else {
        Stop-ProcessTree -ProcessId ([int]$process.Id)
      }
    } catch {
      if ($null -ne $process) { Stop-ProcessTree -ProcessId ([int]$process.Id) }
    }
  } catch {
    $launchError = $_.Exception.Message
  }
  Start-Sleep -Milliseconds 100
  $stderr = Read-TextFile $stderrPath
  $stdout = Read-TextFile $stdoutPath
  Remove-Item -LiteralPath $stderrPath, $stdoutPath -Force -ErrorAction SilentlyContinue
  $errorText = if (-not [string]::IsNullOrWhiteSpace($launchError)) { $launchError } elseif ([string]::IsNullOrWhiteSpace($stderr)) { $stdout } else { $stderr }
  $elapsed = [int]((Get-Date) - $startedAt).TotalMilliseconds
  $result = [pscustomobject]@{
    ViewerId = $job.ViewerId
    Package = $job.Package
    Entrypoint = $job.Entrypoint
    Sample = $job.Sample
    SamplePath = $job.SamplePath
    DeclaredKind = $job.DeclaredKind
    DeclaredValue = $job.DeclaredValue
    Status = $status
    ExitCode = $exitCode
    ElapsedMs = $elapsed
    WindowTitle = $title
    Responding = $responding
    Error = (Trim-Text $errorText)
    Verification = "recheck_${TimeoutSeconds}s"
    OriginalStatus = $job.OriginalStatus
  }
  $results.Add($result)
  $line = ($result | ConvertTo-Json -Compress -Depth 8) + [Environment]::NewLine
  [System.IO.File]::AppendAllText($OutputPath, $line, [System.Text.UTF8Encoding]::new($false))
  Write-Host ("[{0}/{1}] {2} {3} {4}" -f $index, $jobs.Count, $result.ViewerId, $result.Status, $result.Sample)
}

Write-Host "Recheck results: $OutputPath"
