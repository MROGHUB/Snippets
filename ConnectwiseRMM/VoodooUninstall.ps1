
# VoodooV3.ps1

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('0','10','11','12','19','20')]
    [string]$Selection = '0',

    [Parameter(Mandatory=$false)]
    [string]$Action = 'default'
)

function Show-Menu {
    Clear-Host
    Write-Host "=== VoodooV3 Menu ===" -ForegroundColor Cyan
    Write-Host "10) Platform Watchdog Restore"
    Write-Host "11) Platform Watchdog Update"
    Write-Host "12) Platform Watchdog Uninstall"
    Write-Host "19) Voodoo Uninstall"
    Write-Host "20) Voodoo Install"
    Write-Host ""
}

function Invoke-PlatformWatchdogRestore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet('Restore')]
        [string]$Action = 'Restore',

        [Parameter(Mandatory=$false)]
        [ValidateSet('Yes','No')]
        [string]$Display = 'Yes'
    )

    Write-Host "Running Platform Watchdog Restore..." -ForegroundColor Green

    # Enable verbose output if display is enabled
    if ($Display -eq 'Yes') { $VerbosePreference = 'Continue' }

    function Write-Log {
        param([string]$Message)
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Output "[$timestamp] $Message"
    }

    try {
        Write-Log "Starting restore workflow (Display=$Display)"

        # Stop primary service
        Write-Log "Stopping the primary service..."
        Stop-Service -Name 'PrimaryService' -Force -ErrorAction SilentlyContinue

        # Validate backup integrity
        Write-Log "Validating backup image..."
        $backupPath   = 'C:\Backups\PrimaryImage\'
        $checksumFile = Join-Path $backupPath 'checksum.sha256'

        if (Test-Path $checksumFile) {
            $expectedHash = Get-Content $checksumFile
            $actualHash   = (Get-FileHash -Path (Join-Path $backupPath 'image.bin') -Algorithm SHA256).Hash

            if ($expectedHash -ne $actualHash) {
                throw "Backup integrity check failed. Aborting restore."
            }
            Write-Log "Backup integrity verified successfully."
        }

        # Restore files
        Write-Log "Restoring files from backup..."
        $targetPath = 'C:\ProgramData\PrimaryService\'
        if (Test-Path $targetPath) { Remove-Item -Path $targetPath\* -Recurse -Force }
        Copy-Item -Path "$backupPath\*" -Destination $targetPath -Recurse -Force

        # Restart service
        Write-Log "Restarting the primary service..."
        Start-Service -Name 'PrimaryService'

        Write-Log "Restore completed successfully."
        exit 0
    }
    catch {
        Write-Log "ERROR: $($_.Exception.Message)"
        exit 1
    }

    Start-Sleep -Seconds 2
    Write-Host "Restore completed." -ForegroundColor Green
}

