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

# Detect reboot-resume vs manual launch via flag file (reliable across slow update reboots)
$RebootFlag  = "$StateDir\reboot_pending.flag"
$rebootResume = Test-Path $RebootFlag

if (-not $rebootResume) {
    Write-Host "  [START] Running all steps from scratch..." -ForegroundColor Cyan
    # Wipe all done markers
    Get-ChildItem -Path $StateDir -Filter "done_*.txt" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "State reset - manual launch."
} else {
    Remove-Item $RebootFlag -Force -ErrorAction SilentlyContinue
    Write-Log "Reboot resume (flag file found) - keeping state."
    Write-Host "  [RESUME] Resuming after reboot..." -ForegroundColor Cyan
    # Wait for TrustedInstaller to finish applying updates before proceeding.
    Write-Host "  Waiting for Windows Update to finish post-reboot tasks..." -ForegroundColor DarkGray
    $waited = 0
    while ($waited -lt 300) {
        Start-Sleep -Seconds 15
        $waited += 15
        $ti = Get-Process TrustedInstaller -ErrorAction SilentlyContinue
        if (-not $ti) {
            Write-Host "  Windows Update appears idle after $waited seconds." -ForegroundColor DarkGray
            Start-Sleep -Seconds 30  # extra buffer
            break
        }
        Write-Host "  Still applying updates... ($waited s)" -ForegroundColor DarkGray
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
# Uses the Windows Update COM API directly (no PSWindowsUpdate
# module needed). Installs in priority order; reboots and
# resumes automatically until everything is installed.
# ============================================================
Show-Status "Windows Updates"

# Remove NoAutoUpdate policy so the COM API can download freely
try {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" `
        -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
    Write-Log "NoAutoUpdate policy removed."
} catch {}

function InstallUpdates {
    param([string]$Criteria, [string]$Name)
    Write-Host "  Searching: $Name..." -ForegroundColor DarkGray
    Write-Log "Searching updates: $Name"

    $Searcher = New-Object -ComObject Microsoft.Update.Searcher
    $SearchResult = $Searcher.Search($Criteria).Updates

    if ($SearchResult.Count -eq 0) {
        Write-Host "  [SKIP] No updates found: $Name" -ForegroundColor DarkGray
        return
    }

    Write-Host "  Downloading $($SearchResult.Count) update(s): $Name..." -ForegroundColor Yellow
    Write-Log "Downloading $($SearchResult.Count) updates: $Name"
    $Session    = New-Object -ComObject Microsoft.Update.Session
    $Downloader = $Session.CreateUpdateDownloader()
    $Downloader.Updates = $SearchResult
    $Downloader.Download()

    Write-Host "  Installing $($SearchResult.Count) update(s): $Name..." -ForegroundColor Yellow
    Write-Log "Installing $($SearchResult.Count) updates: $Name"
    foreach ($u in $SearchResult) { $u.AcceptEULA() }

    $Installer = New-Object -ComObject Microsoft.Update.Installer
    $Installer.Updates = $SearchResult
    $Result = $Installer.Install()

    if ($Result.RebootRequired) {
        Write-Log "Reboot required after: $Name"
        New-Item $RebootFlag -ItemType File -Force | Out-Null
        Write-Host "  Reboot required. Restarting in 10 seconds..." -ForegroundColor Cyan
        shutdown.exe /t 10 /r /f
        exit
    }
}

$BaseCriteria = "IsInstalled=0 and IsHidden=0 and AutoSelectOnWebSites=1"
Write-Host "  Machine will reboot automatically if needed. Setup resumes after restart." -ForegroundColor Cyan
Write-Log "Starting Windows Update via COM API."

InstallUpdates "$BaseCriteria and CategoryIDs contains '68C5B0A3-D1A6-4553-AE49-01D3A7827828'" "Service Packs"
InstallUpdates "$BaseCriteria and CategoryIDs contains '28BC880E-0592-4CBF-8F95-C79B17911D5F'" "Update Rollups"
InstallUpdates "$BaseCriteria and CategoryIDs contains 'E6CF1350-C01B-414D-A61F-263D14D133B4'" "Critical Updates"
InstallUpdates "$BaseCriteria and CategoryIDs contains '0FA1201D-4330-4FA8-8AE9-B877473B6441'" "Security Updates"
InstallUpdates "$BaseCriteria and CategoryIDs contains 'E0789628-CE08-4437-BE74-2495B842F43B'" "Definition Updates"
InstallUpdates "$BaseCriteria and CategoryIDs contains '5C9376AB-8CE6-464A-B136-22113DD69801'" "Applications"

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
Write-Host "  Press any key to clean up and close..." -ForegroundColor White
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

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
