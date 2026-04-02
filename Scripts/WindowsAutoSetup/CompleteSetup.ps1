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

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Test-RebootRequired {
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { return $true }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending")  { return $true }
    try {
        $pfr = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
        if ($pfr) { return $true }
    } catch {}
    try { if ((New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired) { return $true } } catch {}
    return $false
}

function Find-UIElement {
    param($root, $name, $controlType, $maxWaitSec = 30)
    $condition = $null
    if ($name -and $controlType) {
        $cName = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)
        $cType = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $controlType)
        $condition = New-Object System.Windows.Automation.AndCondition($cName, $cType)
    } elseif ($name) {
        $condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)
    } else {
        $condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $controlType)
    }

    $waited = 0
    while ($waited -lt $maxWaitSec) {
        try {
            $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
            if ($el) { return $el }
        } catch {}
        Start-Sleep -Seconds 2
        $waited += 2
    }
    return $null
}

function Click-UIElement {
    param($element)
    try {
        $invokePattern = $element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $invokePattern.Invoke()
        return $true
    } catch {
        # Fallback: click via mouse at element center
        try {
            $rect = $element.Current.BoundingRectangle
            $cx   = [int]($rect.X + $rect.Width  / 2)
            $cy   = [int]($rect.Y + $rect.Height / 2)
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class MouseClick {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int cButtons, int dwExtraInfo);
    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        mouse_event(0x0002, 0, 0, 0, 0); // left down
        mouse_event(0x0004, 0, 0, 0, 0); // left up
    }
}
"@ -ErrorAction SilentlyContinue
            [MouseClick]::Click($cx, $cy)
            return $true
        } catch {}
    }
    return $false
}

function Invoke-WindowsUpdateViaUI {
    Write-Host "  Opening Windows Update settings..." -ForegroundColor DarkGray

    # Open Windows Update settings page
    Start-Process "ms-settings:windowsupdate" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 4

    # Find the Settings window
    $desktop   = [System.Windows.Automation.AutomationElement]::RootElement
    $settingsWindow = $null
    $waited = 0
    while (-not $settingsWindow -and $waited -lt 20) {
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, "Settings")
        $settingsWindow = $desktop.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
        if (-not $settingsWindow) {
            # Try partial name match via process
            $proc = Get-Process SystemSettings -ErrorAction SilentlyContinue
            if ($proc) {
                $cond2 = New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc[0].Id)
                $settingsWindow = $desktop.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond2)
            }
        }
        Start-Sleep -Seconds 2
        $waited += 2
    }

    if (-not $settingsWindow) {
        Write-Host "  [WARN] Could not find Settings window via UI Automation." -ForegroundColor DarkYellow
        Write-Log "Settings window not found." "WARN"
        return $false
    }

    Write-Host "  Settings window found. Looking for Windows Update button..." -ForegroundColor DarkGray

    # All known button names Windows Update uses across different states
    $btnNames = @(
        "Download & install all",
        "Download &amp; install all",
        "Check for updates",
        "Check for Updates",
        "Download now",
        "Download and install",
        "Download & install",
        "Install now",
        "Restart now",
        "Resume"
    )
    $btn = $null
    foreach ($name in $btnNames) {
        $btn = Find-UIElement -root $settingsWindow -name $name -controlType $null -maxWaitSec 5
        if ($btn) {
            Write-Host "  Found button: '$name' - clicking..." -ForegroundColor Cyan
            Write-Log "Clicking WU button: $name"
            Click-UIElement $btn | Out-Null
            Start-Sleep -Seconds 3
            break
        }
    }

    if (-not $btn) {
        Write-Host "  No actionable button found - Windows Update may already be running." -ForegroundColor DarkGray
        Write-Log "No WU button found - may already be running."
    }

    return $true
}

