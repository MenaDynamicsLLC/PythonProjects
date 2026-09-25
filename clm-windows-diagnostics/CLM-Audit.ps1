# CLM Health + Security Audit module - Learning Edition 2.0
# Read-only diagnostics. Findings are review prompts, not malware verdicts.

function Get-CLMPerformanceSnapshot {
    param([int]$Samples = 5)
    if ($Samples -lt 1) { $Samples = 1 }

    $rows = @()
    for ($i = 0; $i -lt $Samples; $i++) {
        $cpu = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop
        $disk = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction Stop
        $mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop
        $rows += [PSCustomObject]@{
            CpuPercent = [double]$cpu.PercentProcessorTime
            DiskBusyPercent = [double]$disk.PercentDiskTime
            DiskQueueLength = [double]$disk.AvgDiskQueueLength
            AvailableMiB = [double]$mem.AvailableMBytes
            PagesPerSec = [double]$mem.PagesPersec
        }
        if ($i -lt ($Samples - 1)) { Start-Sleep -Seconds 1 }
    }

    $cpuStats = $rows | Measure-Object CpuPercent -Average -Maximum
    $diskStats = $rows | Measure-Object DiskBusyPercent -Average -Maximum
    $queueStats = $rows | Measure-Object DiskQueueLength -Average -Maximum
    $memStats = $rows | Measure-Object AvailableMiB -Minimum
    $pageStats = $rows | Measure-Object PagesPerSec -Average -Maximum

    [PSCustomObject]@{
        Samples = $Samples
        Average_CPU_Percent = [math]::Round($cpuStats.Average, 1)
        Peak_CPU_Percent = [math]::Round($cpuStats.Maximum, 1)
        Average_Disk_Busy_Percent = [math]::Round($diskStats.Average, 1)
        Peak_Disk_Busy_Percent = [math]::Round($diskStats.Maximum, 1)
        Average_Disk_Queue = [math]::Round($queueStats.Average, 2)
        Peak_Disk_Queue = [math]::Round($queueStats.Maximum, 2)
        Lowest_Available_RAM_MiB = [math]::Round($memStats.Minimum, 0)
        Average_Pages_Per_Sec = [math]::Round($pageStats.Average, 1)
        Peak_Pages_Per_Sec = [math]::Round($pageStats.Maximum, 1)
    }
}

function Show-CLMPerformance {
    Write-Host 'Sampling normal activity for about five seconds. This is not a stress test.' -ForegroundColor Yellow
    Get-CLMPerformanceSnapshot -Samples 5 | Format-List | Out-Host
}

function Get-CLMPhysicalDisks {
    if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        try {
            return @(Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
                [PSCustomObject]@{
                    FriendlyName = $_.FriendlyName
                    MediaType = [string]$_.MediaType
                    BusType = [string]$_.BusType
                    Size_GiB = [math]::Round($_.Size / 1GB, 1)
                    HealthStatus = [string]$_.HealthStatus
                    OperationalStatus = ($_.OperationalStatus -join ', ')
                }
            })
        } catch { }
    }

    return @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop | ForEach-Object {
        [PSCustomObject]@{
            FriendlyName = $_.Model
            MediaType = if ($_.MediaType) { $_.MediaType } else { 'Unknown' }
            BusType = $_.InterfaceType
            Size_GiB = [math]::Round($_.Size / 1GB, 1)
            HealthStatus = $_.Status
            OperationalStatus = $_.Status
        }
    })
}

function Get-CLMLogicalDisks {
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | ForEach-Object {
        $freePercent = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
        [PSCustomObject]@{
            DeviceID = $_.DeviceID
            Size_GiB = [math]::Round($_.Size / 1GB, 1)
            Free_GiB = [math]::Round($_.FreeSpace / 1GB, 1)
            Free_Percent = $freePercent
            FileSystem = $_.FileSystem
        }
    }
}

function Show-CLMDisks {
    Write-Host 'PHYSICAL DISKS' -ForegroundColor Yellow
    Get-CLMPhysicalDisks | Format-Table -AutoSize | Out-Host
    Write-Host 'LOGICAL DISKS' -ForegroundColor Yellow
    Get-CLMLogicalDisks | Format-Table -AutoSize | Out-Host
}

