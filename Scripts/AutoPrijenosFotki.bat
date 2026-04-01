@echo off
setlocal enabledelayedexpansion

:: ================================================
:: CONFIG — only edit these two lines
:: ================================================
set "CAMERA_FOLDER=D:\Documents\Test"
set "TARGET_BASE=D:\Documents\Test2"

:: ================================================
:: RUN
:: ================================================
powershell -ExecutionPolicy Bypass -Command ^
    "$src = '%CAMERA_FOLDER%';" ^
    "$dest = '%TARGET_BASE%';" ^
    "$moved = 0; $skipped = 0; $dupes = 0; $noexif = 0;" ^
    "$validExt = @('.jpg','.jpeg','.png','.arw','.cr2','.nef','.raw','.dng','.tif','.tiff');" ^
    "" ^
    "Add-Type -AssemblyName System.Drawing;" ^
    "" ^
    "if (-not (Test-Path $src)) {" ^
    "    Write-Host '[ERROR] Source folder does not exist: ' $src -ForegroundColor Red;" ^
    "    exit 1" ^
    "};" ^
    "" ^
    "if (-not (Test-Path $dest)) {" ^
    "    New-Item -ItemType Directory -Path $dest -Force | Out-Null;" ^
    "    Write-Host '[INFO] Created destination folder: ' $dest -ForegroundColor Cyan;" ^
    "};" ^
    "" ^
    "$files = Get-ChildItem -Path $src -File -Recurse;" ^
    "if (-not $files) {" ^
    "    Write-Host '[WARNING] Source folder is empty. Nothing to move.' -ForegroundColor Yellow;" ^
    "    exit 0" ^
    "};" ^
    "" ^
    "foreach ($file in $files) {" ^
    "    if ($validExt -contains $file.Extension.ToLower()) {" ^
    "        $dateTaken = $null;" ^
    "        $source = 'EXIF';" ^
    "        try {" ^
    "            $img = [System.Drawing.Image]::FromFile($file.FullName);" ^
    "            $prop = $img.GetPropertyItem(36867);" ^
    "            $img.Dispose();" ^
    "            $dateStr = [System.Text.Encoding]::ASCII.GetString($prop.Value).Trim([char]0);" ^
    "            $dateTaken = [datetime]::ParseExact($dateStr, 'yyyy:MM:dd HH:mm:ss', $null);" ^
    "        } catch {" ^
    "            $source = 'FALLBACK-LastWriteTime';" ^
    "            $dateTaken = $file.LastWriteTime;" ^
    "            $noexif++;" ^
    "            Write-Host ('[NO EXIF] ' + $file.Name + ' - using LastWriteTime as fallback') -ForegroundColor Yellow;" ^
    "        };" ^
    "" ^
    "        $targetDir = Join-Path $dest ($dateTaken.ToString('yyyy\\MM\\dd'));" ^
    "        if (-not (Test-Path $targetDir)) {" ^
    "            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null" ^
    "        };" ^
    "" ^
    "        $targetPath = Join-Path $targetDir $file.Name;" ^
    "        if (Test-Path $targetPath) {" ^
    "            $dupes++;" ^
    "            $timestamp = $dateTaken.ToString('HHmmss');" ^
    "            $newName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name) + '_DUPE_' + $timestamp + $file.Extension;" ^
    "            $targetPath = Join-Path $targetDir $newName;" ^
    "            Write-Host ('[DUPE] ' + $file.Name + ' already exists - renaming to: ' + $newName) -ForegroundColor Yellow;" ^
    "        };" ^
    "" ^
    "        try {" ^
    "            Move-Item -Path $file.FullName -Destination $targetPath -Force -ErrorAction Stop;" ^
    "            Write-Host ('[MOVE] ' + $file.Name + ' -> ' + $dateTaken.ToString('yyyy/MM/dd') + '  [source: ' + $source + ']') -ForegroundColor Green;" ^
    "            $moved++;" ^
    "        } catch {" ^
    "            Write-Host ('[FAILED] Could not move: ' + $file.Name + ' - ' + $_.Exception.Message) -ForegroundColor Red;" ^
    "        };" ^
    "" ^
    "    } else {" ^
    "        Write-Host ('[SKIP] ' + $file.Name + ' - not a recognised image format') -ForegroundColor Gray;" ^
    "        $skipped++;" ^
    "    }" ^
    "};" ^
    "" ^
    "Write-Host '';" ^
    "Write-Host '============ SUMMARY ============' -ForegroundColor Cyan;" ^
    "Write-Host ('  Moved:          ' + $moved)   -ForegroundColor Green;" ^
    "Write-Host ('  Skipped:        ' + $skipped) -ForegroundColor Gray;" ^
    "Write-Host ('  Duplicates:     ' + $dupes)   -ForegroundColor Yellow;" ^
    "Write-Host ('  No EXIF (warn): ' + $noexif)  -ForegroundColor Yellow;" ^
    "Write-Host '=================================' -ForegroundColor Cyan"

echo.
echo Operation complete.
echo.
echo Press any key to exit...
pause >nul