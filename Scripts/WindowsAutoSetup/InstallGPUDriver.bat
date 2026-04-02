@echo off
powershell -NoProfile -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File \"%~dp0install_gpu_driver.ps1\"' -Verb RunAs"
