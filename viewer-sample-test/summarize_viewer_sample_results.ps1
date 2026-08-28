param(
  [Parameter(Mandatory = $true)]
  [string]$ResultsPath,
  [string[]]$RecheckPath = @(),
  [string]$ReportPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ResultsPath = (Resolve-Path $ResultsPath).Path
if (-not [string]::IsNullOrWhiteSpace($RecheckPath)) {
  $RecheckPath = (Resolve-Path $RecheckPath).Path
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
  $ReportPath = Join-Path $PSScriptRoot 'viewer-sample-test-report.md'
}

function Read-JsonLines([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return @()
  }
  return @(Get-Content -LiteralPath $Path -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
}

function Markdown-Text([object]$Value, [int]$MaxLength = 240) {
  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) { return '' }
  $text = $text.Trim() -replace "`r?`n", ' ' -replace '\|', '\\|'
  if ($text.Length -le $MaxLength) { return $text }
  return $text.Substring(0, $MaxLength) + ' ...'
}

$rawResults = @(Read-JsonLines $ResultsPath)
$recheckResults = @($RecheckPath | ForEach-Object { Read-JsonLines $_ })
$byKey = @{}
foreach ($result in $rawResults) {
  $byKey["$($result.ViewerId)|$($result.Sample)"] = $result
}
foreach ($result in $recheckResults) {
  # A recheck is authoritative for the same viewer/sample pair.
  $byKey["$($result.ViewerId)|$($result.Sample)"] = $result
}
$results = @($byKey.Values | Sort-Object ViewerId, Sample)
$runId = Split-Path -Leaf (Split-Path -Parent $ResultsPath)

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
[void]$md.Add("- Samples root: D:\BaiduNetdiskDownload\abc\samples")
[void]$md.Add("- Initial persisted records: $($rawResults.Count)")
[void]$md.Add("- Rechecked records: $($recheckResults.Count)")
[void]$md.Add("- Final logical viewer/sample jobs: $($results.Count)")
[void]$md.Add("- Responsive windows (including content errors): $(@($results | Where-Object { (Get-EffectiveStatus $_) -in @('running_window', 'content_error') }).Count)")
[void]$md.Add("- Responsive windows without an explicit viewer error: $(@($results | Where-Object { (Get-EffectiveStatus $_) -eq 'running_window' }).Count)")
[void]$md.Add('- The initial run had one JSONL write lost to a file lock; the missing AAI job was rechecked and included in the final set.')
[void]$md.Add('')
[void]$md.Add('## Classification')
[void]$md.Add('')
[void]$md.Add('- running_window: the process created a responsive window within the test timeout.')
[void]$md.Add('- content_error: a responsive window appeared, but the viewer reported a decode/open/initialization error for the sample.')
[void]$md.Add('- exit_nonzero: the process exited before a responsive window was observed and reported a non-zero/failed launch result.')
[void]$md.Add('- exit_zero: the process exited before a responsive window with code zero.')
[void]$md.Add('- running_no_window / hung / start_error: viewing could not be confirmed.')
[void]$md.Add('- WebView2 and Office viewers can show an in-window decoder error without exiting; running_window confirms startup, not visual content acceptance.')
[void]$md.Add('- Jobs are created only when a sample basename matches a manifest fileName or declared extension; declared formats with no matching sample are outside this run.')
[void]$md.Add('')

[void]$md.Add('## Overall')
[void]$md.Add('')
[void]$md.Add('| Status | Count |')
[void]$md.Add('| --- | ---: |')
foreach ($group in @($results | Group-Object { Get-EffectiveStatus $_ } | Sort-Object Name)) {
  [void]$md.Add("| $($group.Name) | $($group.Count) |")
}
[void]$md.Add('')

[void]$md.Add('## By Viewer')
[void]$md.Add('')
[void]$md.Add('| Viewer | Declared samples | Responsive windows | Failures / content errors | Indeterminate |')
[void]$md.Add('| --- | ---: | ---: | ---: | ---: |')
foreach ($group in @($results | Group-Object ViewerId | Sort-Object Name)) {
  $windowCount = @($group.Group | Where-Object { (Get-EffectiveStatus $_) -eq 'running_window' }).Count
  $failedCount = @($group.Group | Where-Object { (Get-EffectiveStatus $_) -in @('exit_nonzero', 'content_error') }).Count
  $otherCount = @($group.Group | Where-Object { (Get-EffectiveStatus $_) -in @('running_no_window', 'hung', 'start_error', 'exit_zero') }).Count
  [void]$md.Add("| $($group.Name) | $($group.Count) | $windowCount | $failedCount | $otherCount |")
}
[void]$md.Add('')

[void]$md.Add('## Failures and anomalies')
[void]$md.Add('')
[void]$md.Add('| Viewer | Declared format | Sample | Status | Exit code | Verification | Error output |')
[void]$md.Add('| --- | --- | --- | --- | ---: | --- | --- |')
$anomalies = @($results | Where-Object { (Get-EffectiveStatus $_) -ne 'running_window' } | Sort-Object ViewerId, Sample)
foreach ($result in $anomalies) {
  $errorText = Markdown-Text $result.Error
  $verification = Markdown-Text $result.Verification 80
  if ([string]::IsNullOrWhiteSpace($verification)) { $verification = 'initial' }
  [void]$md.Add("| $(Markdown-Text $result.ViewerId 120) | $(Markdown-Text $result.DeclaredValue 80) | $(Markdown-Text $result.Sample 180) | $(Markdown-Text (Get-EffectiveStatus $result) 80) | $(Markdown-Text $result.ExitCode 30) | $verification | $errorText |")
}
if ($anomalies.Count -eq 0) {
  [void]$md.Add('| (none) | | | | | | |')
}
[void]$md.Add('')
[void]$md.Add("Raw per-job results: $($ResultsPath.Replace($repoRoot + '\', ''))")
foreach ($recheckFile in $RecheckPath) {
  if (-not [string]::IsNullOrWhiteSpace($recheckFile)) {
    [void]$md.Add("Recheck results: $($recheckFile.Replace($repoRoot + '\', ''))")
  }
}

$md | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host "Report: $ReportPath"
Write-Host "Final records: $($results.Count); anomalies: $($anomalies.Count)"