function Get-CLMInstalledPrograms {
    $roots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $programs = foreach ($root in $roots) {
        Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.DisplayName) } |
            ForEach-Object {
                [PSCustomObject]@{
                    DisplayName = $_.DisplayName
                    DisplayVersion = $_.DisplayVersion
                    Publisher = $_.Publisher
                    InstallLocation = $_.InstallLocation
                }
            }
    }
    $programs | Sort-Object DisplayName, DisplayVersion -Unique
}

function Get-CLMRemoteAccessSignatures {
    @(
        [PSCustomObject]@{ Tool='Supremo'; Pattern='(?i)Supremo' },
        [PSCustomObject]@{ Tool='AnyDesk'; Pattern='(?i)AnyDesk' },
        [PSCustomObject]@{ Tool='TeamViewer'; Pattern='(?i)TeamViewer' },
        [PSCustomObject]@{ Tool='RustDesk'; Pattern='(?i)RustDesk' },
        [PSCustomObject]@{ Tool='ConnectWise Control / ScreenConnect'; Pattern='(?i)ScreenConnect|ConnectWise\s*Control' },
        [PSCustomObject]@{ Tool='Splashtop'; Pattern='(?i)Splashtop' },
        [PSCustomObject]@{ Tool='LogMeIn / GoTo remote support'; Pattern='(?i)LogMeIn|GoToAssist|GoTo\s*Resolve|GoToResolve' },
        [PSCustomObject]@{ Tool='RemotePC'; Pattern='(?i)RemotePC' },
        [PSCustomObject]@{ Tool='UltraViewer'; Pattern='(?i)UltraViewer' },
        [PSCustomObject]@{ Tool='DWAgent'; Pattern='(?i)DWAgent|DWService' },
        [PSCustomObject]@{ Tool='Zoho Assist'; Pattern='(?i)Zoho\s*Assist|ZohoAssist' },
        [PSCustomObject]@{ Tool='AeroAdmin'; Pattern='(?i)AeroAdmin' },
        [PSCustomObject]@{ Tool='Chrome Remote Desktop'; Pattern='(?i)Chrome\s*Remote\s*Desktop|remoting_host' },
        [PSCustomObject]@{ Tool='MeshCentral Agent'; Pattern='(?i)MeshCentral|MeshAgent' }
    )
}

function Get-CLMRemoteAccessFindings {
    $signatures = @(Get-CLMRemoteAccessSignatures)
    $programs = @(Get-CLMInstalledPrograms)
    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $services = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)
    $startup = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue)
    $findings = @()

    foreach ($sig in $signatures) {
        foreach ($program in ($programs | Where-Object { $_.DisplayName -match $sig.Pattern })) {
            $findings += [PSCustomObject]@{
                Tool = $sig.Tool; Evidence = 'Installed app'; Name = $program.DisplayName
                State = ''; PID = $null; Path = $program.InstallLocation
            }
        }

        foreach ($process in ($processes | Where-Object {
            $_.Name -match $sig.Pattern -or $_.ExecutablePath -match $sig.Pattern -or $_.CommandLine -match $sig.Pattern
        })) {
            $findings += [PSCustomObject]@{
                Tool = $sig.Tool; Evidence = 'Process'; Name = $process.Name
                State = 'Running'; PID = $process.ProcessId; Path = $process.ExecutablePath
            }
        }

        foreach ($service in ($services | Where-Object {
            $_.Name -match $sig.Pattern -or $_.DisplayName -match $sig.Pattern -or $_.PathName -match $sig.Pattern
        })) {
            $findings += [PSCustomObject]@{
                Tool = $sig.Tool; Evidence = 'Service'; Name = $service.Name
                State = "$($service.State) / $($service.StartMode)"; PID = $service.ProcessId; Path = $service.PathName
            }
        }

        foreach ($entry in ($startup | Where-Object { $_.Name -match $sig.Pattern -or $_.Command -match $sig.Pattern })) {
            $findings += [PSCustomObject]@{
                Tool = $sig.Tool; Evidence = 'Startup'; Name = $entry.Name
                State = ''; PID = $null; Path = $entry.Command
            }
        }
    }

    $findings | Sort-Object Tool, Evidence, Name, PID -Unique
}

