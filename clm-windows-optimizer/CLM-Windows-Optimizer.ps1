#Requires -Version 5.1
<#
CLM Windows Optimizer - Working Edition v2.1
Diagnostics and conservative maintenance for Windows. No administrator needed.
Dot-source this file to load functions without opening the menu.
#>
[CmdletBinding()]
param([switch]$ReportOnly, [string]$ReportDirectory, [string[]]$KeepOpen = @())

function Test-CLMClosableApp {
    param([Parameter(Mandatory)]$Process, [string[]]$AdditionalKeepOpen = @())
    # Positive list: browsers, terminals, editors, system/security software and
    # unknown programs are never candidates. A listed app still needs selection.
    $optionalApps = @('steam', 'EpicGamesLauncher', 'Discord', 'Spotify', 'Canva',
        'Signal', 'Telegram', 'WhatsApp', 'Zoom', 'Teams', 'ms-teams', 'Skype')
    try {
        if ($Process.Id -eq $PID -or $Process.SessionId -ne ([Diagnostics.Process]::GetCurrentProcess().SessionId)) { return $false }
        if ($Process.ProcessName -notin $optionalApps -or $Process.ProcessName -in $AdditionalKeepOpen) { return $false }
        if ($Process.MainWindowHandle -eq [IntPtr]::Zero -or [string]::IsNullOrWhiteSpace($Process.MainWindowTitle)) { return $false }
        # Also protect Grok/browser/editor content if embedded in a listed app.
        if ($Process.MainWindowTitle -match '(?i)\b(Grok|Chrome|Edge|Firefox|Brave|Opera|Vivaldi|PowerShell|Visual Studio Code|VS Code)\b') { return $false }
        return $true
    } catch { return $false }
}

function Get-CLMClosableApps {
    param([string[]]$AdditionalKeepOpen = @())
    foreach ($process in (Get-Process -ErrorAction Stop)) {
        try {
            if (Test-CLMClosableApp -Process $process -AdditionalKeepOpen $AdditionalKeepOpen) {
                [PSCustomObject]@{
                    ProcessId = $process.Id
                    Name = $process.ProcessName
                    Window = $process.MainWindowTitle
                    WorkingSet_MiB = [math]::Round($process.WorkingSet64 / 1MB, 1)
                    StartTime = $process.StartTime
                }
            }
        } catch { Write-Verbose 'An app exited or could not be inspected; skipped.' }
    }
}

function Resolve-CLMAppSelection {
    param([string]$Selection, [object[]]$Apps)
    if ([string]::IsNullOrWhiteSpace($Selection)) { return }
    $indices = @()
    foreach ($part in ($Selection -split ',')) {
        $number = 0
        if (-not [int]::TryParse($part.Trim(), [ref]$number) -or $number -lt 1 -or $number -gt $Apps.Count) {
            throw 'Enter only listed row numbers separated by commas, such as 1,3. Nothing was closed.'
        }
        $indices += $number - 1
    }
    foreach ($index in ($indices | Select-Object -Unique)) { $Apps[$index] }
}

function Close-CLMSelectedApps {
    [CmdletBinding(SupportsShouldProcess)]
    param([object[]]$Apps, [string[]]$AdditionalKeepOpen = @())
    foreach ($app in $Apps) {
        $status = 'Skipped'
        try {
            $process = Get-Process -Id $app.ProcessId -ErrorAction Stop
            # PID reuse or a changed window invalidates the preview selection.
            if ($process.StartTime -ne $app.StartTime -or $process.ProcessName -ne $app.Name -or
                $process.MainWindowTitle -ne $app.Window) {
                $status = 'App changed since preview; skipped'
            } elseif (-not (Test-CLMClosableApp -Process $process -AdditionalKeepOpen $AdditionalKeepOpen)) {
                $status = 'Protected or no eligible window; skipped'
            } elseif ($PSCmdlet.ShouldProcess("$($app.Name) [$($app.ProcessId)]", 'Request normal window close')) {
                if ($process.CloseMainWindow()) { $status = 'Close requested; exit not yet confirmed' }
                else { $status = 'App refused close; left running' }
            } else { $status = 'No close requested' }
        } catch { $status = "Could not request close: $($_.Exception.Message)" }
        [PSCustomObject]@{ App = $app.Name; ProcessId = $app.ProcessId; Status = $status }
    }
}

function Get-CLMAppExitStatus {
    param([object[]]$Apps)
    foreach ($app in $Apps) {
        # Distinguish a genuinely exited process from one that only hid to tray.
        $process = Get-Process -Id $app.ProcessId -ErrorAction SilentlyContinue
        $status = 'Exited'
        if ($null -ne $process) {
            try {
                if ($process.StartTime -eq $app.StartTime) { $status = 'Still running (may be in tray or awaiting input)' }
            } catch { $status = 'Unable to verify exit' }
        }
        [PSCustomObject]@{ App = $app.Name; ProcessId = $app.ProcessId; Status = $status }
    }
}

