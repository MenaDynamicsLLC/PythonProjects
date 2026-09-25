#Requires -Version 5.1
param([switch]$NoMenu)
# CLM System Diagnostics & Cleanup - Learning Edition 2.0
# No administrator rights required. No registry, service or security changes.

function Get-CLMMemoryUsers {
    # Working sets include shared pages; totals are not unique physical RAM.
    Get-Process | Group-Object ProcessName | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Name
            Count = $_.Count
            WorkingSet_MiB = [math]::Round(($_.Group | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 1)
        }
    } | Sort-Object WorkingSet_MiB -Descending | Select-Object -First 20
}

function Show-CLMSystem {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    [PSCustomObject]@{
        Computer = $env:COMPUTERNAME
        Windows = $os.Caption
        Model = "$($cs.Manufacturer) $($cs.Model)"
        Total_RAM_GiB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        Used_RAM_GiB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)
        Free_RAM_GiB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    } | Format-List | Out-Host
    Write-Host 'INSTALLED MEMORY MODULES' -ForegroundColor Yellow
    Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop |
        Select-Object DeviceLocator, @{N='Capacity_GiB';E={[math]::Round($_.Capacity / 1GB, 2)}}, Speed, Manufacturer, PartNumber |
        Format-Table -AutoSize | Out-Host
}

function Show-CLMMemory {
    Write-Host 'TOP MEMORY USERS (shared pages can be counted more than once)' -ForegroundColor Yellow
    Get-CLMMemoryUsers | Format-Table -AutoSize | Out-Host
}

function Show-CLMStartup {
    Get-CimInstance Win32_StartupCommand -ErrorAction Stop |
        Select-Object Name, Location, Command | Format-Table -Wrap -AutoSize | Out-Host
}

. (Join-Path $PSScriptRoot 'CLM-Audit.ps1')

function Show-CLMDiagnostics {
    # A failed section does not prevent collection of the remaining sections.
    $sections = [ordered]@{
        SYSTEM = { Show-CLMSystem }
        'HEALTH SUMMARY' = { Show-CLMHealthSummary }
        'PERFORMANCE SNAPSHOT' = { Show-CLMPerformance }
        MEMORY = { Show-CLMMemory }
        DISKS = { Show-CLMDisks }
        'STARTUP AUDIT' = { Show-CLMStartupAudit }
        SECURITY = { Show-CLMSecurity }
        'REMOTE ACCESS AUDIT' = { Show-CLMRemoteAccessAudit }
        'OPTIONAL SOFTWARE REVIEW' = { Show-CLMSoftwareReview }
    }
    foreach ($section in $sections.GetEnumerator()) {
        Write-Host ""
        Write-Host $section.Key -ForegroundColor Cyan
        try { & $section.Value } catch { Write-Warning "$($section.Key) unavailable: $($_.Exception.Message)" }
    }
}

function Assert-CLMNoLinks {
    param([string]$Path)
    # Check every ancestor, not just the leaf, for a junction or symbolic link.
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing linked path: $($item.FullName)"
        }
        $item = $item.Parent
    }
}

function Get-CLMCleanupRoot {
    if ([string]::IsNullOrWhiteSpace($env:TEMP) -or [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'TEMP or LOCALAPPDATA is missing. Cleanup cancelled.'
    }
    $root = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
    $expected = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Temp')).TrimEnd('\')
    # Deliberately refuse redirected/custom TEMP locations instead of guessing.
    if (-not [IO.Path]::IsPathRooted($env:TEMP) -or $root -ine $expected) {
        throw 'Cleanup only supports the standard LOCALAPPDATA\Temp folder. Use Windows Storage settings for custom TEMP locations.'
    }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'TEMP directory does not exist.' }
    Assert-CLMNoLinks $root
    return $root
}

function Get-CLMCleanupCandidates {
    param([string]$Root, [datetime]$Cutoff)
    # Do not recurse: old folders may contain newer or still-needed files.
    Get-ChildItem -LiteralPath $Root -Force -ErrorAction Stop | Where-Object {
        -not $_.PSIsContainer -and
        -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
        $_.LastWriteTime -lt $Cutoff -and $_.CreationTime -lt $Cutoff
    }
}

