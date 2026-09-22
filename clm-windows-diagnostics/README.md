# CLM Windows Toolkit

Version 1.3.0 for Windows 10/11, published by **Mena Dynamics, LLC**.

CLM Windows Toolkit is a learning-oriented Windows diagnostics and conservative cleanup utility. The PowerShell engine remains readable and inspectable, while the Python/Tkinter front end provides a Windows GUI.

## What it does

- Shows Windows, computer model, installed RAM, and current free/used RAM.
- Shows the largest grouped process working sets.
- Lists startup programs and opens Windows Startup Apps settings.
- Shows local disk capacity and free space.
- Runs a conservative TEMP cleanup preview before any deletion.
- Saves a timestamped diagnostics report to the Desktop.
- Does not disable services, edit the registry, change Windows Security, uninstall software, terminate processes, or request automatic elevation.

## Run from source

Keep the project files together and double-click:

```text
Launch-CLM.cmd
```

That starts the PowerShell menu. Administrator rights are not required.

To run the GUI from Python:

```powershell
python .\CLM-Windows-App.py
```

## Build the Windows app

The packaged application is:

```text
CLM-Windows-Toolkit.exe
```

The executable embeds:

- Product name: CLM Windows Toolkit
- Company: Mena Dynamics, LLC
- Version: 1.3.0
- Original filename: CLM-Windows-Toolkit.exe
- A generated CLM application icon

Install the build dependencies and run the builder on Windows:

```powershell
python -m pip install pyinstaller pillow
python .\build_app.py
```

The default output folder is `dist`.

## Code signing

GitHub Actions builds an unsigned executable because the private signing key is intentionally not stored in the repository.

For local development, `Sign-CLM.ps1` signs the built executable with the newest CurrentUser code-signing certificate whose subject contains `Mena Dynamics` and that has a private key:

```powershell
.\Sign-CLM.ps1
```

If the certificate is self-signed and has not yet been trusted for the current Windows user:

```powershell
.\Sign-CLM.ps1 -TrustCurrentUser
```

The helper prints the Authenticode status and the SHA-256 hash after signing. Signing changes the executable bytes, so the post-signing hash is expected to differ from the unsigned build.

Never commit a PFX file, private key, certificate password, or signing secret to the repository.

A self-signed certificate is appropriate for development and machines where you deliberately trust that certificate. Public distribution requires a certificate or signing service trusted by the target Windows systems.

## Cleanup safeguards

Cleanup supports only the standard `%LOCALAPPDATA%\Temp` location when it matches `%TEMP%`.

Only top-level regular files whose creation and modification times are both older than seven days are eligible. Directories and reparse points, including symbolic links and junctions, are skipped. There is no recursive deletion.

The GUI always performs a preview first and asks for confirmation. The PowerShell menu requires the user to type `DELETE`. Files are revalidated immediately before deletion. Deletion is permanent and does not use the Recycle Bin.

## Reports and privacy

Reports are saved as:

```text
CLM_Performance_<timestamp>_<id>.txt
```

They can contain computer names, usernames in paths, application names, and startup command paths. Review reports before sharing them.

## Validation

`Test-CLM.ps1` checks Windows PowerShell syntax and cleanup safeguards using a temporary fixture. GitHub Actions also:

- validates the Python sources,
- exercises source packaging,
- builds the Windows GUI with PyInstaller,
- verifies the embedded product/company/version metadata,
- and uploads the Windows application artifact.

Interactive Windows behavior and Authenticode trust still require a Windows smoke test.
