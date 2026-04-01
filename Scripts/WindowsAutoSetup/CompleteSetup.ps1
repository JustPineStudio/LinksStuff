# ============================================================
#  CompleteSetup.ps1 - Windows 11 Client Post-Install Setup
#  Run via: autounattend.xml registry Run key (fires on first desktop login)
# ============================================================

# Self-elevate to Administrator if not already running elevated
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs
    exit
}

# Force TLS 1.2 - fresh Windows defaults to TLS 1.0 which
# breaks PowerShell Gallery, NuGet, and winget source updates
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Make the terminal window large and clearly visible
$Host.UI.RawUI.WindowTitle = "Windows 11 Client Setup - DO NOT CLOSE"
try {
    $size = $Host.UI.RawUI.BufferSize
    $size.Width  = 120
    $size.Height = 3000
    $Host.UI.RawUI.BufferSize = $size
    $win = $Host.UI.RawUI.WindowSize
    $win.Width  = 120
    $win.Height = 40
    $Host.UI.RawUI.WindowSize = $win
} catch {}

# On any unhandled error: print it clearly and wait for keypress
# so the window never just closes on you
$ErrorActionPreference = "Stop"
trap {
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Red
    Write-Host "  |            SCRIPT ERROR                  |" -ForegroundColor Red
    Write-Host "  +==========================================+" -ForegroundColor Red
    Write-Host ""
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "  Take a photo of this screen and send it for support." -ForegroundColor White
    Write-Host ""
    Write-Host "  Press any key to close..." -ForegroundColor DarkGray
    try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch {}
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- PATHS & STATE ---
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

function Is-Done {
    param([string]$Step)
    if (!(Test-Path $StateFile)) { return $false }
    return ($null -ne (Select-String -Path $StateFile -Pattern "^$Step$" -Quiet))
}

function Mark-Done {
    param([string]$Step)
    Add-Content -Path $StateFile -Value $Step
    Write-Log "Step completed: $Step"
}

function Show-Status {
    Clear-Host
    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |    WINDOWS 11 CLIENT SETUP UTILITY       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
    $steps = @("PC Name","Internet Connection","Time Sync","Windows Updates","GPU Drivers")
    foreach ($s in $steps) {
        if (Is-Done $s) {
            Write-Host "  [DONE] $s" -ForegroundColor Green
        } else {
            Write-Host "  [    ] $s" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
    Write-Host "  ------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

# ---- INIT ----

if (!(Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
if (!(Test-Path $StateFile)) { New-Item -ItemType File -Path $StateFile -Force | Out-Null }
Write-Log "Script launched. PS version: $($PSVersionTable.PSVersion)"

# Scheduled task persists across reboots - no registry write needed
Write-Log "Script launched from: $($MyInvocation.MyCommand.Path)"

# ============================================================
# STEP 0 - PC NAME & PASSWORD
# Shows a popup once. PC name is required. Password is optional.
# If password is left blank, the PC has no password and auto-logs in.
# If a password is set, AutoLogon is updated so reboots during
# Windows Updates still log in automatically, then disabled at the end.
# ============================================================
if (!(Is-Done "PC Name")) {

    $form                 = New-Object System.Windows.Forms.Form
    $form.Text            = "Client PC Setup"
    $form.Size            = New-Object System.Drawing.Size(440, 260)
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox     = $false
    $form.MinimizeBox     = $false
    $form.TopMost         = $true
    $form.BackColor       = [System.Drawing.Color]::FromArgb(24, 24, 24)

    $title           = New-Object System.Windows.Forms.Label
    $title.Text      = "Windows 11 Client Setup"
    $title.Font      = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::White
    $title.Location  = New-Object System.Drawing.Point(20, 16)
    $title.Size      = New-Object System.Drawing.Size(400, 30)
    $form.Controls.Add($title)

    $sub             = New-Object System.Windows.Forms.Label
    $sub.Text        = "Enter a name for this PC, then setup runs automatically."
    $sub.Font        = New-Object System.Drawing.Font("Segoe UI", 9)
    $sub.ForeColor   = [System.Drawing.Color]::DarkGray
    $sub.Location    = New-Object System.Drawing.Point(20, 50)
    $sub.Size        = New-Object System.Drawing.Size(400, 20)
    $form.Controls.Add($sub)

    $lblName           = New-Object System.Windows.Forms.Label
    $lblName.Text      = "PC Name:"
    $lblName.Font      = New-Object System.Drawing.Font("Segoe UI", 10)
    $lblName.ForeColor = [System.Drawing.Color]::LightGray
    $lblName.Location  = New-Object System.Drawing.Point(20, 82)
    $lblName.Size      = New-Object System.Drawing.Size(400, 22)
    $form.Controls.Add($lblName)

    $tbName             = New-Object System.Windows.Forms.TextBox
    $tbName.Font        = New-Object System.Drawing.Font("Segoe UI", 12)
    $tbName.Location    = New-Object System.Drawing.Point(20, 106)
    $tbName.Size        = New-Object System.Drawing.Size(390, 30)
    $tbName.MaxLength   = 15
    $tbName.BackColor   = [System.Drawing.Color]::FromArgb(48, 48, 48)
    $tbName.ForeColor   = [System.Drawing.Color]::White
    $tbName.BorderStyle = "FixedSingle"
    $form.Controls.Add($tbName)

    $noteN           = New-Object System.Windows.Forms.Label
    $noteN.Text      = "Max 15 chars. Letters, numbers, hyphens only. Cannot start or end with hyphen."
    $noteN.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $noteN.ForeColor = [System.Drawing.Color]::DarkGray
    $noteN.Location  = New-Object System.Drawing.Point(20, 140)
    $noteN.Size      = New-Object System.Drawing.Size(390, 20)
    $form.Controls.Add($noteN)

    $btn             = New-Object System.Windows.Forms.Button
    $btn.Text        = "Confirm & Start Setup  >"
    $btn.Font        = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $btn.Location    = New-Object System.Drawing.Point(20, 172)
    $btn.Size        = New-Object System.Drawing.Size(390, 44)
    $btn.BackColor   = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $btn.ForeColor   = [System.Drawing.Color]::White
    $btn.FlatStyle   = "Flat"
    $btn.FlatAppearance.BorderSize = 0
    $form.Controls.Add($btn)
    $form.AcceptButton = $btn

    $btn.Add_Click({
        $n = $tbName.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($n)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter a PC name.", "Required",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null; return
        }
        if ($n.Length -gt 15) {
            [System.Windows.Forms.MessageBox]::Show("Name must be 15 characters or fewer.", "Too Long",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null; return
        }
        if ($n -match '^-|-$') {
            [System.Windows.Forms.MessageBox]::Show("Name cannot start or end with a hyphen.", "Invalid",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null; return
        }
        if ($n -notmatch '^[a-zA-Z0-9\-]+$') {
            [System.Windows.Forms.MessageBox]::Show("Only letters, numbers and hyphens are allowed.", "Invalid",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null; return
        }
        $form.Tag          = $n
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })

    $form.Add_FormClosing({
        param($s, $e)
        if ($form.DialogResult -ne [System.Windows.Forms.DialogResult]::OK) { $e.Cancel = $true }
    })

    [void]$form.ShowDialog()
    $chosenName = $form.Tag

    Write-Log "PC name chosen: $chosenName"
    Rename-Computer -NewName $chosenName -Force -ErrorAction Stop
    Write-Log "Rename-Computer executed. Will apply after reboot."
    Set-Content -Path "$StateDir\pcname.txt" -Value $chosenName -Encoding UTF8
    Mark-Done "PC Name"
}

# ============================================================
# STEP 1 - INTERNET
# Wait until internet is available before doing anything else.
# ============================================================
Show-Status
Write-Host "  Checking internet connection..." -ForegroundColor Yellow

$connected = $false
while (!$connected) {
    try {
        $connected = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue
    } catch { $connected = $false }

    if (!$connected) {
        Clear-Host
        Write-Host ""
        Write-Host "  +==========================================+" -ForegroundColor Red
        Write-Host "  |        NO INTERNET CONNECTION            |" -ForegroundColor Red
        Write-Host "  +==========================================+" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Connect to Wi-Fi or plug in Ethernet cable." -ForegroundColor White
        Write-Host "  Retrying in 10 seconds..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 10
    }
}

if (!(Is-Done "Internet Connection")) { Mark-Done "Internet Connection" }
Show-Status

# ============================================================
# STEP 2 - TIME SYNC
# ============================================================
if (!(Is-Done "Time Sync")) {
    Write-Host "  Syncing system clock..." -ForegroundColor Yellow
    try {
        Write-Host "  Starting Windows Time service..." -ForegroundColor DarkGray
        Start-Service w32tm -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        Write-Host "  Contacting time server..." -ForegroundColor DarkGray
        $syncOut = w32tm /resync /force 2>&1
        Write-Host "  $syncOut" -ForegroundColor DarkGray
        Write-Log "Time sync: $syncOut"
    } catch {
        Write-Log "Time sync warning: $_" "WARN"
        Write-Host "  [WARN] Time sync issue: $_" -ForegroundColor DarkYellow
    }
    Mark-Done "Time Sync"
    Show-Status
}

# ============================================================
# STEP 3 - WINDOWS UPDATES
# Loops until zero updates remain - Windows staggers updates
# across multiple cycles on a fresh install.
# ============================================================
if (!(Is-Done "Windows Updates")) {
    Write-Host "  Preparing Windows Update agent..." -ForegroundColor Yellow

    $updateModuleReady = $false

    if (Get-Module -ListAvailable -Name PSWindowsUpdate -ErrorAction SilentlyContinue) {
        $updateModuleReady = $true
        Write-Log "PSWindowsUpdate already installed."
    } else {
        Write-Host "  Installing update module (needs internet)..." -ForegroundColor DarkGray
        try {
            $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
            if (!$nuget -or $nuget.Version -lt [Version]"2.8.5.201") {
                Write-Host "  Installing NuGet provider..." -ForegroundColor DarkGray
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 `
                    -Force -Confirm:$false -ErrorAction Stop | Out-Null
                Write-Host "  NuGet provider installed." -ForegroundColor DarkGray
                Write-Log "NuGet provider installed."
            }

            Write-Host "  Trusting PowerShell Gallery..." -ForegroundColor DarkGray
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue

            Write-Host "  Downloading PSWindowsUpdate module..." -ForegroundColor DarkGray
            Install-Module PSWindowsUpdate -Force -Confirm:$false `
                -SkipPublisherCheck -ErrorAction Stop | Out-Null
            Write-Host "  Update module ready." -ForegroundColor DarkGray
            Write-Log "PSWindowsUpdate installed successfully."
            $updateModuleReady = $true

        } catch {
            Write-Log "PSWindowsUpdate install failed: $_" "ERROR"
            Write-Host "  [WARN] Could not install update module - skipping Windows Updates." -ForegroundColor DarkYellow
            Write-Host "         Run Windows Update manually via Settings when done." -ForegroundColor DarkGray
        }
    }

    if ($updateModuleReady) {
        try {
            Import-Module PSWindowsUpdate -ErrorAction Stop

            $round = 1
            while ($true) {
                Write-Host "  Scanning for updates - round $round (may take a moment)..." -ForegroundColor Yellow
                Write-Log "Update scan round $round started."

                $updates = Get-WindowsUpdate -AcceptAll -MicrosoftUpdate -ErrorAction Stop

                if ($updates -and $updates.Count -gt 0) {
                    Write-Host "  Found $($updates.Count) update(s). Installing now..." -ForegroundColor Cyan
                    Write-Log "Round $round - installing $($updates.Count) updates."

                    Install-WindowsUpdate -AcceptAll -MicrosoftUpdate -Confirm:$false

                    $rebootNeeded = (Get-WURebootStatus -Silent)
                    if ($rebootNeeded) {
                        Write-Host "  Reboot required - restarting now. Setup resumes automatically..." -ForegroundColor Cyan
                        Write-Log "Round $round complete - rebooting."
                        shutdown.exe /r /t 10 /c "Windows Updates installed. Resuming setup after restart."
                        exit 0
                    }

                    Write-Host "  Round $round done. Checking for more..." -ForegroundColor DarkGray
                    Write-Log "Round $round complete - no reboot needed, continuing loop."
                    $round++

                } else {
                    Write-Host "  All updates installed. Fully up to date after $round scan(s)." -ForegroundColor Green
                    Write-Log "Update loop finished after $round round(s)."
                    break
                }
            }

        } catch {
            Write-Log "Windows Update error: $_" "WARN"
            Write-Host "  [WARN] Update check hit an issue - continuing anyway." -ForegroundColor DarkYellow
        }
    }

    Mark-Done "Windows Updates"
    Show-Status
}

# ============================================================
# STEP 4 - GPU DRIVERS
# ============================================================
if (!(Is-Done "GPU Drivers")) {
    Write-Host "  Detecting graphics hardware..." -ForegroundColor Yellow

    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
    if (!$wingetPath) {
        Write-Host "  [WARN] winget not available yet." -ForegroundColor DarkYellow
        Write-Host "         GPU drivers will install on next run after Windows Updates." -ForegroundColor DarkGray
        Write-Log "winget missing - GPU step deferred." "WARN"
    } else {
        $gpus = Get-CimInstance Win32_VideoController |
                Where-Object { $_.Caption -notmatch "Microsoft|Remote|Virtual|Basic" }

        if (!$gpus) {
            Write-Host "  [SKIP] No discrete GPU detected." -ForegroundColor DarkYellow
            Write-Log "No discrete GPU found - skipping driver install." "WARN"
            Mark-Done "GPU Drivers"
        } else {
            Write-Host "  Refreshing winget sources..." -ForegroundColor DarkGray
            winget source update --name winget 2>&1 | Out-Null
            Write-Host "  Sources updated." -ForegroundColor DarkGray

            foreach ($gpu in $gpus) {
                $name = $gpu.Caption
                Write-Host "  Detected: $name" -ForegroundColor White
                Write-Log "GPU: $name"

                if ($name -match "NVIDIA") {
                    Write-Host "  >> Installing NVIDIA GeForce Experience..." -ForegroundColor Green
                    Write-Host "     (This may take a few minutes...)" -ForegroundColor DarkGray
                    winget install --id Nvidia.GeForceExperience --silent `
                        --accept-package-agreements --accept-source-agreements
                    Write-Host "  >> NVIDIA install finished (exit code: $LASTEXITCODE)" -ForegroundColor DarkGray
                    Write-Log "NVIDIA install finished (exit: $LASTEXITCODE)."

                } elseif ($name -match "AMD|Radeon") {
                    Write-Host "  >> Installing AMD Radeon Software..." -ForegroundColor Red
                    Write-Host "     (This may take a few minutes...)" -ForegroundColor DarkGray
                    winget install --id AMD.RadeonSoftware --silent `
                        --accept-package-agreements --accept-source-agreements
                    Write-Host "  >> AMD install finished (exit code: $LASTEXITCODE)" -ForegroundColor DarkGray
                    Write-Log "AMD install finished (exit: $LASTEXITCODE)."

                } elseif ($name -match "Intel" -and $name -match "Arc|Iris|UHD") {
                    Write-Host "  >> Installing Intel Graphics Driver..." -ForegroundColor Blue
                    Write-Host "     (This may take a few minutes...)" -ForegroundColor DarkGray
                    winget install --id Intel.ArcGraphicsDriver --silent `
                        --accept-package-agreements --accept-source-agreements
                    Write-Host "  >> Intel install finished (exit code: $LASTEXITCODE)" -ForegroundColor DarkGray
                    Write-Log "Intel install finished (exit: $LASTEXITCODE)."

                } else {
                    Write-Host "  [SKIP] GPU not recognised - no driver action taken." -ForegroundColor DarkYellow
                    Write-Log "Unrecognised GPU skipped: $name" "WARN"
                }
            }

            Mark-Done "GPU Drivers"
        }
    }

    Show-Status
}

# ============================================================
# STEP 5 - FINAL VERIFICATION
# ============================================================
Clear-Host
Write-Host ""
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host "  |         FINAL VERIFICATION               |" -ForegroundColor Cyan
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Running checks..." -ForegroundColor DarkGray
Write-Host ""

$allPassed = $true
$failNotes  = @()

function Write-Check {
    param([string]$Label, [bool]$Passed, [string]$Detail = "", [bool]$WarnOnly = $false)
    if ($Passed) {
        $line = "  [PASS] $Label"
        if ($Detail) { $line += " - $Detail" }
        Write-Host $line -ForegroundColor Green
    } elseif ($WarnOnly) {
        $line = "  [WARN] $Label"
        if ($Detail) { $line += " - $Detail" }
        Write-Host $line -ForegroundColor DarkYellow
    } else {
        $line = "  [FAIL] $Label"
        if ($Detail) { $line += " - $Detail" }
        Write-Host $line -ForegroundColor Red
    }
}

# CHECK 1: PC Name
try {
    $pcNameFile = "$StateDir\pcname.txt"
    if (Test-Path $pcNameFile) {
        $expectedName = (Get-Content $pcNameFile -Raw).Trim()
        $actualName   = $env:COMPUTERNAME
        if ($actualName -eq $expectedName) {
            Write-Check "PC Name" $true "set to '$actualName'"
        } else {
            Write-Check "PC Name" $true "will be '$expectedName' after reboot (currently '$actualName')"
        }
    } else {
        Write-Check "PC Name" $true "$env:COMPUTERNAME"
    }
} catch {
    Write-Check "PC Name" $false "could not verify" -WarnOnly $true
}

# CHECK 2: Windows Activation
try {
    $activated = Get-CimInstance SoftwareLicensingProduct -Filter "Name like 'Windows%'" |
                 Where-Object { $_.PartialProductKey -and $_.LicenseStatus -eq 1 }
    if ($activated) {
        Write-Check "Windows Activated" $true
    } else {
        Write-Check "Windows Activated" $false "not yet activated - client must enter their product key" -WarnOnly $true
        $failNotes += "Windows not activated - client needs to enter their retail product key."
    }
} catch {
    Write-Check "Windows Activated" $false "could not check status" -WarnOnly $true
}

# CHECK 3: Time Synced
try {
    $w32Status = w32tm /query /status 2>&1
    $sourceOk  = $w32Status | Select-String "Source"
    $lastSync  = $w32Status | Select-String "Last Successful Sync Time"
    if ($sourceOk -and $lastSync) {
        Write-Check "Time Synced" $true "last sync: $($lastSync.ToString().Split(':',2)[1].Trim())"
    } else {
        Write-Check "Time Synced" $false "sync status unclear" -WarnOnly $true
    }
} catch {
    Write-Check "Time Synced" $false "could not verify" -WarnOnly $true
}

# CHECK 4: Windows Up To Date
try {
    if (Is-Done "Windows Updates") {
        Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue
        $remaining = Get-WindowsUpdate -AcceptAll -MicrosoftUpdate -ErrorAction SilentlyContinue
        if (!$remaining -or $remaining.Count -eq 0) {
            Write-Check "Windows Up To Date" $true "no updates pending"
        } else {
            Write-Check "Windows Up To Date" $false "$($remaining.Count) update(s) still pending"
            $allPassed = $false
            $failNotes += "$($remaining.Count) Windows update(s) still pending."
        }
    } else {
        Write-Check "Windows Up To Date" $false "update step did not complete"
        $allPassed = $false
        $failNotes += "Windows Updates step did not complete."
    }
} catch {
    Write-Check "Windows Up To Date" $false "could not verify" -WarnOnly $true
}

# CHECK 5: GPU Driver
try {
    $gpus = Get-CimInstance Win32_VideoController |
            Where-Object { $_.Caption -notmatch "Microsoft|Remote|Virtual|Basic" }
    if ($gpus) {
        foreach ($gpu in $gpus) {
            if ($gpu.ConfigManagerErrorCode -eq 0) {
                Write-Check "GPU Driver" $true "$($gpu.Caption) - working correctly"
            } else {
                Write-Check "GPU Driver" $false "$($gpu.Caption) - Device Manager error code $($gpu.ConfigManagerErrorCode)"
                $allPassed = $false
                $failNotes += "GPU '$($gpu.Caption)' has a driver error (code $($gpu.ConfigManagerErrorCode))."
            }
        }
    } else {
        Write-Check "GPU Driver" $false "no discrete GPU detected" -WarnOnly $true
        $failNotes += "No discrete GPU detected - may need manual driver install."
    }
} catch {
    Write-Check "GPU Driver" $false "could not check GPU status" -WarnOnly $true
}

# RESULT
Write-Host ""
Write-Host "  ==========================================" -ForegroundColor DarkGray
Write-Host ""

if ($allPassed) {
    Write-Host "  ALL CHECKS PASSED - PC IS READY FOR CLIENT." -ForegroundColor Green
} else {
    Write-Host "  SETUP COMPLETE WITH WARNINGS:" -ForegroundColor DarkYellow
    foreach ($note in $failNotes) {
        Write-Host "    > $note" -ForegroundColor DarkYellow
    }
}

Write-Log "Verification complete. AllPassed=$allPassed | Notes: $($failNotes -join ' | ')"
Write-Host ""

# ============================================================
# CLEANUP - Remove all traces and disable AutoLogon
# ============================================================
Write-Host ""
Write-Host "  ==========================================" -ForegroundColor DarkGray
Write-Host "  Removing all traces of setup from this PC..." -ForegroundColor DarkGray
Write-Host ""

# 1. Disable AutoLogon - PC should require password login from now on
Write-Host "  Disabling automatic login..." -ForegroundColor DarkGray
try {
    Set-ItemProperty -Path $WinlogonPath -Name "AutoAdminLogon" -Value "0" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $WinlogonPath -Name "DefaultPassword" -ErrorAction SilentlyContinue
    Write-Log "AutoLogon disabled."
} catch {}

# 2. Scheduled task + any leftover registry run keys
Write-Host "  Removing scheduled task and registry run keys..." -ForegroundColor DarkGray
try { schtasks /delete /tn "ClientAutoSetup" /f 2>&1 | Out-Null } catch {}
Remove-ItemProperty -Path $RegPath -Name $RegName      -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $RegPath -Name "ClientSetup" -ErrorAction SilentlyContinue

# 3. PSWindowsUpdate module
Write-Host "  Removing PSWindowsUpdate module..." -ForegroundColor DarkGray
try {
    Remove-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
    Uninstall-Module PSWindowsUpdate -AllVersions -Force -ErrorAction SilentlyContinue
} catch {}

# 4. NuGet provider cache
Write-Host "  Removing NuGet provider cache..." -ForegroundColor DarkGray
$nugetPath = "$env:LOCALAPPDATA\PackageManagement\ProviderAssemblies\nuget"
Remove-Item -Path $nugetPath -Recurse -Force -ErrorAction SilentlyContinue

# 5. PowerShell module cache
Write-Host "  Removing module cache..." -ForegroundColor DarkGray
$modulePaths = @(
    "$env:ProgramFiles\WindowsPowerShell\Modules\PSWindowsUpdate",
    "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules\PSWindowsUpdate"
)
foreach ($mp in $modulePaths) {
    Remove-Item -Path $mp -Recurse -Force -ErrorAction SilentlyContinue
}

# 6. PowerShell history
Write-Host "  Clearing PowerShell history..." -ForegroundColor DarkGray
$historyPath = (Get-PSReadlineOption -ErrorAction SilentlyContinue).HistorySavePath
if ($historyPath -and (Test-Path $historyPath)) {
    Clear-Content -Path $historyPath -ErrorAction SilentlyContinue
}

# 7. Windows Event Log
Write-Host "  Clearing setup entries from event log..." -ForegroundColor DarkGray
try { wevtutil cl Application 2>&1 | Out-Null } catch {}

# 8. Windows Update download cache
Write-Host "  Clearing Windows Update download cache..." -ForegroundColor DarkGray
try {
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service wuauserv -ErrorAction SilentlyContinue
} catch {}

# 9. Temp files
Write-Host "  Clearing temp files..." -ForegroundColor DarkGray
Remove-Item "$env:TEMP\*"            -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# 10. State directory - must be last since we are still writing to the log
Write-Host "  Removing setup state folder..." -ForegroundColor DarkGray
Start-Sleep -Seconds 1
Remove-Item -Path $StateDir -Recurse -Force -ErrorAction SilentlyContinue

# 11. Prefetch entries
$prefetchFiles = Get-ChildItem "$env:SystemRoot\Prefetch" -Filter "*POWERSHELL*" -ErrorAction SilentlyContinue
foreach ($pf in $prefetchFiles) {
    Remove-Item $pf.FullName -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "  All traces removed. PC is clean." -ForegroundColor Green
Write-Host ""
Write-Host "  Press any key to close..." -ForegroundColor White
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
