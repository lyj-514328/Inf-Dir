# Viewer Sample Test

This directory contains the Windows viewer compatibility test harness, the
persisted results from the 2026-08-28 run, and the generated report.

## Contents

- `run_viewer_sample_tests.ps1`: matches samples against each packaged viewer
  manifest, launches every matching viewer/sample pair, and records JSONL.
- `recheck_viewer_sample_anomalies.ps1`: rechecks unresolved or initially
  failed jobs with a longer timeout.
- `summarize_viewer_sample_results.ps1`: merges the initial and recheck JSONL
  files and regenerates the Markdown report.
- `viewer-sample-test-report.md`: final compatibility statistics and anomaly
  details.
- `results/20260828-141039/`: raw initial and recheck results for this run.

## Run

From the repository root:

```powershell
.\viewer-sample-test\run_viewer_sample_tests.ps1
```

The default sample root is `D:\BaiduNetdiskDownload\abc\samples`. Override it
with `-SamplesRoot` when necessary. New runs are stored under `results/`.

## Rebuild The Report

```powershell
.\viewer-sample-test\summarize_viewer_sample_results.ps1 `
  -ResultsPath .\viewer-sample-test\results\20260828-141039\results.jsonl `
  -RecheckPath `
    .\viewer-sample-test\results\20260828-141039\recheck.jsonl, `
    .\viewer-sample-test\results\20260828-141039\recheck-failures.jsonl
```

`running_window` means a responsive window appeared without a recognized
viewer error. `content_error` means the process displayed a window but emitted
an explicit decode, open, initialization, or conversion failure.
