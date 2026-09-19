@echo off
cd /d "%~dp0"
if not exist "%~dp0runtime\AutoHotkey64.exe" (
  echo Missing runtime\AutoHotkey64.exe
  pause
  exit /b 1
)
start "" "%~dp0runtime\AutoHotkey64.exe" "%~dp0reconnect.ahk"