function Get-CLMRemoteConnections {
    $processFindings = @(Get-CLMRemoteAccessFindings | Where-Object { $_.Evidence -eq 'Process' -and $_.PID })
    if ($processFindings.Count -eq 0 -or -not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
        return @()
    }

    $connections = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue)
    $rows = @()
    foreach ($finding in $processFindings) {
        foreach ($connection in ($connections | Where-Object { $_.OwningProcess -eq $finding.PID })) {
            $rows += [PSCustomObject]@{
                Tool = $finding.Tool
                Process = $finding.Name
                PID = $finding.PID
                LocalEndpoint = "$($connection.LocalAddress):$($connection.LocalPort)"
                RemoteEndpoint = "$($connection.RemoteAddress):$($connection.RemotePort)"
            }
        }
    }
    $rows | Sort-Object Tool, PID, RemoteEndpoint -Unique
}

function Show-CLMRemoteAccessAudit {
    Write-Host 'Recognized remote-support software is not automatically malicious.' -ForegroundColor Yellow
    Write-Host 'Unexpected persistent remote access should be reviewed with the device owner.' -ForegroundColor Yellow

    $findings = @(Get-CLMRemoteAccessFindings)
    if ($findings.Count -eq 0) {
        Write-Host '[OK] No recognized remote-access tools detected by the current signature list.' -ForegroundColor Green
        return
    }

    $findings | Format-Table Tool, Evidence, Name, State, PID, Path -Wrap -AutoSize | Out-Host

    Write-Host 'ACTIVE CONNECTIONS FROM DETECTED REMOTE-ACCESS PROCESSES' -ForegroundColor Yellow
    $connections = @(Get-CLMRemoteConnections)
    if ($connections.Count -eq 0) {
        Write-Host 'No established TCP connections were correlated at this moment.'
    } else {
        $connections | Format-Table -Wrap -AutoSize | Out-Host
    }
}

function Get-CLMStartupClassification {
    param([string]$Name, [string]$Command)

    $text = "$Name $Command"
    foreach ($sig in (Get-CLMRemoteAccessSignatures)) {
        if ($text -match $sig.Pattern) {
            return [PSCustomObject]@{
                Category = 'REVIEW - remote access'
                Reason = 'Verify that the device owner expects this remote-access software.'
            }
        }
    }

    if ($Name -match '^(SecurityHealth)$') {
        return [PSCustomObject]@{ Category='System/security'; Reason='Windows security notification component.' }
    }

    if ($Name -match '(?i)SynTP|RtkAud|Realtek|Intel.*Graphics|HotKeys') {
        return [PSCustomObject]@{ Category='Hardware/driver'; Reason='Likely hardware or driver helper; review before disabling.' }
    }

    if ($text -match '(?i)AutoLaunch|Steam|Signal|Canva|Grammarly|OneDrive|Epson.*Registration|Logi(tech)?.*Download|HPSEU|Microsoft\.Lists') {
        return [PSCustomObject]@{
            Category = 'Optional startup'
            Reason = 'Usually not required for Windows itself; disable only if the feature is not needed at sign-in.'
        }
    }

    return [PSCustomObject]@{ Category='Manual review'; Reason='No automatic classification rule matched.' }
}

function Get-CLMStartupAudit {
    Get-CimInstance Win32_StartupCommand -ErrorAction Stop | ForEach-Object {
        $classification = Get-CLMStartupClassification -Name $_.Name -Command $_.Command
        [PSCustomObject]@{
            Category = $classification.Category
            Name = $_.Name
            Location = $_.Location
            Command = $_.Command
            Reason = $classification.Reason
        }
    }
}

function Show-CLMStartupAudit {
    Get-CLMStartupAudit |
        Sort-Object Category, Name |
        Format-Table Category, Name, Location, Reason -Wrap -AutoSize | Out-Host
}

function Show-CLMSecurity {
    Write-Host 'MICROSOFT DEFENDER' -ForegroundColor Yellow
    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        try {
            Get-MpComputerStatus -ErrorAction Stop |
                Select-Object AntivirusEnabled, AntispywareEnabled, RealTimeProtectionEnabled,
                    NISEnabled, AntivirusSignatureLastUpdated, QuickScanAge, FullScanAge |
                Format-List | Out-Host
        } catch {
            Write-Warning "Defender status unavailable: $($_.Exception.Message)"
        }
    } else {
        Write-Host 'Defender status cmdlet is unavailable on this system.'
    }

    Write-Host 'WINDOWS FIREWALL PROFILES' -ForegroundColor Yellow
    if (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
        try {
            Get-NetFirewallProfile -ErrorAction Stop |
                Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction |
                Format-Table -AutoSize | Out-Host
        } catch {
            Write-Warning "Firewall profile status unavailable: $($_.Exception.Message)"
        }
    } else {
        Write-Host 'Firewall profile cmdlet is unavailable on this system.'
    }
}

