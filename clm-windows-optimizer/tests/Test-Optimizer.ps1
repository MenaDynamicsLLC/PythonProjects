#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'CLM-Windows-Optimizer.ps1'
$tokens = $null; $parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
. $source

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAILED: $Message" }
    Write-Host "PASS: $Message"
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('CLM-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$originalTemp = $env:TEMP
$originalRootFunction = ${function:Get-CLMTempRoot}
$lock = $null
try {
    $env:TEMP = [IO.Path]::GetPathRoot($fixture)
    $rejected = $false
    try { Get-CLMTempRoot | Out-Null } catch { $rejected = $true }
    Assert-True $rejected 'Drive root refused as TEMP'
    $env:TEMP = $originalTemp

    # Substitute only the root resolver, so no test can delete real user files.
    function Get-CLMTempRoot { return $fixture }
    $old = (Get-Date).AddDays(-10)
    $cutoff = (Get-Date).AddDays(-7)
    foreach ($name in @('old[1].tmp', 'recent.tmp', 'changed.tmp', 'locked.tmp', 'new-copy.tmp')) {
        $path = Join-Path $fixture $name
        [IO.File]::WriteAllText($path, '12345')
        [IO.File]::SetCreationTime($path, $old)
        [IO.File]::SetLastWriteTime($path, $old)
    }
    [IO.File]::SetLastWriteTime((Join-Path $fixture 'recent.tmp'), (Get-Date))
    [IO.File]::SetCreationTime((Join-Path $fixture 'new-copy.tmp'), (Get-Date))
    $nested = [IO.Directory]::CreateDirectory((Join-Path $fixture 'app')).FullName
    [IO.File]::WriteAllText((Join-Path $nested 'keep.tmp'), 'keep')
    [IO.File]::SetCreationTime((Join-Path $nested 'keep.tmp'), $old)
    [IO.File]::SetLastWriteTime((Join-Path $nested 'keep.tmp'), $old)
    $candidates = @(Get-CLMTempCandidates -Root $fixture -Cutoff $cutoff)
    Assert-True ($candidates.Count -eq 3) 'Recent, recently created and nested files excluded'

    $dry = Remove-CLMTempCandidates -Root $fixture -Cutoff $cutoff -Candidates $candidates -WhatIf
    Assert-True ($dry.Deleted -eq 0 -and (Test-Path -LiteralPath (Join-Path $fixture 'old[1].tmp'))) 'WhatIf deletes nothing'

    # Alter a file after preview; hold another open with no delete sharing.
    [IO.File]::WriteAllText((Join-Path $fixture 'changed.tmp'), 'changed after preview')
    $lock = [IO.File]::Open((Join-Path $fixture 'locked.tmp'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    $result = Remove-CLMTempCandidates -Root $fixture -Cutoff $cutoff -Candidates $candidates
    Assert-True ($result.Deleted -eq 1 -and $result.Skipped -eq 2 -and $result.DeletedFileBytes -eq 5) 'Accurate deletion, changed-file and locked-file accounting'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture 'old[1].tmp'))) 'Bracketed filename removed literally'
    Assert-True (Test-Path -LiteralPath (Join-Path $nested 'keep.tmp')) 'Nested application file preserved'
    $lock.Dispose(); $lock = $null

    $empty = Remove-CLMTempCandidates -Root $fixture -Cutoff $cutoff -Candidates @()
    Assert-True ($empty.Deleted -eq 0 -and $empty.Skipped -eq 0) 'Empty candidate list is a no-op'
    $outside = Get-Item -LiteralPath $source
    $invalid = Remove-CLMTempCandidates -Root $fixture -Cutoff $cutoff -Candidates @($outside)
    Assert-True ($invalid.Deleted -eq 0 -and $invalid.Skipped -eq 1) 'Out-of-root candidate refused'

    $junction = Join-Path $fixture 'junction'
    New-Item -ItemType Junction -Path $junction -Target $nested | Out-Null
    $linkRejected = $false
    try { Assert-CLMPlainPath -Path (Join-Path $junction 'keep.tmp') } catch { $linkRejected = $true }
    Assert-True $linkRejected 'Junction ancestors refused'
    # Delete only the junction itself before removing the fixture.
    [IO.Directory]::Delete($junction)

    # Mock CIM so diagnostics tests are deterministic on both PS editions.
    function Get-CimInstance {
        param($ClassName, $Filter, $ErrorAction)
        switch ($ClassName) {
            'Win32_OperatingSystem' { [PSCustomObject]@{Caption='Test Windows'; BuildNumber='1'; TotalVisibleMemorySize=8MB; FreePhysicalMemory=3MB; LastBootUpTime=(Get-Date).AddHours(-2)} }
            'Win32_ComputerSystem' { [PSCustomObject]@{Manufacturer='Test'; Model='Fixture'} }
            'Win32_LogicalDisk' {
                [PSCustomObject]@{DeviceID='C:'; Size=100GB; FreeSpace=25GB}
                [PSCustomObject]@{DeviceID='D:'; Size=0; FreeSpace=$null}
            }
            'Win32_PhysicalMemory' { throw 'simulated CIM failure' }
            'Win32_StartupCommand' { [PSCustomObject]@{Name='Sample'; Location='Test'; Command=('x' * 500)} }
        }
    }
    $system = Get-CLMSystem
    Assert-True ($system.Total_RAM_GiB -eq 8 -and $system.Used_RAM_GiB -eq 5 -and $system.Free_RAM_GiB -eq 3) 'WMI memory units converted correctly'
    $disks = @(Get-CLMDisks)
    Assert-True ($disks[0].Free_Percent -eq 25 -and $null -eq $disks[1].Free_Percent) 'Disk percentages handle zero-capacity disks'
    $reports = Join-Path $fixture 'reports[1]'
    $report = Export-CLMReport -Directory $reports
    $report2 = Export-CLMReport -Directory $reports
    $body = [IO.File]::ReadAllText($report)
    Assert-True ($report -ne $report2) 'Rapid report exports have distinct paths'
    Assert-True ($body.Contains('simulated CIM failure') -and $body.Contains('DISKS') -and $body.Contains(('x' * 500))) 'Report preserves failures, subsequent sections and long startup commands'
    $rejected = $false
    try { Export-CLMReport -Directory $report | Out-Null } catch { $rejected = $true }
    Assert-True $rejected 'Invalid report destination fails visibly'
    Write-Host 'All regression checks passed.' -ForegroundColor Green
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
    $env:TEMP = $originalTemp
    ${function:Get-CLMTempRoot} = $originalRootFunction
    # Fixture is uniquely created by this test; production cleanup is never used.
    if (Test-Path -LiteralPath (Join-Path $fixture 'junction')) {
        [IO.Directory]::Delete((Join-Path $fixture 'junction'))
    }
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction Stop
}
