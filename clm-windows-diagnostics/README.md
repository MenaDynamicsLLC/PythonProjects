# CLM System Diagnostics & Cleanup

Learning Edition 2.0, for Windows 10/11 with Windows PowerShell 5.1. The project also builds an optional Windows GUI executable.

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

The Windows GUI build is named `CLM-Windows-Toolkit.exe`. It is a thin front end over the same PowerShell engine and audit module. The executable can run with the bundled copies of those files, but if inspectable `CLM-Windows-Diagnostics.ps1` and `CLM-Audit.ps1` files are placed beside the EXE, the GUI prefers those external copies.

## Features and limits

- System information, installed RAM modules, grouped process working sets, and startup inventory.
- Five-sample CPU, disk-busy, disk-queue, paging, and available-memory snapshot.
- Physical disk media type, bus, size and reported health, plus logical-drive free-space percentages.
- Startup audit with conservative system/security, hardware/driver, optional, remote-access-review, and manual-review categories.
- Microsoft Defender and Windows Firewall status when the Windows cmdlets are available.
- Remote-access audit across installed apps, processes, services, startup entries, and correlated established TCP connections.
- Review-only checks for selected legacy/optional utilities. A match is not an automatic uninstall recommendation.
- Incident snapshot export with processes, services, startup entries, TCP connections, remote-access findings, and SHA-256 hashes when paths can be resolved.
- Complete Desktop report and safe TEMP cleanup remain available.

Remote-support software is not automatically malicious. CLM flags recognized tools so the technician can verify that the device owner expects them.
Performance snapshots are clues, not hardware benchmarks or final diagnoses. Process working sets include shared pages and cannot be added to obtain unique physical RAM use.
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
computer names, usernames in paths, installed software, startup commands, application paths,
and remote IP addresses. Incident snapshots can contain even more system detail. Review
them before sharing. The repository ignores these filenames; that does not
protect reports you manually upload or rename.

## Windows GUI and ZIP packaging

The PowerShell files remain the maintained diagnostics engine. `CLM-Windows-App.py`
provides the optional Tkinter GUI.

To build the Windows executable locally:

```powershell
python -m pip install pyinstaller pillow
python .\build_app.py --output .\dist
```

Then create or overwrite the distribution ZIP:

```powershell
python .\build_package.py --output .\dist
```

The ZIP is named `CLM-Windows-Toolkit-Windows.zip`. When the EXE has already been
built into the output folder, the ZIP includes the executable plus the inspectable
PowerShell engine, audit module, launcher, signing helper, and documentation.

GitHub Actions performs the same Windows build and publishes a
`CLM-Windows-Toolkit-Windows` artifact. GitHub-built executables are unsigned;
`Sign-CLM.ps1` can apply the user's Mena Dynamics code-signing certificate locally.

## Validation

`Test-CLM.ps1` checks Windows PowerShell syntax, audit helper behavior, remote-access
signature coverage, and cleanup safeguards using a temporary fixture. It tests cancellation, old-file deletion, recent-file and
folder preservation, and rejection of an unexpected TEMP location. It never
targets your real TEMP contents. The GitHub Actions workflow runs it on Windows
and checks Python syntax, builds the Windows GUI executable, verifies its version metadata, builds the ZIP bundle, and publishes the Windows artifact. Interactive Settings behavior and machine-specific CIM output still require a Windows smoke test.
