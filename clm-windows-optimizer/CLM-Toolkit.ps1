# CLM Windows Toolkit v3.0 - additional functions, loaded by the main script.
# No actions run just by loading this file.

function Get-CLMStateDirectory {
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($local)) { throw 'Local application data folder is unavailable.' }
    Join-Path $local 'CLM-Toolkit'
}

function ConvertTo-CLMKeepOpenNames {
    param([AllowEmptyCollection()][object[]]$Names = @())
    if ($Names.Count -gt 64) { throw 'Use no more than 64 keep-open names.' }
    foreach ($name in $Names) {
        if ($name -isnot [string] -or $name.Trim() -notmatch '^[a-zA-Z0-9_ .-]{1,80}$') {
            throw 'Use process names only, such as Spotify or Signal, not paths or commands.'
        }
        $name.Trim() -replace '(?i)\.exe$', ''
    }
}

function Get-CLMWorkProfile {
    param([string]$Directory = (Get-CLMStateDirectory))
    $file = Join-Path $Directory 'work-profile.json'
    if (-not (Test-Path -LiteralPath $file)) {
        return [PSCustomObject]@{ SchemaVersion = 1; KeepOpen = @('chrome','msedge','firefox','brave','Grok','powershell','pwsh','Code','WindowsTerminal') }
    }
    try {
        $workProfile = [IO.File]::ReadAllText($file) | ConvertFrom-Json -ErrorAction Stop
        if ($workProfile.SchemaVersion -ne 1 -or $null -eq $workProfile.KeepOpen -or $workProfile.KeepOpen -is [string]) { throw 'Invalid profile format.' }
        $names = @(ConvertTo-CLMKeepOpenNames -Names @($workProfile.KeepOpen) | Sort-Object -Unique)
        [PSCustomObject]@{ SchemaVersion = 1; KeepOpen = $names }
    } catch { throw "Cannot read Work Mode profile; no apps were closed. File: $file. $($_.Exception.Message)" }
}

function Save-CLMWorkProfile {
    param([AllowEmptyCollection()][object[]]$Names = @(), [string]$Directory = (Get-CLMStateDirectory))
    $names = @(ConvertTo-CLMKeepOpenNames -Names $Names | Sort-Object -Unique)
    [void][IO.Directory]::CreateDirectory($Directory)
    $file = Join-Path $Directory 'work-profile.json'
    $temp = Join-Path $Directory ([guid]::NewGuid().ToString('N') + '.tmp')
    $backup = $temp + '.bak'
    try {
        $json = [PSCustomObject]@{SchemaVersion=1; KeepOpen=$names} | ConvertTo-Json -Depth 4
        [IO.File]::WriteAllText($temp, $json, [Text.UTF8Encoding]::new($true))
        if ([IO.File]::Exists($file)) { [IO.File]::Replace($temp, $file, $backup) }
        else { [IO.File]::Move($temp, $file) }
    } finally {
        if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
        if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
    }
    $file
}

function Edit-CLMWorkProfile {
    $workProfile = Get-CLMWorkProfile
    Write-Host ('Current keep-open list: ' + ($workProfile.KeepOpen -join ', '))
    Write-Host 'Core work/system protection always applies, even if names are removed here.'
    $inputNames = Read-Host 'New complete list of process names, comma separated; ENTER keeps current list'
    if ([string]::IsNullOrWhiteSpace($inputNames)) { return }
    $names = @(ConvertTo-CLMKeepOpenNames -Names ($inputNames -split ','))
    Write-Host ('New list: ' + ($names -join ', '))
    if ((Read-Host 'Type SAVE to store this list').Trim() -ceq 'SAVE') {
        Write-Host ('Saved: ' + (Save-CLMWorkProfile -Names $names))
    }
}