function Get-CLMAvailableMemory {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    [PSCustomObject]@{
        Available_MiB = [math]::Round($os.FreePhysicalMemory / 1KB, 1)
        Total_MiB = [math]::Round($os.TotalVisibleMemorySize / 1KB, 1)
    }
}

function Invoke-CLMMemoryRelief {
    param([string[]]$AdditionalKeepOpen = @())
    Write-Host '=== FREE RAM BY CLOSING SELECTED OPTIONAL APPS ===' -ForegroundColor Cyan
    Write-Host 'Browsers, Grok, PowerShell, VS Code and unrecognized apps stay open.'
    Write-Host 'Only listed optional apps with visible windows can be selected.'
    Write-Host 'Save your work first. Closing an app can interrupt calls, playback or downloads.' -ForegroundColor Yellow
    $apps = @(Get-CLMClosableApps -AdditionalKeepOpen $AdditionalKeepOpen | Sort-Object WorkingSet_MiB -Descending)
    if ($apps.Count -eq 0) {
        Write-Host 'No eligible optional app windows found. Nothing was closed.'
        Write-Host 'Use [2] to inspect RAM use or [9] for Task Manager. Tray apps may need Exit from their tray menu.'
        return
    }
    $rows = for ($i = 0; $i -lt $apps.Count; $i++) {
        [PSCustomObject]@{ Row = $i + 1; App = $apps[$i].Name; Window = $apps[$i].Window; WorkingSet_MiB = $apps[$i].WorkingSet_MiB }
    }
    $rows | Format-Table -Wrap -AutoSize | Out-Host
    Write-Host 'Memory figures are for each window-owning process, not the entire app or guaranteed savings.'
    $selected = @(Resolve-CLMAppSelection -Selection (Read-Host 'Rows to close (e.g. 1,3); ENTER cancels') -Apps $apps)
    if ($selected.Count -eq 0) { Write-Host 'Cancelled.'; return }
    $selected | Select-Object Name, Window | Format-Table -Wrap -AutoSize | Out-Host
    if ((Read-Host 'Type CLOSE to request normal closure of these apps').Trim() -cne 'CLOSE') {
        Write-Host 'Cancelled.'; return
    }
    $before = Get-CLMAvailableMemory
    Close-CLMSelectedApps -Apps $selected -AdditionalKeepOpen $AdditionalKeepOpen | Format-Table -Wrap -AutoSize | Out-Host
    Write-Host 'Handle any app prompts. Apps may refuse closure or minimize to tray.'
    [void](Read-Host 'Press ENTER when ready to measure RAM again')
    Get-CLMAppExitStatus -Apps $selected | Format-Table -Wrap -AutoSize | Out-Host
    $after = Get-CLMAvailableMemory
    Write-Host ('Available RAM: {0:N1} MiB before -> {1:N1} MiB after; change: {2:+0.0;-0.0;0.0} MiB.' -f
        $before.Available_MiB, $after.Available_MiB, ($after.Available_MiB - $before.Available_MiB))
    Write-Host 'This is a system-wide snapshot; other activity also changes available RAM. No speed gain is guaranteed.'
}

function Get-CLMSystem {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    # WMI reports these two memory values in KiB; 1MB here is 1,048,576.
    [PSCustomObject]@{
        Computer = $env:COMPUTERNAME
        Windows = $os.Caption
        Build = $os.BuildNumber
        Model = "$($cs.Manufacturer) $($cs.Model)"
        Total_RAM_GiB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        Used_RAM_GiB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        Free_RAM_GiB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        Last_Boot = $os.LastBootUpTime
        Uptime = ((Get-Date) - $os.LastBootUpTime).ToString('d\.hh\:mm\:ss')
    }
}

function Get-CLMMemoryModules {
    Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop |
        Select-Object DeviceLocator, @{N='Capacity_GiB';E={[math]::Round($_.Capacity / 1GB, 2)}},
            Speed, Manufacturer, PartNumber
}

function Get-CLMMemoryUsers {
    # Working sets include shared pages: grouped totals are approximate and
    # should not be added up to infer total physical memory consumption.
    Get-Process -ErrorAction Stop | Group-Object ProcessName | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Name
            Count = $_.Count
            WorkingSet_MiB = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 1)
        }
    } | Sort-Object WorkingSet_MiB -Descending | Select-Object -First 20
}

function Get-CLMStartup {
    # This CIM class is an inventory, not every possible Windows startup source.
    Get-CimInstance Win32_StartupCommand -ErrorAction Stop | Select-Object Name, Location, Command
}

