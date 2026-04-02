# install_gpu_driver.ps1
# Detects your GPU, installs the driver if missing, or updates it if already installed

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "       GPU Driver Auto-Installer        " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if winget is available
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: winget is not installed." -ForegroundColor Red
    Write-Host "Install it from the Microsoft Store: App Installer" -ForegroundColor Yellow
    exit 1
}

# Detect GPU
$gpu = Get-WmiObject Win32_VideoController | Select-Object -First 1
$gpuName = $gpu.Name

Write-Host "Detected GPU: $gpuName" -ForegroundColor Green
Write-Host ""

# Set the correct winget package ID based on vendor
if ($gpuName -match "NVIDIA") {
    $vendor = "NVIDIA"
    $packageId = "NVIDIA.NVIDIADisplayDriver"
} elseif ($gpuName -match "AMD|Radeon") {
    $vendor = "AMD"
    $packageId = "AMD.AMDSoftwareAdrenalinEdition"
} elseif ($gpuName -match "Intel") {
    $vendor = "Intel"
    $packageId = "Intel.IntelDriverAndSupportAssistant"
} else {
    Write-Host "Could not identify GPU vendor from: $gpuName" -ForegroundColor Red
    Write-Host "Please install drivers manually from your GPU manufacturer's website." -ForegroundColor Yellow
    exit 1
}

# Check if driver is already installed
Write-Host "Checking if $vendor driver is already installed..." -ForegroundColor Yellow
$installed = winget list --id $packageId 2>$null | Select-String $packageId

if ($installed) {
    Write-Host "Driver is installed. Checking for updates..." -ForegroundColor Yellow
    Write-Host ""
    $upgradeOutput = winget upgrade --id $packageId --accept-package-agreements --accept-source-agreements

    if ($upgradeOutput -match "No applicable update") {
        Write-Host ""
        Write-Host "You already have the latest driver. No update needed." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "Driver updated successfully!" -ForegroundColor Green
        Write-Host "A reboot may be required." -ForegroundColor Yellow
    }
} else {
    Write-Host "Driver not found. Installing latest $vendor driver..." -ForegroundColor Yellow
    Write-Host ""
    winget install --id $packageId --accept-package-agreements --accept-source-agreements

    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "Driver installed successfully!" -ForegroundColor Green
        Write-Host "A reboot may be required." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "Installation may have encountered an issue. Check the output above." -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "                Done!                   " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