function Get-CLMPerformanceSample {
    $issues = @(); $cpu = $null; $available = $null; $total = $null; $disks = @()
    try {
        $os = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 5 -ErrorAction Stop
        if ($null -eq $os.FreePhysicalMemory -or $os.TotalVisibleMemorySize -le 0) { throw 'Missing memory values.' }
        $available = [math]::Round($os.FreePhysicalMemory / 1KB, 1)
        $total = [math]::Round($os.TotalVisibleMemorySize / 1KB, 1)
    } catch { $issues += "RAM: $($_.Exception.Message)" }
    try {
        $processor = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -OperationTimeoutSec 5 -ErrorAction Stop
        if ($null -eq $processor.PercentProcessorTime) { throw 'CPU counter unavailable.' }
        $cpu = [math]::Min(100, [math]::Max(0, [double]$processor.PercentProcessorTime))
    } catch { $issues += "CPU: $($_.Exception.Message)" }
    try {
        $physical = @(Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -OperationTimeoutSec 5 -ErrorAction Stop | Where-Object { $_.Name -ne '_Total' })
        if ($physical.Count -eq 0) { throw 'Disk counters unavailable.' }
        foreach ($disk in $physical) {
            if ($null -eq $disk.PercentIdleTime) { $issues += "Disk $($disk.Name): idle counter unavailable."; continue }
            $disks += [PSCustomObject]@{ Name=$disk.Name; BusyPercent=[math]::Min(100, [math]::Max(0, 100 - [double]$disk.PercentIdleTime)) }
        }
    } catch { $issues += "Disk: $($_.Exception.Message)" }
    [PSCustomObject]@{ CapturedAt=(Get-Date -Format o); CpuPercent=$cpu; AvailableMiB=$available; TotalMiB=$total; Disks=$disks; Issues=$issues }
}

function Get-CLMPerformanceSummary {
    param([Parameter(Mandatory)][object[]]$Samples)
    $cpuValues = @($Samples | Where-Object { $null -ne $_.CpuPercent } | ForEach-Object { $_.CpuPercent })
    $memory = @($Samples | Where-Object { $null -ne $_.AvailableMiB -and $_.TotalMiB -gt 0 })
    $cpuMean = $null; $memoryMin = $null; $lowMemoryCount = 0
    if ($cpuValues.Count) { $cpuMean = [math]::Round(($cpuValues | Measure-Object -Average).Average, 1) }
    if ($memory.Count) {
        $memoryMin = ($memory | Measure-Object AvailableMiB -Minimum).Minimum
        $lowMemoryCount = @($memory | Where-Object { $_.AvailableMiB / $_.TotalMiB -lt 0.10 }).Count
    }
    $diskSummary = @($Samples | ForEach-Object { $_.Disks } | Group-Object Name | ForEach-Object {
        [PSCustomObject]@{ Disk=$_.Name; AverageBusyPercent=[math]::Round(($_.Group | Measure-Object BusyPercent -Average).Average, 1); Samples=$_.Count }
    })
    $findings = @()
    if ($memory.Count -ge 3 -and $lowMemoryCount -ge [math]::Ceiling($memory.Count / 2)) {
        $findings += 'RAM pressure is plausible: under 10% available in at least half of valid samples. Review [2], then use Work Mode if optional apps are open.'
    }
    if ($cpuValues.Count -ge 3 -and $cpuMean -ge 80) {
        $findings += 'CPU activity stayed high on average (80%+). Open Task Manager and sort by CPU while the slowdown is happening.'
    }
    foreach ($disk in $diskSummary) {
        if ($disk.Samples -ge 3 -and $disk.AverageBusyPercent -ge 80) {
            $findings += "Disk $($disk.Disk) averaged 80%+ busy. Inspect Disk activity in Task Manager; this does not diagnose disk failure or its cause."
        }
    }
    if ($findings.Count -eq 0) { $findings += 'No sustained threshold was detected in the available samples. This does not rule out brief stalls, heat, network delays, or unavailable counters.' }
    [PSCustomObject]@{ TotalSamples=$Samples.Count; CpuSamples=$cpuValues.Count; AverageCpuPercent=$cpuMean; MemorySamples=$memory.Count;
        LowestAvailableMiB=$memoryMin; DiskSummary=$diskSummary; Findings=$findings;
        Issues=@($Samples | ForEach-Object { $_.Issues } | Sort-Object -Unique) }
}

