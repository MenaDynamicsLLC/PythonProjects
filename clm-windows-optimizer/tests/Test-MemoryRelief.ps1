#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'CLM-Windows-Optimizer.ps1')

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAILED: $Message" }
    Write-Host "PASS: $Message"
}

function New-TestProcess([string]$Name, [int]$ProcessNumber = 40000001) {
    $process = [PSCustomObject]@{
        Id = $ProcessNumber
        ProcessName = $Name
        SessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
        MainWindowHandle = [IntPtr]1
        MainWindowTitle = "$Name window"
        StartTime = [datetime]'2026-01-01'
        WorkingSet64 = 100MB
        CloseCalls = 0
        AcceptClose = $true
    }
    $process | Add-Member -MemberType ScriptMethod -Name CloseMainWindow -Value {
        $this.CloseCalls++
        return $this.AcceptClose
    }
    return $process
}

# No real processes are closed by this suite.
foreach ($name in @('chrome', 'msedge', 'firefox', 'brave', 'opera', 'vivaldi',
    'Grok', 'powershell', 'pwsh', 'Code', 'Code - Insiders', 'WindowsTerminal',
    'explorer', 'MsMpEng', 'svchost', 'UnknownUsefulTool')) {
    Assert-True (-not (Test-CLMClosableApp (New-TestProcess $name))) "Protected: $name"
}
$script:testProcess = New-TestProcess 'Spotify'
Assert-True (Test-CLMClosableApp $script:testProcess) 'Optional visible app eligible'
Assert-True (-not (Test-CLMClosableApp $script:testProcess -AdditionalKeepOpen @('spotify'))) 'Additional keep-open names are honored case-insensitively'
$script:testProcess.MainWindowTitle = 'Grok'
Assert-True (-not (Test-CLMClosableApp $script:testProcess)) 'Grok title protected even inside a listed app'
$script:testProcess.MainWindowTitle = 'Spotify window'
$script:testProcess.MainWindowHandle = [IntPtr]::Zero
Assert-True (-not (Test-CLMClosableApp $script:testProcess)) 'Windowless and tray processes excluded'
$script:testProcess.MainWindowHandle = [IntPtr]1
$script:testProcess.SessionId++
Assert-True (-not (Test-CLMClosableApp $script:testProcess)) 'Other sessions excluded'
$script:testProcess.SessionId--

function Get-Process {
    param($Id, $ErrorAction)
    if ($script:processGone) { return }
    return $script:testProcess
}
$script:processGone = $false
$apps = @(Get-CLMClosableApps)
Assert-True ($apps.Count -eq 1 -and $apps[0].WorkingSet_MiB -eq 100) 'Candidate snapshot includes identity and memory'
$picked = @(Resolve-CLMAppSelection '1, 1' $apps)
Assert-True ($picked.Count -eq 1) 'Duplicate selection deduplicated'
Assert-True (@(Resolve-CLMAppSelection '' $apps).Count -eq 0) 'Blank selection cancels'
foreach ($selection in @('1,2', '0', '-1', 'all', '1,', '999999999999999999999')) {
    $rejected = $false
    try { Resolve-CLMAppSelection $selection $apps | Out-Null } catch { $rejected = $true }
    Assert-True $rejected "Invalid selection rejected: $selection"
}

$result = Close-CLMSelectedApps $apps -WhatIf
Assert-True ($script:testProcess.CloseCalls -eq 0) 'WhatIf sends no close message'
$result = Close-CLMSelectedApps $apps -AdditionalKeepOpen @('Spotify')
Assert-True ($script:testProcess.CloseCalls -eq 0 -and $result.Status -like 'Protected*') 'Keep-open policy rechecked before closure'
$script:testProcess.StartTime = $script:testProcess.StartTime.AddSeconds(1)
$result = Close-CLMSelectedApps $apps
Assert-True ($script:testProcess.CloseCalls -eq 0 -and $result.Status -like 'App changed*') 'Reused PID cannot close a replacement process'
$script:testProcess.StartTime = $apps[0].StartTime
$script:testProcess.MainWindowTitle = 'Another document'
$result = Close-CLMSelectedApps $apps
Assert-True ($script:testProcess.CloseCalls -eq 0) 'Changed window invalidates preview'
$script:testProcess.MainWindowTitle = $apps[0].Window
$result = Close-CLMSelectedApps $apps
Assert-True ($script:testProcess.CloseCalls -eq 1 -and $result.Status -like 'Close requested*') 'Selected app receives normal close request'
$state = Get-CLMAppExitStatus $apps
Assert-True ($state.Status -like 'Still running*') 'Close request is not misreported as process exit'
$script:testProcess.AcceptClose = $false
$result = Close-CLMSelectedApps $apps
Assert-True ($script:testProcess.CloseCalls -eq 2 -and $result.Status -like 'App refused*') 'Refused close is reported without forced termination'
$script:processGone = $true
$state = Get-CLMAppExitStatus $apps
Assert-True ($state.Status -eq 'Exited') 'Process disappearance is reported as exited'

function Get-CimInstance {
    param($ClassName, $ErrorAction)
    [PSCustomObject]@{TotalVisibleMemorySize=8MB; FreePhysicalMemory=3MB}
}
$memory = Get-CLMAvailableMemory
Assert-True ($memory.Available_MiB -eq 3072 -and $memory.Total_MiB -eq 8192) 'Before/after RAM samples use correct units'
Write-Host 'All memory-relief regression checks passed.' -ForegroundColor Green