function Invoke-CLMCleanup {
    $root = Get-CLMCleanupRoot
    $cutoff = (Get-Date).AddDays(-7)
    $candidates = @(Get-CLMCleanupCandidates -Root $root -Cutoff $cutoff)
    Write-Host "TEMP: $root"
    Write-Host 'Only top-level files created and modified over seven days ago are eligible.'
    Write-Host 'Folders and links are skipped. Close applications first; old files may still be needed.' -ForegroundColor Yellow
    if ($candidates.Count -eq 0) { Write-Host 'No eligible files.'; return }
    $candidates | Select-Object Name, LastWriteTime, @{N='Size_MiB';E={[math]::Round($_.Length / 1MB, 2)}} |
        Format-Table -Wrap | Out-Host
    Write-Host "Preview: $($candidates.Count) files. Deletion does not use the Recycle Bin."
    if ((Read-Host 'Type DELETE to delete these files') -cne 'DELETE') { Write-Host 'Cleanup cancelled.'; return }
    $deleted = 0; $skipped = 0; $bytes = 0L
    foreach ($candidate in $candidates) {
        try {
            # Revalidate after confirmation in case the environment or file changed.
            if ((Get-CLMCleanupRoot) -ine $root) { throw 'TEMP location changed.' }
            $current = Get-Item -LiteralPath $candidate.FullName -Force -ErrorAction Stop
            if ($current.PSIsContainer -or ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                $current.LastWriteTime -ge $cutoff -or $current.CreationTime -ge $cutoff -or
                $current.LastWriteTimeUtc -ne $candidate.LastWriteTimeUtc -or $current.Length -ne $candidate.Length) {
                throw 'File changed or is no longer eligible.'
            }
            $length = $current.Length
            Remove-Item -LiteralPath $current.FullName -Force -ErrorAction Stop
            $bytes += $length
            $deleted++
        } catch {
            $skipped++
            Write-Warning "$($candidate.Name): $($_.Exception.Message)"
        }
    }
    Write-Host "Deleted: $deleted; skipped/failed: $skipped; deleted file sizes: $([math]::Round($bytes / 1MB, 2)) MiB."
}

function Export-CLMReport {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop -PathType Container)) {
        throw 'Desktop folder is unavailable; no report was created.'
    }
    $file = Join-Path $desktop ("CLM_Performance_{0}_{1}.txt" -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'), [guid]::NewGuid().ToString('N').Substring(0, 8))
    $started = $false
    try {
        Start-Transcript -LiteralPath $file -NoClobber -ErrorAction Stop | Out-Null
        $started = $true
        Show-CLMDiagnostics
    } finally {
        if ($started) { Stop-Transcript -ErrorAction Stop | Out-Null }
    }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw 'Report file was not created.' }
    Write-Host "Report saved to: $file" -ForegroundColor Green
    Write-Host 'Review before sharing: reports may include computer names, software names, application paths, and remote IP addresses.'
}

if (-not $NoMenu) {
    if ($env:OS -ne 'Windows_NT') { throw 'This utility requires Windows.' }
    do {
        Write-Host ""
        Write-Host 'CLM SYSTEM DIAGNOSTICS & CLEANUP - Learning Edition 2.0' -ForegroundColor Cyan
        Write-Host '[1] System / RAM information'
        Write-Host '[2] Biggest memory users'
        Write-Host '[3] Performance snapshot (~5 sec)'
        Write-Host '[4] Physical + logical disks'
        Write-Host '[5] Startup audit'
        Write-Host '[6] Security status'
        Write-Host '[7] Remote-access audit'
        Write-Host '[8] Save incident snapshot'
        Write-Host '[9] Preview and clean old TEMP files'
        Write-Host '[10] Run complete health + security audit'
        Write-Host '[11] Save Desktop report'
        Write-Host '[12] Open Startup Apps settings'
        Write-Host '[Q] Quit'
        $choice = (Read-Host 'Choose').Trim().ToUpperInvariant()
        try {
            switch ($choice) {
                '1' { Show-CLMSystem }
                '2' { Show-CLMMemory }
                '3' { Show-CLMPerformance }
                '4' { Show-CLMDisks }
                '5' { Show-CLMStartupAudit }
                '6' { Show-CLMSecurity }
                '7' { Show-CLMRemoteAccessAudit }
                '8' { Export-CLMIncidentSnapshot }
                '9' { Invoke-CLMCleanup }
                '10' { Show-CLMDiagnostics }
                '11' { Export-CLMReport }
                '12' { Start-Process 'ms-settings:startupapps' -ErrorAction Stop }
                'Q' { }
                default { Write-Warning 'Invalid selection.' }
            }
        } catch { Write-Warning $_.Exception.Message }
        if ($choice -ne 'Q') { [void](Read-Host 'Press ENTER to return to the menu') }
    } while ($choice -ne 'Q')
}