function Invoke-CLMSlowdownCheck {
    Write-Host 'Observe your usual workload for about 30 seconds. No stress test or settings changes.' -ForegroundColor Cyan
    Write-Host 'Counter queries may extend the duration. Ctrl+C cancels.'
    $samples = @(); $clock = [Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt 7; $i++) {
        $remaining = ($i * 5) - $clock.Elapsed.TotalSeconds
        if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int]($remaining * 1000)) }
        Write-Progress -Activity 'Checking laptop performance' -Status "Sample $($i + 1) of 7" -PercentComplete ($i * 100 / 7)
        $samples += Get-CLMPerformanceSample
    }
    Write-Progress -Activity 'Checking laptop performance' -Completed
    $summary = Get-CLMPerformanceSummary -Samples $samples
    $summary | Select-Object TotalSamples, CpuSamples, AverageCpuPercent, MemorySamples, LowestAvailableMiB | Format-List | Out-Host
    $summary.DiskSummary | Format-Table -AutoSize | Out-Host
    foreach ($finding in $summary.Findings) { Write-Host $finding }
    foreach ($issue in $summary.Issues) { Write-Host "Unavailable/partial: $issue" -ForegroundColor Yellow }
    Write-Host ('Elapsed: {0:N1} seconds. Blank metrics mean unavailable, not zero. Thresholds are clues, not a diagnosis.' -f $clock.Elapsed.TotalSeconds)
}

function New-CLMSnapshot {
    $system = Get-CLMSystem
    $memory = Get-CLMAvailableMemory
    [PSCustomObject]@{
        SchemaVersion=1; CapturedAt=(Get-Date -Format o); Computer=$system.Computer; Model=$system.Model
        AvailableMiB=$memory.Available_MiB; TotalMiB=$memory.Total_MiB
        Disks=@(Get-CLMDisks); TopMemoryUsers=@(Get-CLMMemoryUsers)
    }
}

function Assert-CLMSnapshot {
    param([Parameter(Mandatory)]$Snapshot)
    if ($Snapshot.SchemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace($Snapshot.Computer) -or
        [string]::IsNullOrWhiteSpace($Snapshot.Model)) { throw 'Unsupported or incomplete snapshot.' }
    $date = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse($Snapshot.CapturedAt, [ref]$date)) { throw 'Invalid snapshot timestamp.' }
    foreach ($field in @('AvailableMiB','TotalMiB')) {
        if ($null -eq $Snapshot.$field -or $Snapshot.$field -isnot [ValueType]) { throw "Invalid snapshot metric: $field" }
        $value = [double]$Snapshot.$field
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0) { throw "Invalid snapshot metric: $field" }
    }
    if ($Snapshot.TotalMiB -le 0 -or $Snapshot.AvailableMiB -gt $Snapshot.TotalMiB) { throw 'Invalid memory range.' }
    if ($null -eq $Snapshot.Disks) { throw 'Missing snapshot disks.' }
    foreach ($disk in $Snapshot.Disks) {
        if ([string]::IsNullOrWhiteSpace($disk.DeviceID)) { throw 'Missing disk identity.' }
        foreach ($field in @('Size_GiB','Free_GiB')) {
            if ($null -ne $disk.$field -and ($disk.$field -isnot [ValueType] -or [double]$disk.$field -lt 0 -or
                [double]::IsNaN([double]$disk.$field) -or [double]::IsInfinity([double]$disk.$field))) { throw 'Invalid disk value.' }
        }
    }
}

