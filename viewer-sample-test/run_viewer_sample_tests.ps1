param(
  [string]$SamplesRoot = 'D:\BaiduNetdiskDownload\abc\samples',
  [string]$DistRoot = '',
  [string]$OutputRoot = '',
  [int]$ReadyTimeoutSeconds = 5
)

$ErrorActionPreference = 'Continue'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($DistRoot)) {
  $DistRoot = Join-Path $repoRoot 'plugins\dist'
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $PSScriptRoot 'results'
}

$SamplesRoot = (Resolve-Path $SamplesRoot).Path
$DistRoot = (Resolve-Path $DistRoot).Path
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$runId = (Get-Date).ToString('yyyyMMdd-HHmmss')
$runRoot = Join-Path $OutputRoot $runId
$ioRoot = Join-Path $runRoot 'io'
New-Item -ItemType Directory -Force -Path $ioRoot | Out-Null
$jsonlPath = Join-Path $runRoot 'results.jsonl'
$reportPath = Join-Path $PSScriptRoot 'viewer-sample-test-report.md'

function Read-TextFile([string]$Path) {
  for ($attempt = 0; $attempt -lt 5; $attempt++) {
    try {
      if (Test-Path -LiteralPath $Path) {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
      }
    } catch { }
    Start-Sleep -Milliseconds 100
  }
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

function New-Result($Job, [string]$Status, [int]$ExitCode, [int]$ElapsedMs, [string]$Title, [bool]$Responding, [string]$ErrorText) {
  return [pscustomobject]@{
    ViewerId = $Job.ViewerId
    Package = $Job.Package
    Entrypoint = $Job.Entrypoint
    Sample = $Job.Sample
    SamplePath = $Job.SamplePath
    DeclaredKind = $Job.DeclaredKind
    DeclaredValue = $Job.DeclaredValue
    Status = $Status
    ExitCode = $ExitCode
    ElapsedMs = $ElapsedMs
    WindowTitle = $Title
    Responding = $Responding
    Error = (Trim-Text $ErrorText)
  }
}

function Invoke-ViewerSample($Job, [int]$Index) {
  $safeName = '{0:D5}-{1}' -f $Index, ($Job.ViewerId -replace '[^A-Za-z0-9_.-]', '_')
  $stderrPath = Join-Path $ioRoot "$safeName.err"
  $stdoutPath = Join-Path $ioRoot "$safeName.out"
  $startedAt = Get-Date
  $process = $null
  try {
    $quotedPath = '"' + $Job.SamplePath.Replace('"', '\"') + '"'
    $process = Start-Process `
      -FilePath $Job.Executable `
      -ArgumentList $quotedPath `
      -WorkingDirectory $Job.PackageDirectory `
      -RedirectStandardError $stderrPath `
      -RedirectStandardOutput $stdoutPath `
      -PassThru `
      -ErrorAction Stop
  } catch {
    return New-Result $Job 'start_error' -1 0 '' $false $_.Exception.Message
  }

  $status = 'running_no_window'
  $exitCode = -1
  $title = ''
  $responding = $false
  $deadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 200
    try { $process.Refresh() } catch { }
    try {
      if ($process.HasExited) {
        $exitCode = $process.ExitCode
        $status = if ($exitCode -eq 0) { 'exit_zero' } else { 'exit_nonzero' }
        break
      }
      if ($process.MainWindowHandle -ne 0) {
        $title = $process.MainWindowTitle
        $responding = $process.Responding
        $status = if ($responding) { 'running_window' } else { 'hung' }
        if ($status -eq 'running_window') { break }
      }
    } catch { }
  }

  try {
    $process.Refresh()
    if ($process.HasExited) {
      $exitCode = $process.ExitCode
      if ($status -eq 'running_no_window') {
        $status = if ($exitCode -eq 0) { 'exit_zero' } else { 'exit_nonzero' }
      }
    } else {
      if ($process.MainWindowHandle -ne 0) {
        $title = $process.MainWindowTitle
        $responding = $process.Responding
        if ($responding) { $status = 'running_window' }
      }
      Stop-ProcessTree -ProcessId ([int]$process.Id)
    }
  } catch {
    Stop-ProcessTree -ProcessId ([int]$process.Id)
  }

  Start-Sleep -Milliseconds 100
  $stderr = Read-TextFile $stderrPath
  $stdout = Read-TextFile $stdoutPath
  Remove-Item -LiteralPath $stderrPath, $stdoutPath -Force -ErrorAction SilentlyContinue
  $elapsed = [int]((Get-Date) - $startedAt).TotalMilliseconds
  $errorText = if ([string]::IsNullOrWhiteSpace($stderr)) { $stdout } else { $stderr }
  return New-Result $Job $status $exitCode $elapsed $title $responding $errorText
}

$samples = @(Get-ChildItem -LiteralPath $SamplesRoot -Recurse -File)
$manifestFiles = @(Get-ChildItem -Path (Join-Path $DistRoot '*\plugin.json') -File)
$jobs = [System.Collections.Generic.List[object]]::new()

foreach ($manifestFile in $manifestFiles) {
  try {
    $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $quickView = $manifest.capabilities.quickView
    if ($null -eq $quickView) { continue }

    $entrypoint = [string]$manifest.entrypoint
    $executable = Join-Path $manifestFile.DirectoryName $entrypoint
    if (-not (Test-Path -LiteralPath $executable)) { continue }
    $extensions = @($quickView.extensions | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
    $fileNames = @($quickView.fileNames | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
    $sortedExtensions = @($extensions | Sort-Object Length -Descending)

    foreach ($sample in $samples) {
      $baseName = $sample.Name.ToLowerInvariant()
      $kind = $null
      $value = $null
      foreach ($fileName in $fileNames) {
        if ($baseName -eq $fileName) {
          $kind = 'fileName'
          $value = $fileName
          break
        }
      }
      if ($null -eq $kind) {
        foreach ($extension in $sortedExtensions) {
          if ($baseName.EndsWith($extension)) {
            $kind = 'extension'
            $value = $extension
            break
          }
        }
      }
      if ($null -eq $kind) { continue }

      $relative = $sample.FullName.Substring($SamplesRoot.Length).TrimStart('\')
      $jobs.Add([pscustomobject]@{
        ViewerId = [string]$manifest.id
        Package = $manifestFile.Directory.Name
        Entrypoint = $entrypoint
        Executable = $executable
        PackageDirectory = $manifestFile.DirectoryName
        Sample = $relative
        SamplePath = $sample.FullName
        DeclaredKind = $kind
        DeclaredValue = $value
      })
    }
  } catch {
    Write-Warning "Skipping manifest $($manifestFile.FullName): $($_.Exception.Message)"
  }
}

Write-Host "Samples: $($samples.Count); viewer/sample jobs: $($jobs.Count)"
$index = 0
foreach ($job in $jobs) {
  $index++
  $result = Invoke-ViewerSample $job $index
  $jsonLine = ($result | ConvertTo-Json -Compress -Depth 8) + [Environment]::NewLine
  $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonLine)
  $written = $false
  for ($attempt = 0; $attempt -lt 10 -and -not $written; $attempt++) {
    $stream = $null
    try {
      $stream = [System.IO.File]::Open(
        $jsonlPath,
        [System.IO.FileMode]::Append,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::ReadWrite)
      $stream.Write($jsonBytes, 0, $jsonBytes.Length)
      $written = $true
    } catch {
      if ($attempt -eq 9) {
        Write-Warning "Could not persist result $index ($($job.ViewerId), $($job.Sample)): $($_.Exception.Message)"
      } else {
        Start-Sleep -Milliseconds 100
      }
    } finally {
      if ($null -ne $stream) { $stream.Dispose() }
    }
  }
  if (($index % 10) -eq 0 -or $index -eq $jobs.Count) {
    Write-Host ("[{0}/{1}] {2} {3} {4}" -f $index, $jobs.Count, $result.ViewerId, $result.Status, $result.Sample)
  }
}

$resultObjects = @()
if (Test-Path -LiteralPath $jsonlPath) {
  $resultObjects = @(Get-Content -LiteralPath $jsonlPath -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Get-EffectiveStatus([object]$Result) {
  if ($Result.Status -eq 'running_window' -and -not [string]::IsNullOrWhiteSpace([string]$Result.Error)) {
    if ([string]$Result.Error -match '(?i)(failed to load image|failed to open archive|failed to initialize|unhandled exception|decoder failed|conversion failed)') {
      return 'content_error'
    }
  }
  return [string]$Result.Status
}

$md = [System.Collections.Generic.List[string]]::new()
[void]$md.Add('# Viewer Sample Test Report')
[void]$md.Add('')
[void]$md.Add("- Run: $runId")
[void]$md.Add("- Samples root: $SamplesRoot")
[void]$md.Add("- Dist root: $DistRoot")
[void]$md.Add("- Samples discovered: $($samples.Count)")
[void]$md.Add("- Viewer/sample jobs: $($jobs.Count)")
[void]$md.Add("- Ready timeout per job: ${ReadyTimeoutSeconds}s")
[void]$md.Add('')
[void]$md.Add('## Classification')
[void]$md.Add('')
[void]$md.Add('- running_window: the process created a responsive window before the timeout; native decoders generally parse the file before this point.')
[void]$md.Add('- content_error: a responsive window appeared, but the viewer reported a decode/open/initialization error for the sample.')
[void]$md.Add('- exit_nonzero: the viewer exited before creating a window with a non-zero code.')
[void]$md.Add('- exit_zero: the viewer exited before creating a window with code zero.')
[void]$md.Add('- running_no_window / hung / start_error: viewing could not be confirmed.')
[void]$md.Add('- WebView2 and Office viewers may show an in-window error without exiting; running_window confirms startup, not visual content acceptance.')
[void]$md.Add('')

$statusGroups = @($resultObjects | Group-Object Status | Sort-Object Name)
[void]$md.Add('## Overall')
[void]$md.Add('')
[void]$md.Add('| Status | Count |')
[void]$md.Add('| --- | ---: |')
foreach ($group in @($resultObjects | Group-Object { Get-EffectiveStatus $_ } | Sort-Object Name)) {
  [void]$md.Add("| $($group.Name) | $($group.Count) |")
}
[void]$md.Add('')

[void]$md.Add('## By Viewer')
[void]$md.Add('')
[void]$md.Add('| Viewer | Declared samples | Responsive windows | Non-zero exits | Indeterminate |')
[void]$md.Add('| --- | ---: | ---: | ---: | ---: |')
foreach ($group in @($resultObjects | Group-Object ViewerId | Sort-Object Name)) {
  $window = @($group.Group | Where-Object { (Get-EffectiveStatus $_) -eq 'running_window' }).Count
  $failed = @($group.Group | Where-Object { (Get-EffectiveStatus $_) -in @('exit_nonzero', 'content_error') }).Count
  $indeterminate = @($group.Group | Where-Object { (Get-EffectiveStatus $_) -in @('running_no_window', 'hung', 'start_error', 'exit_zero') }).Count
  [void]$md.Add("| $($group.Name) | $($group.Count) | $window | $failed | $indeterminate |")
}
[void]$md.Add('')

[void]$md.Add('## Failures and anomalies')
[void]$md.Add('')
[void]$md.Add('| Viewer | Declared format | Sample | Status | Exit code | Window title | Error output |')
[void]$md.Add('| --- | --- | --- | --- | ---: | --- | --- |')
$anomalies = @($resultObjects | Where-Object { (Get-EffectiveStatus $_) -ne 'running_window' })
foreach ($result in $anomalies) {
  $sample = $result.Sample -replace '\|', '\\|'
  $errorText = (Trim-Text $result.Error 240) -replace "`r?`n", ' ' -replace '\|', '\\|'
  $title = ([string]$result.WindowTitle) -replace '\|', '\\|'
  [void]$md.Add("| $($result.ViewerId) | $($result.DeclaredValue) | $sample | $(Get-EffectiveStatus $result) | $($result.ExitCode) | $title | $errorText |")
}
if ($anomalies.Count -eq 0) {
  [void]$md.Add('| (none) | | | | | | |')
}
[void]$md.Add('')
[void]$md.Add("Raw per-job results: $($jsonlPath.Replace($repoRoot + '\\', ''))")

$md | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host "Report: $reportPath"
Write-Host "Raw results: $jsonlPath"
