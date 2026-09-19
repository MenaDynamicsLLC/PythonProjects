# CLM System Diagnostics & Cleanup

Learning Edition 1.1, for Windows 10/11 with Windows PowerShell 5.1.

## Run

Download the project folder, keep its files together, and double-click
`Launch-CLM.cmd`. Python and administrator rights are not required.
The launcher sets execution policy Bypass only for its PowerShell process;
it does not change the machine policy or override organization policy.
Read the script before running it.

Alternatively, from PowerShell in this folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CLM-Windows-Diagnostics.ps1
```

## Features and limits

- System information, installed RAM modules, grouped process working sets,
  startup commands, and local disk capacity/free space.
- All diagnostics includes every diagnostic section. Failed sections are
  reported as warnings while the other sections continue.
- Startup Apps settings shortcut and a uniquely named Desktop text report.
- Memory and disk units are GiB/MiB. Process working sets include shared pages
  and cannot be added up to obtain unique physical RAM use.
- These are snapshots, not hardware health tests or performance benchmarks.
  Cleanup frees disk space; it does not directly optimize CPU or RAM.

## Cleanup safeguards

Cleanup supports only `%LOCALAPPDATA%\Temp` when it matches `%TEMP%`.
It refuses custom/redirected TEMP paths and linked directory ancestors.
Only top-level regular files whose creation and modification times are both
older than seven days are previewed. All subdirectories and reparse points
(including symbolic links and junctions) are skipped; there is no recursive deletion.
Use Windows Storage settings if you need broader cleanup.

Close applications and inspect the preview. Old, unlocked files may still be
needed. Type `DELETE` to confirm; any other response cancels. Files are
rechecked before deletion, but this is not an atomic filesystem operation.
Deletion is permanent, without the Recycle Bin. Locked files and other failures
are reported individually, with deleted/skipped counts and the summed sizes
of successfully deleted files (not a measurement of physical space reclaimed).

No registry edits, service changes, security changes, software removal, process
termination, or automatic elevation are performed.

## Reports and privacy

Reports are saved on your Desktop as `CLM_Performance_*.txt`. They can include
computer names, usernames in paths, and application startup commands. Review
them before sharing. The repository ignores these filenames; that does not
protect reports you manually upload or rename.

## Optional Python packaging exercise

The original Python wrapper generated Windows files. Here the PowerShell script
is the single maintained source, and Python packages it with the launcher/docs:

```text
python build_package.py --output ./dist
```

The destination is created automatically. The default is a `dist` folder beside
the builder, so no `/mnt/data` dependency remains.

## Validation

`Test-CLM.ps1` checks Windows PowerShell syntax and cleanup safeguards using a
temporary fixture. It tests cancellation, old-file deletion, recent-file and
folder preservation, and rejection of an unexpected TEMP location. It never
targets your real TEMP contents. The GitHub Actions workflow runs it on Windows
and checks that the Python builder produces its expected files. Interactive
Settings behavior and actual CIM/transcript output still need a Windows smoke test.
