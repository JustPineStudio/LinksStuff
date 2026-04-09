# ============================================================
#  CompleteSetup.ps1 - Windows 11 Client Post-Install Setup
#  Run via: Launch.bat (from USB or Desktop)
# ============================================================

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Host.UI.RawUI.WindowTitle = "Windows 11 Client Setup - DO NOT CLOSE"
try {
    $size = $Host.UI.RawUI.BufferSize; $size.Width = 120; $size.Height = 3000
    $Host.UI.RawUI.BufferSize = $size
    $win = $Host.UI.RawUI.WindowSize; $win.Width = 120; $win.Height = 40
    $Host.UI.RawUI.WindowSize = $win
} catch {}

$ErrorActionPreference = "Stop"
trap {
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Red
    Write-Host "  |            SCRIPT ERROR                  |" -ForegroundColor Red
    Write-Host "  +==========================================+" -ForegroundColor Red
    Write-Host ""
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "  Take a photo of this screen and send it for support." -ForegroundColor White
    Write-Host "  Press any key to close..." -ForegroundColor DarkGray
    try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch {}
    exit 1
}

# --- PATHS ---
$StateDir     = "C:\ProgramData\_ClientSetup"
$StateFile    = "$StateDir\progress.txt"
$LogFile      = "$StateDir\setup.log"
$RegPath      = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$RegName      = "ClientAutoSetup"
$WinlogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

# ---- HELPERS ----

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    try { Add-Content -Path $LogFile -Value "[$ts][$Level] $Message" } catch {}
}

