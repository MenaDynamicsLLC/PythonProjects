#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot 'CLM-Windows-Diagnostics.ps1'
$tokens = $null; $parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
. $scriptPath -NoMenu

function Assert-CLMTest([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$signatureTools = @(Get-CLMRemoteAccessSignatures | Select-Object -ExpandProperty Tool)
Assert-CLMTest ($signatureTools -contains 'Supremo') 'Supremo signature missing.'
Assert-CLMTest ($signatureTools -contains 'AnyDesk') 'AnyDesk signature missing.'
Assert-CLMTest ($signatureTools -contains 'TeamViewer') 'TeamViewer signature missing.'

$securityClass = Get-CLMStartupClassification -Name 'SecurityHealth' -Command ''
Assert-CLMTest ($securityClass.Category -eq 'System/security') 'SecurityHealth classification failed.'
$remoteClass = Get-CLMStartupClassification -Name 'Supremo' -Command 'C:\Program Files (x86)\Supremo\Supremo.exe /SVCRUN'
Assert-CLMTest ($remoteClass.Category -eq 'REVIEW - remote access') 'Remote-access classification failed.'
$unknownClass = Get-CLMStartupClassification -Name 'ExampleUnknownApp' -Command 'C:\Example\app.exe'
Assert-CLMTest ($unknownClass.Category -eq 'Manual review') 'Unknown startup item should require manual review.'
$originalTemp = $env:TEMP
$originalLocal = $env:LOCALAPPDATA
$fixture = Join-Path $originalTemp ('CLM-test-' + [guid]::NewGuid().ToString('N'))
try {
    $root = Join-Path $fixture 'Temp'
    New-Item -ItemType Directory -Path $root | Out-Null
    $env:LOCALAPPDATA = $fixture
    $env:TEMP = $root
    $old = Join-Path $root 'old[1].txt'
    $recent = Join-Path $root 'recent.txt'
    Set-Content -LiteralPath $old -Value 'old test data'
    Set-Content -LiteralPath $recent -Value 'recent test data'
    $folder = Join-Path $root 'keep-folder'
    New-Item -ItemType Directory -Path $folder | Out-Null
    Set-Content -LiteralPath (Join-Path $folder 'keep.txt') -Value 'keep'
    $oldItem = Get-Item -LiteralPath $old
    $oldItem.CreationTime = (Get-Date).AddDays(-10)
    $oldItem.LastWriteTime = (Get-Date).AddDays(-10)
    $files = @(Get-CLMCleanupCandidates $root (Get-Date).AddDays(-7))
    Assert-CLMTest ($files.Count -eq 1 -and $files[0].Name -eq 'old[1].txt') 'Wrong preview candidates.'
    function Read-Host { param($Prompt) return 'N' }
    Invoke-CLMCleanup
    Assert-CLMTest (Test-Path -LiteralPath $old) 'Cancellation deleted a file.'
    function Read-Host { param($Prompt) return 'DELETE' }
    Invoke-CLMCleanup
    Assert-CLMTest (-not (Test-Path -LiteralPath $old)) 'Old file not removed.'
    Assert-CLMTest (Test-Path -LiteralPath $recent) 'Recent file deleted.'
    Assert-CLMTest (Test-Path -LiteralPath (Join-Path $folder 'keep.txt')) 'Nested file deleted.'
    $env:TEMP = $fixture
    $rejected = $false
    try { Get-CLMCleanupRoot | Out-Null } catch { $rejected = $true }
    Assert-CLMTest $rejected 'Unexpected TEMP path accepted.'
    Write-Host 'CLM validation passed.'
} finally {
    $env:TEMP = $originalTemp
    $env:LOCALAPPDATA = $originalLocal
    Remove-Item Function:\Read-Host -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