function Get-CLMDisks {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop |
        Select-Object DeviceID,
            @{N='Size_GiB';E={if ($null -ne $_.Size) {[math]::Round($_.Size / 1GB, 1)}}},
            @{N='Free_GiB';E={if ($null -ne $_.FreeSpace) {[math]::Round($_.FreeSpace / 1GB, 1)}}},
            @{N='Free_Percent';E={if ($_.Size -gt 0 -and $null -ne $_.FreeSpace) {[math]::Round(100 * $_.FreeSpace / $_.Size, 1)}}}
}

function Get-CLMReportText {
    # Build text directly instead of starting a host-wide transcript. Failures
    # stay visible in their section and don't discard other diagnostic results.
    "CLM Windows Optimizer v2.1 - $(Get-Date -Format o)"
    'RAM sizes are GiB/MiB. Working sets may count shared memory more than once.'
    $sections = [ordered]@{
        SYSTEM = { Get-CLMSystem | Format-List | Out-String -Width 240 }
        'MEMORY MODULES' = { Get-CLMMemoryModules | Format-Table -AutoSize | Out-String -Width 240 }
        'TOP MEMORY USERS (approximate working sets)' = { Get-CLMMemoryUsers | Format-Table -AutoSize | Out-String -Width 240 }
        DISKS = { Get-CLMDisks | Format-Table -AutoSize | Out-String -Width 240 }
        'STARTUP INVENTORY (may be incomplete)' = { Get-CLMStartup | Format-List | Out-String -Width 4096 }
    }
    foreach ($section in $sections.GetEnumerator()) {
        "`r`n=== $($section.Key) ==="
        try { & $section.Value } catch { "Unavailable: $($_.Exception.Message)" }
    }
}

function Export-CLMReport {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory)) {
        $Directory = [Environment]::GetFolderPath('Desktop')
        if ([string]::IsNullOrWhiteSpace($Directory)) {
            $Directory = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'CLM-Reports'
        }
    }
    # Directory.CreateDirectory treats brackets as literal filename characters.
    $folder = [IO.Directory]::CreateDirectory($Directory).FullName
    $name = 'CLM_Performance_{0}_{1}.txt' -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $file = Join-Path $folder $name
    $text = (Get-CLMReportText) -join [Environment]::NewLine
    [IO.File]::WriteAllText($file, $text, [Text.UTF8Encoding]::new($true))
    return $file
}

function Assert-CLMPlainPath {
    param([Parameter(Mandatory)][string]$Path)
    # Check every existing ancestor too: a normal file can live under a junction.
    $current = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    while ($null -ne $current) {
        if ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Cleanup refuses symbolic links or junctions: $($current.FullName)"
        }
        $parent = Split-Path -Path $current.FullName -Parent
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current.FullName) { break }
        $current = Get-Item -LiteralPath $parent -Force -ErrorAction Stop
    }
}

function Get-CLMTempRoot {
    # Only the conventional per-user LocalAppData\Temp folder is allowed.
    # Custom TEMP locations are intentionally handed off to Windows Storage.
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($local) -or [string]::IsNullOrWhiteSpace($env:TEMP)) {
        throw 'The user TEMP location is unavailable.'
    }
    $expected = [IO.Path]::GetFullPath((Join-Path $local 'Temp')).TrimEnd('\')
    $actual = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    if (-not $actual.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Custom TEMP path detected. Use Windows Storage settings for cleanup.'
    }
    Assert-CLMPlainPath -Path $actual
    $folder = Get-Item -LiteralPath $actual -Force -ErrorAction Stop
    if (-not $folder.PSIsContainer) { throw 'TEMP is not a directory.' }
    return $folder.FullName
}

function Get-CLMTempCandidates {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][datetime]$Cutoff)
    # Intentionally top-level only: leave application subdirectories intact.
    Get-ChildItem -LiteralPath $Root -File -Force -ErrorAction Stop | Where-Object {
        -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
        $_.LastWriteTime -lt $Cutoff -and $_.CreationTime -lt $Cutoff
    }
}

