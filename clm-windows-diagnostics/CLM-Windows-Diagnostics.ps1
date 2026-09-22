#Requires -Version 5.1
param(
    [switch]$NoMenu,
    [ValidateSet('System','Memory','Startup','OpenStartup','CleanupPreview','Cleanup','Diagnostics','Report')]
    [string]$Action,
    [switch]$ConfirmCleanup
)
# CLM Windows Toolkit - Learning Edition 1.3
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

function Show-CLMDiagnostics {
    # A failed section does not prevent collection of the remaining sections.
    $sections = [ordered]@{
        SYSTEM = { Show-CLMSystem }
        MEMORY = { Show-CLMMemory }
        STARTUP = { Show-CLMStartup }
        DISKS = {
            Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop |
                Select-Object DeviceID, @{N='Size_GiB';E={[math]::Round($_.Size / 1GB, 1)}},
                    @{N='Free_GiB';E={[math]::Round($_.FreeSpace / 1GB, 1)}} |
                Format-Table -AutoSize | Out-Host
        }
    }
    foreach ($section in $sections.GetEnumerator()) {
        Write-Host "`n$($section.Key)" -ForegroundColor Cyan
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
    param(
        [switch]$PreviewOnly,
        [switch]$ConfirmDelete
    )

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

    if ($PreviewOnly) {
        Write-Host 'Preview only: no files were deleted.'
        return
    }

    if (-not $ConfirmDelete -and (Read-Host 'Type DELETE to delete these files') -cne 'DELETE') {
        Write-Host 'Cleanup cancelled.'
        return
    }

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
    Write-Host 'Report may contain unavailable-section warnings. Review it before sharing; it includes computer and application paths.'
}

function Invoke-CLMAction {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    switch ($Name) {
        'System' { Show-CLMSystem }
        'Memory' { Show-CLMMemory }
        'Startup' { Show-CLMStartup }
        'OpenStartup' { Start-Process 'ms-settings:startupapps' -ErrorAction Stop }
        'CleanupPreview' { Invoke-CLMCleanup -PreviewOnly }
        'Cleanup' {
            if (-not $ConfirmCleanup) {
                throw 'Cleanup action requires -ConfirmCleanup. Run CleanupPreview first.'
            }
            Invoke-CLMCleanup -ConfirmDelete
        }
        'Diagnostics' { Show-CLMDiagnostics }
        'Report' { Export-CLMReport }
        default { throw "Unknown action: $Name" }
    }
}

if ($env:OS -ne 'Windows_NT' -and (-not $NoMenu -or $Action)) {
    throw 'This utility requires Windows.'
}

if ($Action) {
    Invoke-CLMAction -Name $Action
} elseif (-not $NoMenu) {
    do {
        Write-Host "`nCLM WINDOWS TOOLKIT - Learning Edition 1.3" -ForegroundColor Cyan
        Write-Host '[1] RAM / system information'
        Write-Host '[2] Biggest memory users'
        Write-Host '[3] Startup programs'
        Write-Host '[4] Open Startup Apps settings'
        Write-Host '[5] Preview and clean old TEMP files'
        Write-Host '[6] Run all diagnostics'
        Write-Host '[7] Save Desktop report'
        Write-Host '[Q] Quit'
        $choice = (Read-Host 'Choose').Trim().ToUpperInvariant()
        try {
            switch ($choice) {
                '1' { Show-CLMSystem }
                '2' { Show-CLMMemory }
                '3' { Show-CLMStartup }
                '4' { Start-Process 'ms-settings:startupapps' -ErrorAction Stop }
                '5' { Invoke-CLMCleanup }
                '6' { Show-CLMDiagnostics }
                '7' { Export-CLMReport }
                'Q' { }
                default { Write-Warning 'Invalid selection.' }
            }
        } catch { Write-Warning $_.Exception.Message }
        if ($choice -ne 'Q') { [void](Read-Host 'Press ENTER to return to the menu') }
    } while ($choice -ne 'Q')
}
