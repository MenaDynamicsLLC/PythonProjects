# CLM Windows Optimizer - Learning Edition v2.0

A Windows 10/11 diagnostic and conservative maintenance utility for learning
PowerShell. Requires Windows PowerShell 5.1 or newer. Python is only needed
to build an optional ZIP, not to run the utility. Administrator access is not
required. The name is historical: this does not promise a performance boost.

## Run

1. Download the repository using **Code > Download ZIP** and extract it.
2. Open the `clm-windows-optimizer` folder.
3. Double-click **Run-CLM-Optimizer.cmd**.

The launcher runs the adjacent script with a process-only execution-policy
bypass. It does not change the stored execution policy or request elevation.
Organization policy can still prevent execution; contact your administrator
if it does. Read downloaded scripts before running them.

Alternatively, from PowerShell in this folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CLM-Windows-Optimizer.ps1
```

Create a report without opening the menu:

```powershell
.\CLM-Windows-Optimizer.ps1 -ReportOnly -ReportDirectory "$env:USERPROFILE\Documents\CLM-Reports"
```

## Functions

| Menu | Action |
| --- | --- |
| 1 | System model, Windows build, RAM, uptime and installed memory modules |
| 2 | Top 20 process groups by approximate working-set memory |
| 3 | Startup command inventory |
| 4 | Windows Startup Apps settings |
| 5 | Preview and optionally delete old top-level user TEMP files |
| 6 | All diagnostic sections, including startup inventory; no cleanup |
| 7 | Save a UTF-8 text report to Desktop or an explicitly chosen directory |
| 8 | Fixed-disk capacity, free space and percentage free |
| 9 | Task Manager |
| S | Windows Storage settings |

Reports use Documents/CLM-Reports if Windows supplies no Desktop path. An
unwritable destination produces an error; it is never reported as success.
Individual unavailable diagnostic sections are marked in the report while the
remaining sections are retained. Reports contain computer names, process names
and startup commands/paths: review them before sharing. Nothing is uploaded by
this utility.

## Cleanup boundaries

- Only the current user's conventional LocalAppData/Temp directory is accepted;
  a custom TEMP location is refused. Use Windows Storage settings for those cases.
- Only top-level files with both creation and modification times older than
  seven days are listed. Application subdirectories remain intact.
- Symbolic links/junctions in the path are refused; file links are excluded.
- Preview includes filenames, dates, counts and file sizes. Type `DELETE` to
  proceed; anything else cancels. There is no automatic cleanup on launch.
- Close applications first. Age is not proof a file is unused. Deletion is
  permanent and does not use the Recycle Bin. Locked or inaccessible files are
  skipped; files changed after preview are rechecked and skipped.
- Results count successful deletions and skips/failures. Deleted logical file
  sizes do not necessarily equal recovered disk space.
- Path checks reduce accidental deletion risk but are not an atomic filesystem
  security boundary against another process actively swapping paths.

No processes are killed and no services, registry startup entries, security
features, installed software or system files are altered. Windows settings
shortcuts leave decisions to you.

## Interpreting diagnostics

High RAM use alone does not establish a problem. Process working sets include
shared pages, so their sum may exceed physical memory use. These are snapshots,
not a continuous profiler. Startup inventory may omit other launch mechanisms
such as scheduled tasks. Disk capacity is not a disk hardware-health test.

Memory is labeled GiB/MiB to match the binary divisors. WMI's
[Win32_OperatingSystem memory properties](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-operatingsystem)
are reported in kilobytes; the script converts those values accordingly.

## Build the downloadable package

Python 3.9+; no third-party dependencies:

```console
python build_package.py
python build_package.py --output "C:\Users\YourName\Desktop\CLM-Package"
```

The builder creates missing output directories and packages the checked-in
PowerShell, launcher and README. Existing output files with these names are
replaced. Default output is `dist/` beside the builder. Do not edit generated
copies if you intend to rebuild; edit the checked-in source instead.

## Learning and validation

Functions return objects; the menu handles formatting. `Get-CLMReportText`
collects section failures without needing a transcript. Cleanup uses
`-LiteralPath`, explicit confirmation, validation and `SupportsShouldProcess`
for programmatic `-WhatIf` support.

From the repository root on Windows:

```powershell
powershell.exe -NoProfile -File .\clm-windows-optimizer\tests\Test-Optimizer.ps1
pwsh -NoProfile -File .\clm-windows-optimizer\tests\Test-Optimizer.ps1
```

Tests use a temporary fixture and mocked diagnostic queries; they never clean
the real user TEMP folder. The GitHub Actions workflow checks both PowerShell
5.1 and 7 and builds the package. Manual checks still needed on your machine:
menu interaction, Settings/Task Manager launch and real CIM availability.

## Changes from v1.0

Added cleanup preview/age/path checks and accounting; removed unbounded recursive
deletion and unused size counting. Replaced fragile host transcripts with direct
report generation. Added per-action errors, independent diagnostic sections,
uptime, disk percentages, Settings shortcuts, report-only mode and a launcher.
The Python builder uses portable paths and a single source of truth.
