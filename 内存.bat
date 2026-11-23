@echo off
chcp 65001 >nul
powershell -ExecutionPolicy Bypass -File "%~dp0FreeMemory.ps1"
pause