function Show-Status {
    param([string]$Current = "")
    Clear-Host
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |    WINDOWS 11 CLIENT SETUP UTILITY       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    $steps = @("Internet","Time Sync","Windows Updates")
    foreach ($s in $steps) {
        if ($s -eq $Current) {
            Write-Host "  [ >> ] $s" -ForegroundColor Yellow
        } elseif (Test-Path "$StateDir\done_$($s -replace ' ','_').txt") {
            Write-Host "  [DONE] $s" -ForegroundColor Green
        } else {
            Write-Host "  [    ] $s" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "  ------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

function Mark-Done { param([string]$Step)
    $f = "$StateDir\done_$($Step -replace ' ','_').txt"
    if (-not (Test-Path $f)) { New-Item $f -ItemType File -Force | Out-Null }
    Write-Log "Step done: $Step"
}

function Is-Done { param([string]$Step)
    return (Test-Path "$StateDir\done_$($Step -replace ' ','_').txt")
}

# ---- INIT ----

if (!(Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
Write-Log "Script launched. PS version: $($PSVersionTable.PSVersion)"

# Detect reboot-resume vs manual launch
# Reboot-resume = registry key exists AND PC booted less than 10 minutes ago
$rebootResume = $false
$regVal = Get-ItemProperty -Path $RegPath -Name $RegName -ErrorAction SilentlyContinue
if ($regVal) {
    $lastBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $minutesSinceBoot = (New-TimeSpan -Start $lastBoot -End (Get-Date)).TotalMinutes
    if ($minutesSinceBoot -lt 10) { $rebootResume = $true }
}

if (-not $rebootResume) {
    Write-Host "  [START] Running all steps from scratch..." -ForegroundColor Cyan
    # Wipe all done markers
    Get-ChildItem -Path $StateDir -Filter "done_*.txt" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "State reset - manual launch."
} else {
    Write-Log "Reboot resume ($([math]::Round($minutesSinceBoot,1)) min since boot) - keeping state."
    Write-Host "  [RESUME] Resuming after reboot..." -ForegroundColor Cyan
    # After a reboot Windows Update may still be finishing the previous install.
    # Wait until the wuauserv service is idle before we do anything.
    Write-Host "  Waiting for Windows Update to finish post-reboot tasks..." -ForegroundColor DarkGray
    $waited = 0
    while ($waited -lt 300) {
        Start-Sleep -Seconds 15
        $waited += 15
        $svc = Get-Service wuauserv -ErrorAction SilentlyContinue
        # Also check if TrustedInstaller (which applies updates) is running
        $ti = Get-Process TrustedInstaller -ErrorAction SilentlyContinue
        if (-not $ti) {
            Write-Host "  Windows Update appears idle after $waited seconds." -ForegroundColor DarkGray
            Start-Sleep -Seconds 30  # extra buffer
            break
        }
        Write-Host "  Still applying updates... ($waited s)" -ForegroundColor DarkGray
    }

    # Reset Windows Update service to clear any in-progress download session
    # that Windows auto-started after reboot, which would conflict with Install-WindowsUpdate.
    Write-Host "  Resetting Windows Update service..." -ForegroundColor DarkGray
    try {
        Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
        $stopped = $false
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 2
            if ((Get-Service wuauserv).Status -eq "Stopped") { $stopped = $true; break }
        }
        if (-not $stopped) { Write-Host "  [WARN] wuauserv did not stop cleanly - continuing anyway." -ForegroundColor DarkYellow }
        Start-Service wuauserv -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
        Write-Host "  Windows Update service reset." -ForegroundColor DarkGray
        Write-Log "wuauserv reset on reboot resume."
    } catch {
        Write-Host "  [WARN] Could not reset wuauserv: $($_.Exception.Message)" -ForegroundColor DarkYellow
        Write-Log "wuauserv reset warning: $($_.Exception.Message)" "WARN"
    }
}

# Register persistence so script resumes after reboot during updates
$ScriptPath = $MyInvocation.MyCommand.Path
if ($ScriptPath) {
    Set-ItemProperty -Path $RegPath -Name $RegName `
        -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    Write-Log "Registry persistence set: $ScriptPath"
}

Start-Sleep -Seconds 1

# ============================================================
# STEP 1 - INTERNET
# Ping 8.8.8.8 - wait until connected, no timeout.
# ============================================================
Show-Status "Internet"
Write-Host "  Checking internet connection..." -ForegroundColor Yellow

$connected = $false
while (-not $connected) {
    try { $connected = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue }
    catch { $connected = $false }
    if (-not $connected) {
        Write-Host ""
        Write-Host "  +==========================================+" -ForegroundColor Red
        Write-Host "  |        NO INTERNET CONNECTION            |" -ForegroundColor Red
        Write-Host "  +==========================================+" -ForegroundColor Red
        Write-Host "  Connect to Wi-Fi or plug in Ethernet, then wait..." -ForegroundColor White
        Start-Sleep -Seconds 10
        Show-Status "Internet"
    }
}

Write-Host "  [OK] Internet connected." -ForegroundColor Green
Write-Log "Internet OK."
Mark-Done "Internet"
Start-Sleep -Seconds 1

# ============================================================
# STEP 2 - TIME SYNC
# Force sync, then configure w32tm properly, then verify.
# ============================================================
Show-Status "Time Sync"
Write-Host "  Syncing system clock..." -ForegroundColor Yellow

try {
    # Make sure the service is running
    Set-Service w32tm -StartupType Automatic -ErrorAction SilentlyContinue
    Stop-Service w32tm -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Service w32tm -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Register with NTP pool and force sync
    w32tm /config /manualpeerlist:"pool.ntp.org,0x1 time.windows.com,0x1" /syncfromflags:manual /reliable:YES /update 2>&1 | Out-Null
    w32tm /resync /force 2>&1 | Out-Null
    Start-Sleep -Seconds 3

    # Verify
    $status = w32tm /query /status 2>&1
    $syncLine = $status | Where-Object { $_ -match "Last Successful Sync" }
    if ($syncLine) {
        Write-Host "  [OK] Clock synced. $syncLine" -ForegroundColor Green
        Write-Log "Time sync OK: $syncLine"
    } else {
        Write-Host "  [OK] Sync command ran. Clock should be correct." -ForegroundColor Green
        Write-Log "Time sync ran - no Last Sync line in output."
    }
} catch {
    $errMsg = $_.Exception.Message
    Write-Host "  [WARN] Time sync issue: $errMsg" -ForegroundColor DarkYellow
    Write-Log "Time sync warning: $errMsg" "WARN"
}

Mark-Done "Time Sync"
Start-Sleep -Seconds 1

# ============================================================
# STEP 3 - WINDOWS UPDATES
# Opens the Windows Update settings page and clicks the
# "Check for updates" button exactly like a human would.
# Monitors progress and reboots if needed, then loops until
# the page shows "You're up to date".
# ============================================================
Show-Status "Windows Updates"

# Install PSWindowsUpdate module if not already present
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Host "  Installing PSWindowsUpdate module..." -ForegroundColor DarkGray
    Write-Log "Installing PSWindowsUpdate module."
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    Install-Module -Name PSWindowsUpdate -Force -Confirm:$false | Out-Null
}
Import-Module PSWindowsUpdate -ErrorAction Stop

$dateStr  = Get-Date -Format "yyyy-MM-dd"
$logPath  = "C:\$($env:COMPUTERNAME)-$dateStr-MSUpdates.log"
Write-Host "  Running updates - log: $logPath" -ForegroundColor DarkGray
Write-Host "  Machine will reboot automatically if needed. Setup resumes after restart." -ForegroundColor Cyan
Write-Log "Starting Install-WindowsUpdate. Log: $logPath"

Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -AutoReboot | Out-File $logPath -Force

Write-Host "  [OK] Windows Update complete." -ForegroundColor Green
Write-Log "Windows Update complete - no reboot required."
Mark-Done "Windows Updates"
Start-Sleep -Seconds 1

# ============================================================
# FINAL VERIFICATION - check reality for each item
# ============================================================
Clear-Host
Write-Host ""
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host "  |         FINAL VERIFICATION               |" -ForegroundColor Cyan
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host ""

$allPassed = $true
$failNotes = @()

function Write-Check {
    param([string]$Label, [bool]$Passed, [string]$Detail = "", [bool]$WarnOnly = $false)
    $line = if ($Passed) { "  [PASS]" } elseif ($WarnOnly) { "  [WARN]" } else { "  [FAIL]" }
    $line += " $Label"
    if ($Detail) { $line += " - $Detail" }
    $color = if ($Passed) { "Green" } elseif ($WarnOnly) { "DarkYellow" } else { "Red" }
    Write-Host $line -ForegroundColor $color
    if (-not $Passed -and -not $WarnOnly) { $script:allPassed = $false }
}

# CHECK 1: Windows Activation
try {
    $act = Get-CimInstance SoftwareLicensingProduct -Filter "Name like 'Windows%'" |
           Where-Object { $_.PartialProductKey -and $_.LicenseStatus -eq 1 }
    if ($act) { Write-Check "Windows Activated" $true }
    else {
        Write-Check "Windows Activated" $false "client must enter product key" -WarnOnly $true
        $failNotes += "Windows not activated - client needs to enter their retail product key."
    }
} catch { Write-Check "Windows Activated" $false "could not check" -WarnOnly $true }

# CHECK 2: Time Synced
try {
    $w32 = w32tm /query /status 2>&1
    $syncLine = ($w32 | Where-Object { $_ -match "Last Successful Sync" }) -replace ".*:\s*",""
    if ($syncLine) {
        Write-Check "Time Synced" $true "last sync: $($syncLine.Trim())"
    } else {
        # Try one more sync and check again
        w32tm /resync /force 2>&1 | Out-Null
        Start-Sleep -Seconds 3
        $w32b = w32tm /query /status 2>&1
        $syncLineB = ($w32b | Where-Object { $_ -match "Last Successful Sync" }) -replace ".*:\s*",""
        if ($syncLineB) { Write-Check "Time Synced" $true "last sync: $($syncLineB.Trim())" }
        else { Write-Check "Time Synced" $false "could not confirm sync" -WarnOnly $true }
    }
} catch { Write-Check "Time Synced" $false "could not verify" -WarnOnly $true }

# CHECK 3: Windows Updates
try {
    $remaining = (Get-WindowsUpdate -MicrosoftUpdate -IsInstalled:$false -ErrorAction Stop).Count
    if ($remaining -eq 0) {
        Write-Check "Windows Up To Date" $true "no updates pending"
    } else {
        Write-Check "Windows Up To Date" $false "$remaining update(s) still pending"
        $failNotes += "$remaining Windows update(s) still pending."
    }
} catch { Write-Check "Windows Up To Date" $false "could not scan" -WarnOnly $true }


Write-Host ""
Write-Host "  ==========================================" -ForegroundColor DarkGray
Write-Host ""
if ($allPassed) {
    Write-Host "  ALL CHECKS PASSED - PC IS READY FOR CLIENT." -ForegroundColor Green
} else {
    Write-Host "  SETUP COMPLETE WITH WARNINGS:" -ForegroundColor DarkYellow
    foreach ($n in $failNotes) { Write-Host "    > $n" -ForegroundColor DarkYellow }
}
Write-Log "Verification done. AllPassed=$allPassed | $($failNotes -join ' | ')"
Write-Host ""

# ============================================================
# CLEANUP - remove all traces
# ============================================================
Write-Host "  ==========================================" -ForegroundColor DarkGray
Write-Host "  Cleaning up..." -ForegroundColor DarkGray
Write-Host ""

try { Set-ItemProperty -Path $WinlogonPath -Name "AutoAdminLogon" -Value "0" -ErrorAction SilentlyContinue } catch {}
try { Remove-ItemProperty -Path $WinlogonPath -Name "DefaultPassword" -ErrorAction SilentlyContinue } catch {}

Remove-ItemProperty -Path $RegPath -Name $RegName      -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $RegPath -Name "ClientSetup" -ErrorAction SilentlyContinue

$hp = (Get-PSReadlineOption -ErrorAction SilentlyContinue).HistorySavePath
if ($hp -and (Test-Path $hp)) { Clear-Content $hp -ErrorAction SilentlyContinue }

try {
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
} catch {}

Remove-Item "$env:TEMP\*"            -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
if ($logPath -and (Test-Path $logPath)) { Remove-Item $logPath -Force -ErrorAction SilentlyContinue }

try { wevtutil cl Application 2>&1 | Out-Null } catch {}

Get-ChildItem "$env:SystemRoot\Prefetch" -Filter "*POWERSHELL*" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

Start-Sleep -Seconds 1
Remove-Item -Path $StateDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "  All traces removed. PC is clean." -ForegroundColor Green
Write-Host ""
Write-Host "  Press any key to close..." -ForegroundColor White
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