function Remove-CLMTempCandidates {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][datetime]$Cutoff,
        [AllowEmptyCollection()][object[]]$Candidates = @())
    # Revalidate after confirmation, including each file immediately before use.
    $validatedRoot = Get-CLMTempRoot
    if (-not $Root.Equals($validatedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'TEMP changed after preview; cleanup cancelled.'
    }
    $deleted = 0; $skipped = 0; [long]$bytes = 0
    foreach ($candidate in $Candidates) {
        try {
            $item = Get-Item -LiteralPath $candidate.FullName -Force -ErrorAction Stop
            if ($item.PSIsContainer -or -not $item.DirectoryName.Equals($Root, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'Candidate is outside the top level of TEMP.'
            }
            Assert-CLMPlainPath -Path $item.FullName
            if ($item.LastWriteTime -ge $Cutoff -or $item.CreationTime -ge $Cutoff -or
                $item.LastWriteTime -ne $candidate.LastWriteTime -or $item.Length -ne $candidate.Length) {
                throw 'File changed or is too recent.'
            }
            if ($PSCmdlet.ShouldProcess($item.FullName, 'Permanently delete old TEMP file')) {
                $length = $item.Length
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                $deleted++; $bytes += $length
            } else { $skipped++ }
        } catch {
            $skipped++
            Write-Verbose "Skipped $($candidate.FullName): $($_.Exception.Message)"
        }
    }
    [PSCustomObject]@{ Deleted = $deleted; Skipped = $skipped; DeletedFileBytes = $bytes }
}

function Invoke-CLMTempCleanup {
    $root = Get-CLMTempRoot
    $cutoff = (Get-Date).AddDays(-7)
    $candidates = @(Get-CLMTempCandidates -Root $root -Cutoff $cutoff)
    Write-Host "TEMP: $root"
    Write-Host 'Only top-level files created AND modified more than 7 days ago are eligible.'
    Write-Host 'Close applications first. Old files can still be needed; deletion is permanent.' -ForegroundColor Yellow
    Write-Host 'Subdirectories and links are left intact. Use Storage settings for broader cleanup.'
    if ($candidates.Count -eq 0) { Write-Host 'No eligible files.'; return }
    $bytes = ($candidates | Measure-Object Length -Sum).Sum
    $candidates | Select-Object Name, Length, LastWriteTime | Format-Table -Wrap -AutoSize | Out-Host
    Write-Host ('Preview: {0} files, {1:N2} MiB of file sizes.' -f $candidates.Count, ($bytes / 1MB))
    if ((Read-Host 'Type DELETE to delete these files').Trim() -cne 'DELETE') {
        Write-Host 'Cleanup cancelled.'; return
    }
    $result = Remove-CLMTempCandidates -Root $root -Cutoff $cutoff -Candidates $candidates
    Write-Host ('Deleted: {0}; skipped/failed: {1}; deleted file sizes: {2:N2} MiB.' -f $result.Deleted, $result.Skipped, ($result.DeletedFileBytes / 1MB))
    Write-Host 'File sizes are not a measurement of recovered disk space. Locked files are skipped.'
}

function Start-CLMMenu {
    try { $Host.UI.RawUI.WindowTitle = 'CLM Windows Optimizer v2.1' } catch { Write-Verbose 'Host has no window title.' }
    while ($true) {
        Write-Host "`n=== CLM WINDOWS OPTIMIZER - Working Edition v2.1 ===" -ForegroundColor Cyan
        Write-Host @'
[1] RAM / system information
[2] Biggest RAM users (approximate working sets)
[3] Startup inventory
[4] Open Startup Apps settings
[5] Preview / clean old top-level TEMP files
[6] All diagnostics (read-only)
[7] Save performance report
[8] Disk space
[9] Open Task Manager
[M] Free RAM: choose optional apps to close (keeps your work apps open)
[S] Open Windows Storage settings
[Q] Quit
'@
        $choice = (Read-Host 'Choose').Trim().ToUpperInvariant()
        if ($choice -eq 'Q') { return }
        try {
            switch ($choice) {
                '1' { Get-CLMSystem | Format-List | Out-Host; Get-CLMMemoryModules | Format-Table -AutoSize | Out-Host }
                '2' { Get-CLMMemoryUsers | Format-Table -AutoSize | Out-Host }
                '3' { Get-CLMStartup | Format-List | Out-Host }
                '4' { Start-Process 'ms-settings:startupapps' -ErrorAction Stop }
                '5' { Invoke-CLMTempCleanup }
                '6' { Get-CLMReportText | Out-Host }
                '7' { Write-Host ('Report saved: ' + (Export-CLMReport -Directory $ReportDirectory)) -ForegroundColor Green }
                '8' { Get-CLMDisks | Format-Table -AutoSize | Out-Host }
                '9' { Start-Process (Join-Path $env:SystemRoot 'System32\Taskmgr.exe') -ErrorAction Stop }
                'M' { Invoke-CLMMemoryRelief -AdditionalKeepOpen $KeepOpen }
                'S' { Start-Process 'ms-settings:storagesense' -ErrorAction Stop }
                default { Write-Host 'Choose one of the listed options.' -ForegroundColor Yellow }
            }
        } catch { Write-Host "Unable to complete this action: $($_.Exception.Message)" -ForegroundColor Red }
        [void](Read-Host 'Press ENTER to return to the menu')
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ($env:OS -ne 'Windows_NT') { throw 'Run this utility on Windows 10/11 with PowerShell 5.1 or newer.' }
    if ($ReportOnly) { Export-CLMReport -Directory $ReportDirectory }
    else { Start-CLMMenu }
}