function Invoke-PlatformWatchdogUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet('Yes','No')]
        [string]$Display = 'Yes'
    )

    Write-Host "Running Platform Watchdog Update..." -ForegroundColor Green

    if ($Display -eq 'Yes') { $VerbosePreference = 'Continue' }

    function Write-Log {
        param([string]$Message)
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Output "[$timestamp] $Message"
    }

    function Get-DiskSpace {
        param([string]$Drive = 'C:')
        $drive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$Drive'"
        return @{
            Free  = [math]::Round($drive.FreeSpace / 1GB, 2)
            Total = [math]::Round($drive.Size      / 1GB, 2)
        }
    }

    try {
        Write-Log "Starting Windows Update cleanup (Display=$Display)"

        # Check admin privileges
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
            throw "This script requires Administrator privileges."
        }

        # Get initial disk space
        $initialSpace = Get-DiskSpace
        Write-Log "Initial free disk space: $($initialSpace.Free) GB"

        # Clean PnP driver cache
        Write-Log "Cleaning PnP driver cache..."
        Start-Process -FilePath 'rundll32.exe' -ArgumentList 'pnpclean.dll,RunDLL_PnpClean /drivers/maxclean' -Wait -NoNewWindow

        # Check DISM health
        Write-Log "Checking DISM component health..."
        Start-Process -FilePath 'dism.exe' -ArgumentList '/Online /Cleanup-Image /CheckHealth' -Wait -NoNewWindow

        # Run SFC scan
        Write-Log "Running System File Checker..."
        Start-Process -FilePath 'sfc.exe' -ArgumentList '/scannow' -Wait -NoNewWindow

        # Restore system health if needed
        Write-Log "Running DISM RestoreHealth..."
        Start-Process -FilePath 'dism.exe' -ArgumentList '/Online /Cleanup-Image /RestoreHealth' -Wait -NoNewWindow

        # Cleanup component store
        Write-Log "Cleaning up Windows component store..."
        Start-Process -FilePath 'dism.exe' -ArgumentList '/Online /Cleanup-Image /StartComponentCleanup' -Wait -NoNewWindow

        # ResetBase to remove superseded components
        Write-Log "Resetting component store base..."
        Start-Process -FilePath 'dism.exe' -ArgumentList '/Online /Cleanup-Image /StartComponentCleanup /ResetBase' -Wait -NoNewWindow

        # Clean Windows Update cache
        Write-Log "Cleaning Windows Update cache..."
        $paths = @(
            'C:\Windows\SoftwareDistribution\Download\*',
            'C:\Windows\SoftwareDistribution\DataStore\*',
            'C:\Windows\Temp\*',
            'C:\Windows\Prefetch\*'
        )

        foreach ($path in $paths) {
            if (Test-Path $path) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        # Run Windows Disk Cleanup
        Write-Log "Running Windows Disk Cleanup..."
        $cleanMgr = Start-Process -FilePath 'cleanmgr.exe' -ArgumentList '/sagerun:1' -Wait -PassThru -NoNewWindow

        # Get final disk space
        $finalSpace = Get-DiskSpace
        $reclaimed  = $finalSpace.Free - $initialSpace.Free

        Write-Log "Final free disk space: $($finalSpace.Free) GB"
        Write-Log "Reclaimed disk space: $reclaimed GB"
        Write-Log "AutoUpdate cleanup completed successfully."

        exit 0
    }
    catch {
        Write-Log "ERROR: $($_.Exception.Message)"
        exit 1
    }

    Start-Sleep -Seconds 2
    Write-Host "Update completed." -ForegroundColor Green
}

function Invoke-PlatformWatchdogUninstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$AppName = 'Platform Watchdog',

        [Parameter(Mandatory=$false)]
        [ValidateSet('Yes','No')]
        [string]$Display = 'Yes',

        [Parameter(Mandatory=$false)]
        [int]$Timeout = 300
    )

    Write-Host "Running Platform Watchdog Uninstall..." -ForegroundColor Green

    if ($Display -eq 'Yes') { $VerbosePreference = 'Continue' }

    function Write-Log {
        param([string]$Message)
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Write-Output "[$timestamp] $Message"
    }

    function Get-UninstallString {
        param([string]$ApplicationName)

        $paths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )

        foreach ($path in $paths) {
            $app = Get-ItemProperty $path | Where-Object { $_.DisplayName -like "*$ApplicationName*" }
            if ($app) { return $app.UninstallString }
        }
        return $null
    }

    try {
        Write-Log "Starting silent uninstall for $AppName (Display=$Display)"

        # Check admin privileges
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
            throw "This script requires Administrator privileges."
        }

        # Find uninstall string
        $uninstallString = Get-UninstallString -ApplicationName $AppName
        if (-not $uninstallString) {
            throw "Application '$AppName' not found in registry."
        }

        Write-Log "Found uninstall string: $uninstallString"

        # Determine silent switches
        $silentSwitch = if ($uninstallString -like 'msiexec*') { '/qn /norestart' } else { '/S' }

        # Execute uninstall
        Write-Log "Executing silent uninstall..."
        $process = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c $uninstallString $silentSwitch" -Wait -PassThru -NoNewWindow

        if ($process.ExitCode -ne 0) {
            Write-Log "Warning: Uninstall exit code was $($process.ExitCode)"
        }

        # Cleanup leftover directories
        $pathsToClean = @(
            "C:\Program Files\$AppName",
            "C:\Program Files (x86)\$AppName",
            "C:\ProgramData\$AppName",
            "$env:APPDATA\$AppName",
            "$env:LOCALAPPDATA\$AppName"
        )

        foreach ($path in $pathsToClean) {
            if (Test-Path $path) {
                Write-Log "Cleaning up: $path"
                Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Log "Uninstall completed successfully."
        exit 0
    }
    catch {
        Write-Log "ERROR: $($_.Exception.Message)"
        exit 1
    }

    Start-Sleep -Seconds 2
    Write-Host "Uninstall completed." -ForegroundColor Green
}