function Save-CLMSnapshot {
    param([string]$Directory = (Join-Path (Get-CLMStateDirectory) 'Snapshots'))
    $snapshot = New-CLMSnapshot
    Assert-CLMSnapshot $snapshot
    [void][IO.Directory]::CreateDirectory($Directory)
    $file = Join-Path $Directory ('Snapshot_{0}_{1}.json' -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'), [guid]::NewGuid().ToString('N').Substring(0,8))
    [IO.File]::WriteAllText($file, ($snapshot | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($true))
    $file
}

function Compare-CLMSnapshots {
    param([Parameter(Mandatory)]$Before, [Parameter(Mandatory)]$After)
    Assert-CLMSnapshot $Before; Assert-CLMSnapshot $After
    if ($Before.Computer -ne $After.Computer -or $Before.Model -ne $After.Model) { throw 'Choose snapshots from the same computer and model.' }
    if ([datetimeoffset]$After.CapturedAt -lt [datetimeoffset]$Before.CapturedAt) { throw 'The after snapshot must be newer than the before snapshot.' }
    [PSCustomObject]@{ Metric='Available RAM (MiB)'; Before=$Before.AvailableMiB; After=$After.AvailableMiB; Change=[math]::Round($After.AvailableMiB - $Before.AvailableMiB,1) }
    [PSCustomObject]@{ Metric='Total usable RAM (MiB)'; Before=$Before.TotalMiB; After=$After.TotalMiB; Change=[math]::Round($After.TotalMiB - $Before.TotalMiB,1) }
    foreach ($disk in $Before.Disks) {
        $match = @($After.Disks | Where-Object { $_.DeviceID -eq $disk.DeviceID -and $_.Size_GiB -eq $disk.Size_GiB })
        if ($match.Count -eq 1 -and $null -ne $disk.Free_GiB -and $null -ne $match[0].Free_GiB) {
            [PSCustomObject]@{ Metric="Free space $($disk.DeviceID) (GiB)"; Before=$disk.Free_GiB; After=$match[0].Free_GiB; Change=[math]::Round($match[0].Free_GiB - $disk.Free_GiB,1) }
        }
    }
}

function Show-CLMSnapshotComparison {
    $directory = Join-Path (Get-CLMStateDirectory) 'Snapshots'
    if (-not (Test-Path -LiteralPath $directory)) { Write-Host 'Save two snapshots with [B] first.'; return }
    $files = @(Get-ChildItem -LiteralPath $directory -Filter 'Snapshot_*.json' -File | Sort-Object Name)
    if ($files.Count -lt 2) { Write-Host 'Save two snapshots with [B] first.'; return }
    for ($i=0; $i -lt $files.Count; $i++) { Write-Host "[$($i+1)] $($files[$i].Name)" }
    $first=0; $second=0
    $selection = Read-Host 'Before row (ENTER cancels)'
    if ([string]::IsNullOrWhiteSpace($selection)) { return }
    if (-not [int]::TryParse($selection,[ref]$first) -or $first -lt 1 -or $first -gt $files.Count) { throw 'Invalid before row.' }
    $selection = Read-Host 'After row (ENTER cancels)'
    if ([string]::IsNullOrWhiteSpace($selection)) { return }
    if (-not [int]::TryParse($selection,[ref]$second) -or $second -lt 1 -or $second -gt $files.Count -or $first -eq $second) { throw 'Choose a different valid after row.' }
    $before = [IO.File]::ReadAllText($files[$first-1].FullName) | ConvertFrom-Json -ErrorAction Stop
    $after = [IO.File]::ReadAllText($files[$second-1].FullName) | ConvertFrom-Json -ErrorAction Stop
    Compare-CLMSnapshots -Before $before -After $after | Format-Table -AutoSize | Out-Host
    Write-Host 'Positive change means more available RAM/free disk space. Different workloads affect results; this is not a speed benchmark.'
    Write-Host 'Disk rows match drive letter and capacity, not hardware identity. Added/removed/resized drives are omitted.'
}
