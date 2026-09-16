#Requires -Version 5.1
<#
CLM Windows Optimizer - Learning Edition v2.0
Diagnostics and conservative maintenance for Windows. No administrator needed.
Dot-source this file to load functions without opening the menu.
#>
[CmdletBinding()]
param([switch]$ReportOnly, [string]$ReportDirectory)

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
    "CLM Windows Optimizer v2.0 - $(Get-Date -Format o)"
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
    try { $Host.UI.RawUI.WindowTitle = 'CLM Windows Optimizer v2.0' } catch { Write-Verbose 'Host has no window title.' }
    while ($true) {
        Write-Host "`n=== CLM WINDOWS OPTIMIZER - Learning Edition v2.0 ===" -ForegroundColor Cyan
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