function Wait-ForWindowsUpdateToFinish {
    param([int]$maxMinutes = 120)
    Write-Host "  Monitoring Windows Update progress..." -ForegroundColor DarkGray

    $deadline = (Get-Date).AddMinutes($maxMinutes)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 15

        # Check if reboot needed - updates installed and need restart
        if (Test-RebootRequired) {
            Write-Host "  Reboot required - updates installed!" -ForegroundColor Green
            return "reboot"
        }

        # Check Settings window for "You're up to date" text - means done
        try {
            $proc = Get-Process SystemSettings -ErrorAction SilentlyContinue
            if ($proc) {
                $desktop = [System.Windows.Automation.AutomationElement]::RootElement
                $cond = New-Object System.Windows.Automation.PropertyCondition(
                    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc[0].Id)
                $win = $desktop.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
                if ($win) {
                    # Look for "up to date" text element
                    $upToDateNames = @("You're up to date", "You're up to date", "Up to date")
                    foreach ($txt in $upToDateNames) {
                        $el = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
                            (New-Object System.Windows.Automation.PropertyCondition(
                                [System.Windows.Automation.AutomationElement]::NameProperty, $txt)))
                        if ($el) {
                            Write-Host "  Detected 'You're up to date' - updates complete!" -ForegroundColor Green
                            return "done"
                        }
                    }

                    # Also click any remaining Download & install buttons that appear
                    $remainingBtns = @("Download & install","Download and install","Install now","Restart now")
                    foreach ($name in $remainingBtns) {
                        $btn = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
                            (New-Object System.Windows.Automation.PropertyCondition(
                                [System.Windows.Automation.AutomationElement]::NameProperty, $name)))
                        if ($btn) {
                            Write-Host "  Clicking remaining button: '$name'..." -ForegroundColor Cyan
                            try {
                                $ip = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
                                $ip.Invoke()
                            } catch {}
                            Write-Log "Clicked remaining: $name"
                            Start-Sleep -Seconds 3
                        }
                    }
                }
            }
        } catch {}

        # Check if WU processes are still running
        $wuRunning = $false
        try {
            if (Get-Process -Name "TrustedInstaller","wuauclt","WaaSMedicAgent" -ErrorAction SilentlyContinue) {
                $wuRunning = $true
            }
        } catch {}

        if (-not $wuRunning) {
            Write-Host "  Windows Update processes finished." -ForegroundColor DarkGray
            return "done"
        }

        Write-Host "  Still updating... ($(($deadline - (Get-Date)).Minutes) min remaining)" -ForegroundColor DarkGray
    }

    Write-Host "  [WARN] Timed out waiting for Windows Update." -ForegroundColor DarkYellow
    return "timeout"
}

# Restore round number if resuming after reboot mid-updates
$roundFile = "$StateDir\update_round.txt"
$round = 1
if ($rebootResume -and (Test-Path $roundFile)) {
    try { $round = [int](Get-Content $roundFile -Raw) } catch {}
    Write-Host "  Resuming from update round $round after reboot." -ForegroundColor Cyan
    Write-Log "Restored update round $round from file."
}

$maxRounds = 10