function Invoke-VoodooUninstall {
    [CmdletBinding()]
    param()

    Write-Host "Running Voodoo Uninstall..." -ForegroundColor Green

    $ErrorActionPreference = 'Continue'
    $ProgressPreference    = 'SilentlyContinue'
    $ConfirmPreference     = 'None'
    $VerbosePreference     = 'Continue'   # Force verbose output globally

    Clear-Host

    # --- Logging setup ---
    $logDir  = Join-Path $env:ProgramData 'CW_RMM_Uninstall'
    New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue | Out-Null
    $timeTag = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $logPath = Join-Path $logDir "CW_RMM_Uninstall_$timeTag.log"

    try {
        Start-Transcript -Path $logPath -Force | Out-Null
        Write-Verbose "Transcript started: $logPath"
    } catch {
        Write-Output "WARNING: Failed to start transcript: $($_.Exception.Message)"
    }

    # --- Utility functions ---

    function Invoke-OfficialITSPlatformUninstall {
        [CmdletBinding()]
        param()

        $agentCoreExe = "C:\Program Files (x86)\ITSPlatform\agentcore\platform-agent-core.exe"
        $cfgPath      = "C:\Program Files (x86)\ITSPlatform\config\platform_agent_core_cfg.json"
        $logPath      = "C:\Program Files (x86)\ITSPlatformSetupLogs\platform_agent_core.log"

        if (Test-Path $agentCoreExe) {
            Write-Output "Attempting official ITSPlatform uninstall..."
            Write-Verbose "Executing: $agentCoreExe `"$cfgPath`" `"$logPath`" uninstallagent"
            try {
                Start-Process -FilePath $agentCoreExe -ArgumentList "`"$cfgPath`" `"$logPath`" uninstallagent" -NoNewWindow -ErrorAction SilentlyContinue
                Write-Output "Invoked ITSPlatform agent uninstall; waiting 120 seconds..."
                Write-Verbose "Sleeping 120 seconds to allow agent to self-remove..."
                Start-Sleep -Seconds 120
            } catch {
                Write-Output "WARNING: Official ITSPlatform uninstall failed: $($_.Exception.Message)"
            }
        } else {
            Write-Output "INFO: platform-agent-core.exe not found; skipping official uninstall."
        }
    }

    function Invoke-SAAZODUninstall {
        [CmdletBinding()]
        param()

        $saazExe = "C:\Program Files (x86)\SAAZOD\Uninstall\Uninstall.exe"
        $saazXml = "C:\Program Files (x86)\SAAZOD\Uninstall\Uninstall.xml"

        if (Test-Path -Path $saazExe) {
            Write-Output "Triggering SAAZOD uninstall (silent)..."
            Write-Verbose "Executing: $saazExe /silent /u:`"$saazXml`""
            try {
                Start-Process -FilePath $saazExe -ArgumentList "/silent /u:`"$saazXml`"" -Wait -ErrorAction SilentlyContinue
                Write-Verbose "SAAZOD uninstall process completed; sleeping 10 seconds for cleanup..."
                Start-Sleep -Seconds 10
            } catch {
                Write-Output "WARNING: SAAZOD uninstall failed: $($_.Exception.Message)"
            }
        } else {
            Write-Output "INFO: SAAZOD uninstaller not found: $saazExe"
        }
    }

    function Stop-ProcessesByPatterns {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string[]] $Patterns
        )

        Write-Output "Stopping processes..."
        Write-Verbose "Process patterns: $($Patterns -join ', ')"

        foreach ($pattern in $Patterns) {
            Write-Verbose "Querying processes for pattern: $pattern"
            try {
                $procs = Get-Process -Name $pattern -ErrorAction SilentlyContinue
                foreach ($p in $procs) {
                    Write-Output "Stopping Process: $($p.Name) (PID $($p.Id))"
                    Write-Verbose "Stop-Process -Id $($p.Id) -Force"
                    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Output "WARNING: Failed stopping processes for pattern '$pattern': $($_.Exception.Message)"
            }
        }
    }

    function Stop-ServicesByPatterns {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string[]] $Patterns
        )

        Write-Output "Stopping services..."
        Write-Verbose "Service patterns: $($Patterns -join ', ')"

        foreach ($pattern in $Patterns) {
            try {
                $svcs = Get-Service -Name $pattern -ErrorAction SilentlyContinue
                foreach ($svc in $svcs) {
                    Write-Verbose "Inspecting service: $($svc.Name) | Status=$($svc.Status)"
                    if ($svc.Status -ne 'Stopped') {
                        Write-Output "Stopping Service: $($svc.Name)"
                        Write-Verbose "Stop-Service -Name $($svc.Name) -Force"
                        Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                    }
                }
            } catch {
                Write-Output "WARNING: Failed stopping services for pattern '$pattern': $($_.Exception.Message)"
            }
        }
    }

    function Delete-ServicesByNames {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string[]] $ServiceNames
        )

        foreach ($service in $ServiceNames) {
            Write-Output "Deleting service: $service"
            Write-Verbose "sc.exe delete $service"
            try {
                Start-Process -FilePath "sc.exe" -ArgumentList "delete", $service -NoNewWindow -Wait -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
            } catch {
                Write-Output "WARNING: Failed deleting service '$service': $($_.Exception.Message)"
            }
        }
    }

    function Delete-ServicesByCimPathContains {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string[]] $ContainsAnyOf
        )

        Write-Verbose "Scanning CIM services whose PathName contains any of: $($ContainsAnyOf -join ', ')"
        try {
            $targetSvcs = Get-CimInstance -ClassName Win32_Service | Where-Object {
                $pn = $_.PathName
                (($ContainsAnyOf | Where-Object { $pn -and ($pn -like "*$_*") }).Count) -gt 0
            }

            foreach ($svc in $targetSvcs) {
                Write-Output "Removing service via CIM: $($svc.Name)"
                Write-Verbose "Invoke-CimMethod StopService; then Remove-CimInstance for $($svc.Name)"
                Invoke-CimMethod -InputObject $svc -Name StopService -ErrorAction SilentlyContinue | Out-Null
                Remove-CimInstance -InputObject $svc -Verbose -Confirm:$false -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Output "WARNING: CIM service cleanup error: $($_.Exception.Message)"
        }
    }

    function Remove-ScheduledTaskIfExists {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string] $TaskName
        )

        Write-Verbose "Checking scheduled task: $TaskName"
        try {
            $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
            if ($task) {
                Write-Output "Deleting scheduled task: $TaskName"
                Write-Verbose "Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false"
                Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
            } else {
                Write-Output "INFO: Scheduled task not found: $TaskName"
            }
        } catch {
            Write-Output "WARNING: Scheduled task cleanup error: $($_.Exception.Message)"
        }
    }

    function Remove-Folders {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string[]] $Paths
        )

        foreach ($folder in $Paths) {
            Write-Verbose "Testing folder path: $folder"
            if (Test-Path $folder) {
                Write-Output "Deleting folder: $folder"
                Write-Verbose "Removing all children recursively (first pass), then folder (second pass)"
                try {
                    Get-ChildItem $folder -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -Confirm:$false -Verbose -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                    Remove-Item -Path $folder -Recurse -Force -Confirm:$false -Verbose -ErrorAction SilentlyContinue
                } catch {
                    Write-Output "WARNING: Failed deleting folder '$folder': $($_.Exception.Message)"
                }
            } else {
                Write-Output "INFO: Folder not found: $folder"
            }
        }
    }

    function Remove-RegistryKeys {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string[]] $KeyPaths
        )

        foreach ($key in $KeyPaths) {
            Write-Verbose "Testing registry key: $key"
            if (Test-Path -LiteralPath $key) {
                Write-Output "Deleting registry key: $key"
                Write-Verbose "Remove-Item -Path $key -Recurse -Force -Confirm:$false -Verbose"
                try {
                    Remove-Item -Path $key -Recurse -Force -Confirm:$false -Verbose -ErrorAction SilentlyContinue
                } catch {
                    Write-Output "WARNING: Failed deleting registry key '$key': $($_.Exception.Message)"
                }
            } else {
                Write-Output "INFO: Registry key not found: $key"
            }
        }
    }

    function Find-InstallerRegistryKeysByProductNamePattern {
        <#
        Recursively searches HKLM:\SOFTWARE\Classes\Installer\Products\
        and returns PSCustomObject { Path, ProductName } for keys whose
        ProductName matches the provided regex pattern.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string] $ProductNamePattern,
            [string] $StartPath = 'HKLM:\SOFTWARE\Classes\Installer\Products\'
        )

        Write-Output "Searching Installer registry for ProductName pattern: $ProductNamePattern"
        Write-Verbose "Start path: $StartPath"

        $results = @()

        try {
            $keys = Get-ChildItem -Path $StartPath -Recurse -ErrorAction SilentlyContinue
            foreach ($key in $keys) {
                try {
                    $pn = (Get-ItemProperty -Path $key.PSPath -Name 'ProductName' -ErrorAction SilentlyContinue).ProductName
                    Write-Verbose "Inspecting key: $($key.PSPath) | ProductName='$pn'"
                    if ($pn -and ($pn -match $ProductNamePattern)) {
                        Write-Verbose "Matched: Path='$($key.PSPath)' ProductName='$pn'"
                        $results += [PSCustomObject]@{
                            Path        = $key.PSPath
                            ProductName = $pn
                        }
                    }
                } catch {
                    Write-Verbose "Skipping key (no ProductName): $($key.PSPath)"
                }
            }
        } catch {
            Write-Output "WARNING: Installer registry search error: $($_.Exception.Message)"
        }

        if (-not $results) {
            Write-Output "INFO: No matching Installer registry keys found for '$ProductNamePattern'."
        }

        return $results
    }

    function Remove-InstallerRegistryKeys {
        <#
        Deletes keys provided as PSCustomObject { Path, ProductName }.
        Null-safe and verbose. Uses -LiteralPath to avoid wildcard evaluation.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [Object[]] $Keys
        )

        foreach ($k in $Keys) {
            if (-not $k) {
                Write-Verbose "Skipping null key object"
                continue
            }

            # Safely extract Path even if object is malformed
            $path = $null
            try { $path = $k.Path } catch { $path = $null }

            if ([string]::IsNullOrWhiteSpace($path)) {
                Write-Verbose "Skipping key with empty Path: $($k | Out-String)"
                continue
            }

            Write-Verbose "Verifying Installer key path: $path"
            if (Test-Path -LiteralPath $path) {
                Write-Output "Deleting Installer registry key: $path"
                try {
                    Remove-Item -LiteralPath $path -Recurse -Force -Confirm:$false -Verbose -ErrorAction SilentlyContinue
                } catch {
                    Write-Output "WARNING: Failed deleting '$path': $($_.Exception.Message)"
                }
            } else {
                Write-Output "INFO: Installer key not found (already removed?): $path"
            }
        }
    }

    function Invoke-SilentUninstallFromUninstallString {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string] $UninstallString
        )

        $s = $UninstallString.Trim()
        Write-Verbose "Processing UninstallString: $s"

        if ($s -match '(?i)msiexec(\.exe)?') {
            if ($s -match '{[0-9A-Fa-f\-]{36}}') {
                $guid = $Matches[0]
                Write-Verbose "MSI GUID detected: $guid"
                Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -ErrorAction SilentlyContinue
            } else {
                $args = $s -replace '(?i)/I', '/X'
                $args = $args + ' /qn /norestart'
                Write-Verbose "MSI fallback args: $args"
                Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $args -Wait -ErrorAction SilentlyContinue
            }
        } else {
            $exePath = $s; $argList = ''
            if     ($s -match '^(\".+?\")\s+(.*)$') { $exePath = $Matches[1].Trim('"'); $argList = $Matches[2] }
            elseif ($s -match '^([^\s]+)\s+(.*)$') { $exePath = $Matches[1];            $argList = $Matches[2] }

            # Add common silent switches; duplicates OK
            $argList = ($argList + ' /quiet /silent /verysilent /S /s -silent -S').Trim()

            Write-Verbose "EXE uninstall: Path='$exePath' Args='$argList'"
            if (Test-Path -LiteralPath $exePath) {
                Start-Process -FilePath $exePath -ArgumentList $argList -Wait -ErrorAction SilentlyContinue
            } else {
                Write-Output "WARNING: Uninstall EXE not found: $exePath"
            }
        }
    }

    function Uninstall-ProgramsByDisplayNamePatterns {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string[]] $Patterns
        )

        $uninstallRoots = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )

        foreach ($root in $uninstallRoots) {
            Write-Output "Scanning uninstall hive: $root"
            $subKeys = Get-ChildItem -Path $root -ErrorAction SilentlyContinue
            foreach ($subKey in $subKeys) {
                $props = Get-ItemProperty -Path $subKey.PSPath -ErrorAction SilentlyContinue
                $name  = $props.DisplayName
                $uStr  = $props.UninstallString
                Write-Verbose "Key: $($subKey.PSPath) | DisplayName='$name' | UninstallString='$uStr'"
                if (-not $name -or -not $uStr) { continue }

                foreach ($pat in $Patterns) {
                    if ($name -like $pat) {
                        Write-Output "Uninstalling '$name' via UninstallString (silent)..."
                        Invoke-SilentUninstallFromUninstallString -UninstallString $uStr
                        break
                    }
                }
            }
        }
    }

    # --- Execution ---
    Write-Output ""
    Write-Output "Beginning CW RMM Uninstall (Always Verbose + Non-Interactive)"

    # 1) Official ITSPlatform uninstall
    Invoke-OfficialITSPlatformUninstall

    # 2) Silent uninstall via registry for ITSPlatform-like + ScreenConnect Client
    Uninstall-ProgramsByDisplayNamePatterns -Patterns @('ITSPlatform*','*ScreenConnect Client*')

    # 3) SAAZOD uninstall
    Invoke-SAAZODUninstall

    # 4) Stop processes
    Stop-ProcessesByPatterns -Patterns @('platform-agent*','platform-*-plugin','SAAZ*','rthlpdk','ITSPlatform*')

    # 5) Stop services
    Stop-ServicesByPatterns -Patterns @('ITSPlatform*','SAAZ*')

    # Collect concrete service names for deletion
    Write-Verbose "Collecting services for deletion with patterns: ITSPlatform*, SAAZ*"
    $ServicesToDelete = Get-Service -Name 'ITSPlatform*','SAAZ*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    if ($ServicesToDelete) {
        Write-Output "Deleting services via sc.exe: $($ServicesToDelete -join ', ')"
        Delete-ServicesByNames -ServiceNames $ServicesToDelete
    } else {
        Write-Output "INFO: No matching services to delete via sc.exe."
    }

    # 7) Alternative service deletion via CIM (PathName contains tokens)
    Delete-ServicesByCimPathContains -ContainsAnyOf @('ITSPlatform','SAAZ')

    # 8) Scheduled Task cleanup
    Remove-ScheduledTaskIfExists -TaskName 'ITSPlatformSelfHealUtility'

    # 9) Delete folders
    Remove-Folders -Paths @(
        'C:\Program Files (x86)\ITSPlatformSetupLogs',
        'C:\Program Files (x86)\ITSPlatform',
        'C:\Program Files (x86)\SAAZOD',
        'C:\Program Files (x86)\SAAZODBKP',
        'C:\ProgramData\SAAZOD'
    )

    # 10) Remove rogue "C:\Program" file (bad uninstaller artifact)
    Write-Output "Checking for rogue 'C:\Program' file..."
    try {
        if (Test-Path -LiteralPath "C:\Program" -PathType Leaf) {
            Write-Output "Deleting rogue 'C:\Program' file."
            Write-Verbose "Remove-Item -LiteralPath 'C:\Program' -Force -Confirm:$false -Verbose"
            Remove-Item -LiteralPath "C:\Program" -Force -Confirm:$false -Verbose -ErrorAction SilentlyContinue
        } else {
            Write-Output "INFO: Rogue 'C:\Program' file not found."
        }
    } catch {
        Write-Output "WARNING: Failed removing 'C:\Program': $($_.Exception.Message)"
    }

    # 11) Remove registry keys (main hives)
    Write-Output "Deleting CW RMM registry keys (primary hives)..."
    Remove-RegistryKeys -KeyPaths @(
        'HKLM:\SOFTWARE\WOW6432Node\SAAZOD',
        'HKLM:\SOFTWARE\WOW6432Node\ITSPlatform'
    )

    # 12) Remove odd blank/space-padded ITSPlatform key variants
    foreach ($blankKey in @(
        "HKLM:\SOFTWARE\WOW6432Node\ \ITSPlatform",
        "HKLM:\SOFTWARE\WOW6432Node\  \ITSPlatform"
    )) {
        Write-Verbose "Testing blank-padded registry key: $blankKey"
        if (Test-Path -LiteralPath $blankKey) {
            Write-Output "Deleting blank-padded registry key: $blankKey"
            try {
                Remove-Item -Path $blankKey -Recurse -Force -Confirm:$false -Verbose -ErrorAction Stop
                Write-Output "Blank-padded registry key deleted successfully."
            } catch {
                Write-Output "WARNING: Failed to delete blank-padded key '$blankKey': $($_.Exception.Message)"
                try {
                    $parentKey = Split-Path $blankKey -Parent
                    Write-Output "Attempting parent key delete: $parentKey"
                    Remove-Item -Path $parentKey -Recurse -Force -Confirm:$false -Verbose -ErrorAction Stop
                    Write-Output "Parent registry keys deleted successfully."
                } catch {
                    Write-Output "WARNING: Failed to delete parent of blank-padded key '$blankKey': $($_.Exception.Message)"
                }
            }
        } else {
            Write-Output "INFO: Blank-padded registry key not found: $blankKey"
        }
    }

    # 13) Improved MSI Installer keys cleanup (recursive find → delete)
    Write-Output "Cleaning MSI Installer registry keys matching ITSPlatform.*"
    $ProductRegistryKeysToRemoveITS = Find-InstallerRegistryKeysByProductNamePattern -ProductNamePattern 'ITSPlatform.*'
    if ($ProductRegistryKeysToRemoveITS) {
        Write-Output "Deleting matched ITSPlatform Installer registry keys..."
        Remove-InstallerRegistryKeys -Keys $ProductRegistryKeysToRemoveITS
    }

    Write-Output "Cleaning MSI Installer registry keys matching ScreenConnect Client.*"
    $ProductRegistryKeysToRemoveSC = Find-InstallerRegistryKeysByProductNamePattern -ProductNamePattern 'ScreenConnect Client.*'
    if ($ProductRegistryKeysToRemoveSC) {
        Write-Output "Deleting matched ScreenConnect Client Installer registry keys..."
        Remove-InstallerRegistryKeys -Keys $ProductRegistryKeysToRemoveSC
    }

    Write-Output ""
    Write-Output "Done! CW RMM should be successfully uninstalled and remnants removed."
    Write-Verbose "Uninstall script completed. Transcript path: $logPath"

    try { Stop-Transcript | Out-Null } catch { }

    Start-Sleep -Seconds 2
    Write-Host "Uninstall completed." -ForegroundColor Green
}