function Get-CLMSoftwareReview {
    $rules = @(
        [PSCustomObject]@{ Pattern='(?i)CCleaner'; Reason='Third-party cleanup/monitoring utility; review whether it is still wanted.' },
        [PSCustomObject]@{ Pattern='(?i)AOL'; Reason='Legacy AOL software or helper; review if no longer used.' },
        [PSCustomObject]@{ Pattern='(?i)HP\s*SimplePass|SimplePass'; Reason='Legacy HP fingerprint/password utility; review if its features are no longer used.' },
        [PSCustomObject]@{ Pattern='(?i)Epson.*Registration'; Reason='Printer registration helper; commonly unnecessary after setup.' },
        [PSCustomObject]@{ Pattern='(?i)Logi(tech)?.*Download\s*Assistant'; Reason='Vendor download/update helper; usually optional at startup.' }
    )

    $programs = @(Get-CLMInstalledPrograms)
    $startup = @(Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue)
    $rows = @()

    foreach ($rule in $rules) {
        foreach ($program in ($programs | Where-Object { $_.DisplayName -match $rule.Pattern })) {
            $rows += [PSCustomObject]@{ Item=$program.DisplayName; Evidence='Installed app'; Reason=$rule.Reason }
        }
        foreach ($entry in ($startup | Where-Object { $_.Name -match $rule.Pattern -or $_.Command -match $rule.Pattern })) {
            $rows += [PSCustomObject]@{ Item=$entry.Name; Evidence='Startup'; Reason=$rule.Reason }
        }
    }

    $rows | Sort-Object Item, Evidence -Unique
}

function Show-CLMSoftwareReview {
    $rows = @(Get-CLMSoftwareReview)
    if ($rows.Count -eq 0) {
        Write-Host '[OK] No current optional/legacy review rules matched.' -ForegroundColor Green
    } else {
        Write-Host 'These are review candidates, not automatic uninstall recommendations.' -ForegroundColor Yellow
        $rows | Format-Table -Wrap -AutoSize | Out-Host
    }
}

function Show-CLMHealthSummary {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $totalMiB = [double]$os.TotalVisibleMemorySize / 1KB
    $freeMiB = [double]$os.FreePhysicalMemory / 1KB
    $freePct = if ($totalMiB -gt 0) { [math]::Round(($freeMiB / $totalMiB) * 100, 1) } else { 0 }

    if ($freePct -lt 10) {
        Write-Host "[REVIEW] RAM pressure: only $freePct% available at this snapshot." -ForegroundColor Yellow
    } elseif ($freePct -lt 20) {
        Write-Host "[INFO] RAM is moderately constrained: $freePct% available at this snapshot."
    } else {
        Write-Host "[OK] RAM availability: $freePct%." -ForegroundColor Green
    }

    $physical = @(Get-CLMPhysicalDisks)
    if ($physical | Where-Object { $_.MediaType -match '(?i)HDD|Hard' -and $_.BusType -notmatch '(?i)USB' }) {
        Write-Host '[INFO] Mechanical HDD detected. An SSD can materially improve Windows responsiveness.'
    }

    foreach ($disk in (Get-CLMLogicalDisks)) {
        if ($disk.Free_Percent -lt 10 -or $disk.Free_GiB -lt 10) {
            Write-Host "[REVIEW] Low free space on $($disk.DeviceID): $($disk.Free_GiB) GiB ($($disk.Free_Percent)%)." -ForegroundColor Yellow
        }
    }

    $remote = @(Get-CLMRemoteAccessFindings)
    if ($remote.Count -gt 0) {
        $tools = ($remote.Tool | Sort-Object -Unique) -join ', '
        Write-Host "[REVIEW] Recognized remote-access software detected: $tools. Verify owner authorization." -ForegroundColor Yellow
    } else {
        Write-Host '[OK] No recognized remote-access software detected by current signatures.' -ForegroundColor Green
    }

    if (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue) {
        try {
            $mp = Get-MpComputerStatus -ErrorAction Stop
            if ($mp.AntivirusEnabled -and $mp.RealTimeProtectionEnabled) {
                Write-Host '[OK] Microsoft Defender antivirus and real-time protection are enabled.' -ForegroundColor Green
            } else {
                Write-Host '[REVIEW] Microsoft Defender antivirus or real-time protection is not enabled.' -ForegroundColor Yellow
            }
        } catch { }
    }

    $optionalStartup = @(Get-CLMStartupAudit | Where-Object { $_.Category -eq 'Optional startup' })
    if ($optionalStartup.Count -gt 0) {
        Write-Host "[INFO] Optional startup entries detected: $($optionalStartup.Count). Review before disabling."
    }
}

