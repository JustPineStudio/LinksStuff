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

# Detect GPU - skip virtual adapters, prefer NVIDIA/AMD over Intel integrated
$allGpus = Get-CimInstance Win32_VideoController |
           Where-Object { $_.Name -notmatch "Virtual|Parsec|Remote|Microsoft|Basic|VirtualBox|VMware" }

$gpu = $allGpus | Where-Object { $_.Name -match "NVIDIA" } | Select-Object -First 1
if (-not $gpu) { $gpu = $allGpus | Where-Object { $_.Name -match "AMD|Radeon" } | Select-Object -First 1 }
if (-not $gpu) { $gpu = $allGpus | Where-Object { $_.Name -match "Intel" } | Select-Object -First 1 }

if (-not $gpu) {
    Write-Host "ERROR: No physical GPU detected." -ForegroundColor Red
    exit 1
}

$gpuName = $gpu.Name

Write-Host "Detected GPU: $gpuName" -ForegroundColor Green
Write-Host ""

# Set vendor and package ID
if ($gpuName -match "NVIDIA") {
    $vendor = "NVIDIA"
    $packageId = $null  # Not available on winget
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

# NVIDIA - download directly via NVIDIA API
if ($vendor -eq "NVIDIA") {

    # Map GPU name to NVIDIA product series ID (psid) and product ID (pfid)
    # OS 57 = Windows 10/11 64-bit, DCH driver
    $psid = $null; $pfid = $null
    switch -Regex ($gpuName) {
        "RTX\s*50"               { $psid = 144; $pfid = 1000 }
        "RTX\s*4090"             { $psid = 139; $pfid = 989  }
        "RTX\s*4080"             { $psid = 139; $pfid = 988  }
        "RTX\s*4070"             { $psid = 139; $pfid = 987  }
        "RTX\s*4060"             { $psid = 139; $pfid = 986  }
        "RTX\s*3090"             { $psid = 120; $pfid = 877  }
        "RTX\s*3080"             { $psid = 120; $pfid = 873  }
        "RTX\s*3070"             { $psid = 120; $pfid = 871  }
        "RTX\s*3060"             { $psid = 120; $pfid = 869  }
        "RTX\s*20[0-9][0-9]"    { $psid = 108; $pfid = 814  }
        "GTX\s*16[0-9][0-9]"    { $psid = 122; $pfid = 857  }
        "GTX\s*10[0-9][0-9]"    { $psid = 107; $pfid = 816  }
        default {
            Write-Host "  [WARN] GPU model '$gpuName' not in lookup table." -ForegroundColor DarkYellow
            Write-Host "  Download manually: https://www.nvidia.com/en-us/drivers/" -ForegroundColor Yellow
            exit 1
        }
    }

    Write-Host "  Querying NVIDIA API for latest driver..." -ForegroundColor DarkGray
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $apiUrl = "https://www.nvidia.com/Download/processFind.aspx?psid=$psid&pfid=$pfid&osid=57&lid=1&whql=1&lang=en-us&ctk=0&dtcid=1"
        $response = Invoke-WebRequest -Uri $apiUrl -UseBasicParsing -TimeoutSec 30

        # Extract driver version from response
        $version = $null
        if ($response.Content -match 'url.*?download.*?/(\d+\.\d+)/') {
            $version = $Matches[1]
        } elseif ($response.Content -match '(\d{3}\.\d{2})') {
            $version = $Matches[1]
        }

        if (-not $version) {
            Write-Host "  [ERROR] Could not parse driver version from NVIDIA API." -ForegroundColor Red
            Write-Host "  Download manually: https://www.nvidia.com/en-us/drivers/" -ForegroundColor Yellow
            exit 1
        }

        Write-Host "  Latest driver version: $version" -ForegroundColor Green

        # Convert Windows driver version (e.g. 32.0.15.9597) to NVIDIA version (595.97)
        # Formula: third segment last digit + first 2 of fourth segment + "." + last 2 of fourth segment
        $rawVer = $gpu.DriverVersion
        $currentNvidia = $null
        if ($rawVer -match '\.(\d+)\.(\d{4})$') {
            $hundreds = ($Matches[1] -replace '.*(\d)$','$1')
            $currentNvidia = "$hundreds$($Matches[2].Substring(0,2)).$($Matches[2].Substring(2,2))"
        }
        Write-Host "  Current driver version: $currentNvidia" -ForegroundColor DarkGray

        if ($currentNvidia -eq $version) {
            Write-Host ""
            Write-Host "  Already on the latest driver ($version). No update needed." -ForegroundColor Green
            exit 0
        }

        # Try known NVIDIA filename formats in order
        $dest = "$env:TEMP\nvidia_driver_$version.exe"
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
            "Referer"    = "https://www.nvidia.com/en-us/drivers/"
        }
        $candidates = @(
            "https://us.download.nvidia.com/Windows/$version/$version-desktop-win10-win11-64bit-international-dch-whql.exe",
            "https://us.download.nvidia.com/Windows/$version/$version-desktop-win10-win11-64bit-international-whql.exe",
            "https://us.download.nvidia.com/Windows/$version/$version-desktop-win10-64bit-international-dch-whql.exe"
        )

        $downloadUrl = $null
        foreach ($url in $candidates) {
            try {
                $check = Invoke-WebRequest -Uri $url -Method Head -Headers $headers -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                if ($check.StatusCode -eq 200) { $downloadUrl = $url; break }
            } catch {}
        }

        if (-not $downloadUrl) {
            Write-Host "  [ERROR] Could not find a valid download URL for driver $version." -ForegroundColor Red
            Write-Host "  Download manually: https://www.nvidia.com/en-us/drivers/" -ForegroundColor Yellow
            exit 1
        }

        Write-Host "  Downloading driver ($version) - this will take a few minutes..." -ForegroundColor Yellow
        Write-Host "  URL: $downloadUrl" -ForegroundColor DarkGray

        Invoke-WebRequest -Uri $downloadUrl -OutFile $dest -Headers $headers -UseBasicParsing

        Write-Host "  Download complete. Installing silently..." -ForegroundColor Yellow
        Write-Host "  (This may take several minutes)" -ForegroundColor DarkGray

        $proc = Start-Process -FilePath $dest -Wait -PassThru
        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 1) {
            Write-Host ""
            Write-Host "  Driver installed successfully! A reboot is required." -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "  Installer exited with code $($proc.ExitCode) - may have encountered an issue." -ForegroundColor DarkYellow
        }

        Remove-Item $dest -Force -ErrorAction SilentlyContinue

    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Download manually: https://www.nvidia.com/en-us/drivers/" -ForegroundColor Yellow
        exit 1
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "                Done!                   " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    exit 0
}

# AMD and Intel - use winget
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