function Invoke-VoodooInstall {
    [CmdletBinding()]
    param()

    Write-Host "Running Voodoo Install..." -ForegroundColor Green
    $Dir = "C:\Kelley\"

    function CreateDirectory {
        if (-not (Test-Path -Path $Dir -PathType Container)) {
            New-Item -ItemType Directory -Path $Dir -Force -ErrorAction Stop
            Write-Host "Path Creation Completed"
        } else {
            Write-Host "Path already exists"
        }
    }

    function DownloadFile {
        $URI = Read-Host "Enter the URI of the file to download"
        $FileName = [regex]::Match($URI, "(?<=/)[^/]*(?=/MSI/setup)").Value.Replace("%20", " ")
        $FileName += ".msi"
        $FilePath = Join-Path -Path $Dir -ChildPath $FileName

        if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
            try {
                Invoke-WebRequest -Uri $URI -OutFile $FilePath -ErrorAction Stop
                Write-Host "[$FilePath] Created"
            } catch {
                Write-Host "Failed to download the file from the specified URI"
                return
            }
        } else {
            Write-Host "[$FilePath] already exists"
        }

        InstallFile -FilePath $FilePath
    }

    function InstallFile {
        param([string]$FilePath)

        if (Test-Path -Path $FilePath -PathType Leaf) {
            try {
                $msiPackageToInstall = $FilePath
                $tmpFile = [System.IO.Path]::GetTempFileName()
                Start-Process msiexec -ArgumentList "/i `"$msiPackageToInstall`" /qn /L*v `"$tmpFile`"" -NoNewWindow -Wait
                Write-Host "[$FilePath] installed successfully"
            } catch {
                Write-Host "Failed to install the file"
            }
        } else {
            Write-Host "File [$FilePath] does not exist"
        }
    }

    # Run CreateDirectory, then DownloadFile, then InstallFile functions
    CreateDirectory
    DownloadFile

    Start-Sleep -Seconds 2
    Write-Host "Install completed." -ForegroundColor Green
}

function Show-Pause {
    Write-Host ""
    Write-Host "Press any key to continue..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Main execution loop
do {
    Show-Menu
    $Selection = Read-Host "Please make a selection (0-20)"

    switch ($Selection) {
        '0'  { Write-Host "Exiting..." -ForegroundColor Yellow; break }
        '10' { Invoke-PlatformWatchdogRestore;   Show-Pause }
        '11' { Invoke-PlatformWatchdogUpdate;    Show-Pause }
        '12' { Invoke-PlatformWatchdogUninstall; Show-Pause }
        '19' { Invoke-VoodooUninstall;           Show-Pause }
        '20' { Invoke-VoodooInstall;             Show-Pause }
        default {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
} while ($Selection -ne '0')

Write-Host "Script completed. Goodbye!" -ForegroundColor Cyan