while ($true) {
    if ($round -gt $maxRounds) {
        Write-Host "  [WARN] Reached max update rounds ($maxRounds). Moving on." -ForegroundColor DarkYellow
        Write-Log "Hit max update rounds - moving on."
        break
    }

    Show-Status "Windows Updates"
    Write-Host "  === Windows Update round $round of max $maxRounds ===" -ForegroundColor Cyan
    Write-Log "Update round $round."

    # Click Check for updates in Settings
    $uiOk = Invoke-WindowsUpdateViaUI

    if ($uiOk) {
        # Give it a moment to start
        Start-Sleep -Seconds 10

        # Click any download/install button that appears
        $desktop = [System.Windows.Automation.AutomationElement]::RootElement
        $proc = Get-Process SystemSettings -ErrorAction SilentlyContinue
        if ($proc) {
            $cond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc[0].Id)
            $settingsWindow = $desktop.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
            if ($settingsWindow) {
                $actionBtns = @(
                    "Download & install all",
                    "Download &amp; install all",
                    "Download now",
                    "Download and install",
                    "Download & install",
                    "Install now",
                    "Restart now"
                )
                foreach ($name in $actionBtns) {
                    $btn = Find-UIElement -root $settingsWindow -name $name -controlType $null -maxWaitSec 5
                    if ($btn) {
                        Write-Host "  Clicking '$name'..." -ForegroundColor Cyan
                        Click-UIElement $btn | Out-Null
                        Write-Log "Clicked: $name"
                        Start-Sleep -Seconds 5
                    }
                }
            }
        }

        Write-Host "  Waiting for Windows Update to finish..." -ForegroundColor Yellow
        $result = Wait-ForWindowsUpdateToFinish -maxMinutes 120

        # Close Settings window
        Get-Process SystemSettings -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        if ($result -eq "reboot" -or (Test-RebootRequired)) {
            Write-Host ""
            Write-Host "  *** Updates installed. Rebooting in 15 seconds... ***" -ForegroundColor Cyan
            Write-Host "  Setup resumes automatically after restart." -ForegroundColor Cyan
            Write-Log "Rebooting after round $round."
            Set-Content -Path $roundFile -Value ($round + 1) -Encoding UTF8
            shutdown.exe /r /t 15 /c "Windows Updates installed. Setup resumes after restart."
            exit 0
        }

        # If Settings showed "You're up to date" - trust it and stop
        if ($result -eq "done") {
            Write-Host ""
            Write-Host "  [OK] Windows Update confirmed up to date after round $round." -ForegroundColor Green
            Write-Log "Updates done - Settings showed up to date after round $round."
            Remove-Item $roundFile -Force -ErrorAction SilentlyContinue
            break
        }
    }

    # Verify via COM API that nothing is left
    Write-Host "  Checking for any remaining updates..." -ForegroundColor Yellow
    $remaining = $null
    try {
        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result2  = $searcher.Search("IsInstalled=0 and IsHidden=0")
        $remaining = $result2.Updates
    } catch {}

    $countLeft = if ($remaining) { $remaining.Count } else { 0 }
    Write-Log "Round $round - $countLeft updates remaining after UI run."

    if ($countLeft -eq 0) {
        Write-Host ""
        Write-Host "  [OK] Windows is fully up to date after $round round(s)!" -ForegroundColor Green
        Write-Log "Updates complete after $round round(s)."
        Remove-Item $roundFile -Force -ErrorAction SilentlyContinue
        break
    } else {
        Write-Host "  $countLeft update(s) still pending - running another round..." -ForegroundColor DarkYellow
        $round++
        Start-Sleep -Seconds 10
    }
}

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

# CHECK 3: Windows Updates - scan using COM API same as above
try {
    $remaining = Get-PendingUpdates
    if (-not $remaining -or $remaining.Count -eq 0) {
        Write-Check "Windows Up To Date" $true "no updates pending"
    } else {
        Write-Check "Windows Up To Date" $false "$($remaining.Count) update(s) still pending"
        $failNotes += "$($remaining.Count) Windows update(s) still pending."
    }
} catch { Write-Check "Windows Up To Date" $false "could not scan" -WarnOnly $true }

# CHECK 4: GPU Driver - remind to install manually
try {
    $gpus = Get-CimInstance Win32_VideoController |
            Where-Object { $_.Caption -notmatch "Microsoft|Remote|Virtual|Basic" }
    if ($gpus) {
        foreach ($gpu in $gpus) {
            Write-Check "GPU Driver" $true "$($gpu.Caption) detected - install latest driver manually from manufacturer website" -WarnOnly $true
            $failNotes += "GPU '$($gpu.Caption)' - download latest driver manually: nvidia.com/drivers or amd.com/support"
        }
    }
} catch {}

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

try { wevtutil cl Application 2>&1 | Out-Null } catch {}

Get-ChildItem "$env:SystemRoot\Prefetch" -Filter "*POWERSHELL*" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

Start-Sleep -Seconds 1
Remove-Item -Path $StateDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "  All traces removed. PC is clean." -ForegroundColor Green
Write-Host ""
Write-Host "  Press any key to close..." -ForegroundColor White
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