function Resolve-CLMExecutablePath {
    param([string]$RawPath)

    if ([string]::IsNullOrWhiteSpace($RawPath)) { return $null }
    $raw = $RawPath.Trim()

    if ($raw.StartsWith('"')) {
        $closingQuote = $raw.IndexOf('"', 1)
        if ($closingQuote -gt 1) { return $raw.Substring(1, $closingQuote - 1) }
    }

    if ($raw -match '^(.*?\.exe)(?:\s|$)') { return $matches[1] }
    return $raw
}

function Export-CLMIncidentSnapshot {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($desktop) -or -not (Test-Path -LiteralPath $desktop -PathType Container)) {
        throw 'Desktop folder is unavailable; incident snapshot was not created.'
    }

    $folder = Join-Path $desktop ("CLM-Incident_{0}_{1}" -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'), [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null

    @("Collected: $(Get-Date -Format o)", "Computer: $env:COMPUTERNAME") |
        Out-File -LiteralPath (Join-Path $folder '00-summary.txt') -Encoding UTF8

    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Select-Object Name, ProcessId, ParentProcessId, ExecutablePath, CommandLine |
        Format-Table -Wrap -AutoSize | Out-String -Width 4096 |
        Out-File -LiteralPath (Join-Path $folder '01-processes.txt') -Encoding UTF8

    Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
        Select-Object Name, DisplayName, State, StartMode, ProcessId, PathName |
        Format-Table -Wrap -AutoSize | Out-String -Width 4096 |
        Out-File -LiteralPath (Join-Path $folder '02-services.txt') -Encoding UTF8

    Get-CLMStartupAudit |
        Format-Table -Wrap -AutoSize | Out-String -Width 4096 |
        Out-File -LiteralPath (Join-Path $folder '03-startup.txt') -Encoding UTF8

    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        Get-NetTCPConnection -ErrorAction SilentlyContinue |
            Select-Object State, LocalAddress, LocalPort, RemoteAddress, RemotePort, OwningProcess |
            Sort-Object State, OwningProcess |
            Format-Table -AutoSize | Out-String -Width 4096 |
            Out-File -LiteralPath (Join-Path $folder '04-network-connections.txt') -Encoding UTF8
    }

    $remote = @(Get-CLMRemoteAccessFindings)
    $remote | Format-Table -Wrap -AutoSize | Out-String -Width 4096 |
        Out-File -LiteralPath (Join-Path $folder '05-remote-access-findings.txt') -Encoding UTF8

    $hashRows = @()
    foreach ($finding in ($remote | Where-Object { $_.Path })) {
        $candidatePath = Resolve-CLMExecutablePath -RawPath $finding.Path
        if ($candidatePath -and (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
            try {
                $hash = Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256 -ErrorAction Stop
                $hashRows += [PSCustomObject]@{ Tool=$finding.Tool; Path=$candidatePath; SHA256=$hash.Hash }
            } catch { }
        }
    }

    $hashRows | Sort-Object Path -Unique |
        Format-Table -Wrap -AutoSize | Out-String -Width 4096 |
        Out-File -LiteralPath (Join-Path $folder '06-remote-file-hashes.txt') -Encoding UTF8

    Write-Host "Incident snapshot saved to: $folder" -ForegroundColor Green
    Write-Host 'This preserves observations only; it does not prove detected software was used maliciously.' -ForegroundColor Yellow
}
