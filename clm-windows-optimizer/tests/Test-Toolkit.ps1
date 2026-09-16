#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($name in @('CLM-Windows-Optimizer.ps1','CLM-Toolkit.ps1')) {
    $tokens=$null; $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name),[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
}
. (Join-Path $root 'CLM-Windows-Optimizer.ps1')
function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAILED: $Message" }
    Write-Host "PASS: $Message"
}
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('CLM-toolkit-' + [guid]::NewGuid().ToString('N'))
try {
    $workProfile = Get-CLMWorkProfile -Directory $fixture
    Assert-True ('Code' -in $workProfile.KeepOpen -and -not (Test-Path -LiteralPath $fixture)) 'Default profile protects work apps without writing files'
    $file = Save-CLMWorkProfile -Names @('Spotify.exe','Signal','Spotify') -Directory $fixture
    $workProfile = Get-CLMWorkProfile -Directory $fixture
    Assert-True ($workProfile.KeepOpen.Count -eq 2 -and 'Spotify' -in $workProfile.KeepOpen) 'Profile round trip normalizes executable suffix and duplicates'
    [void](Save-CLMWorkProfile -Names @('Canva') -Directory $fixture)
    Assert-True ((Get-CLMWorkProfile -Directory $fixture).KeepOpen[0] -eq 'Canva') 'Existing profile replaced successfully'
    $rejected=$false
    try { Save-CLMWorkProfile -Names @('C:\Program Files\bad.exe') -Directory $fixture } catch { $rejected=$true }
    Assert-True ($rejected -and (Get-CLMWorkProfile -Directory $fixture).KeepOpen[0] -eq 'Canva') 'Invalid name does not overwrite profile'
    [IO.File]::WriteAllText($file,'{broken')
    $rejected=$false
    try { Get-CLMWorkProfile -Directory $fixture } catch { $rejected=$true }
    Assert-True $rejected 'Corrupt profile fails visibly instead of ignoring protections'
    [void](Save-CLMWorkProfile -Names @() -Directory $fixture)
    Assert-True ((Get-CLMWorkProfile -Directory $fixture).KeepOpen.Count -eq 0) 'Empty additional profile is valid; core protections remain separate'

    # Native Windows CIM smoke check, without changing or closing anything.
    $sample = Get-CLMPerformanceSample
    Assert-True ($sample.TotalMiB -gt 0 -and $null -ne $sample.AvailableMiB) 'Real Windows memory sample available'
    Assert-True ($null -ne $sample.CpuPercent -and $sample.CpuPercent -ge 0 -and $sample.CpuPercent -le 100) 'Real Windows CPU counter available'
    Assert-True ($sample.Disks.Count -gt 0) 'Real Windows physical disk counters available'
    $samplePath = Save-CLMSnapshot -Directory (Join-Path $fixture 'snapshots[1]')
    $before = [IO.File]::ReadAllText($samplePath) | ConvertFrom-Json
    $after = [IO.File]::ReadAllText($samplePath) | ConvertFrom-Json
    $before.AvailableMiB=100; $after.AvailableMiB=200
    $after.CapturedAt=([datetimeoffset]$before.CapturedAt).AddMinutes(1).ToString('o')
    $diff = @(Compare-CLMSnapshots $before $after)
    Assert-True ($diff[0].Change -eq 100) 'Saved snapshot reloads and compares real system schema'
    $after.Computer='another-machine'
    $rejected=$false
    try { Compare-CLMSnapshots $before $after | Out-Null } catch { $rejected=$true }
    Assert-True $rejected 'Snapshots from other machines rejected'
    $after.Computer=$before.Computer
    $after.CapturedAt=([datetimeoffset]$before.CapturedAt).AddMinutes(-1).ToString('o')
    $rejected=$false
    try { Compare-CLMSnapshots $before $after | Out-Null } catch { $rejected=$true }
    Assert-True $rejected 'Reversed chronology rejected'
    $after.CapturedAt=([datetimeoffset]$before.CapturedAt).AddMinutes(1).ToString('o')
    $after.AvailableMiB=$null
    $rejected=$false
    try { Compare-CLMSnapshots $before $after | Out-Null } catch { $rejected=$true }
    Assert-True $rejected 'Missing numeric value is not silently treated as zero'
    $after.AvailableMiB=200
    $before.Disks=@([PSCustomObject]@{DeviceID='C:';Size_GiB=100;Free_GiB=20})
    $after.Disks=@([PSCustomObject]@{DeviceID='C:';Size_GiB=100;Free_GiB=25})
    $diff=@(Compare-CLMSnapshots $before $after)
    Assert-True ($diff[2].Change -eq 5) 'Disk free-space change is calculated correctly'
    $after.Disks[0].Size_GiB=200
    Assert-True (@(Compare-CLMSnapshots $before $after).Count -eq 2) 'Resized or replaced-capacity disk excluded'

    $high=[PSCustomObject]@{CpuPercent=90;AvailableMiB=100;TotalMiB=4000;Disks=@([PSCustomObject]@{Name='0 C:';BusyPercent=90});Issues=@()}
    $low=[PSCustomObject]@{CpuPercent=5;AvailableMiB=2000;TotalMiB=4000;Disks=@([PSCustomObject]@{Name='0 C:';BusyPercent=5});Issues=@()}
    $missing=[PSCustomObject]@{CpuPercent=$null;AvailableMiB=$null;TotalMiB=$null;Disks=@();Issues=@('Unavailable')}
    $summary=Get-CLMPerformanceSummary @($high,$high,$high,$missing)
    Assert-True ($summary.CpuSamples -eq 3 -and $summary.AverageCpuPercent -eq 90 -and $summary.Findings.Count -eq 3) 'Sustained high measurements flagged; missing sample excluded from averages'
    $summary=Get-CLMPerformanceSummary @($high,$low,$low,$low)
    Assert-True ($summary.Findings.Count -eq 1 -and $summary.Findings[0] -like 'No sustained*') 'One spike does not trigger sustained-load conclusions'
    $summary=Get-CLMPerformanceSummary @($missing,$missing,$missing)
    Assert-True ($null -eq $summary.AverageCpuPercent -and $summary.CpuSamples -eq 0 -and $summary.Issues.Count -eq 1) 'All-missing counters remain unavailable, never zero load'

    function Get-CimInstance {
        param($ClassName,$Filter,$OperationTimeoutSec,$ErrorAction)
        switch ($ClassName) {
            'Win32_OperatingSystem' { [PSCustomObject]@{FreePhysicalMemory=1MB;TotalVisibleMemorySize=4MB} }
            'Win32_PerfFormattedData_PerfOS_Processor' { throw 'simulated CPU failure' }
            'Win32_PerfFormattedData_PerfDisk_PhysicalDisk' { [PSCustomObject]@{Name='0 C:';PercentIdleTime=25} }
        }
    }
    $partial=Get-CLMPerformanceSample
    Assert-True ($null -eq $partial.CpuPercent -and $partial.AvailableMiB -eq 1024 -and $partial.Disks[0].BusyPercent -eq 75 -and $partial.Issues.Count -eq 1) 'Failed CPU query preserves independent RAM and disk results'
    Write-Host 'All toolkit checks passed.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
