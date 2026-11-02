#Requires -Version 5.1
# MyControlPanel headless poll — manual per-user install (TM-1, Lina).
# Registers the per-user Task Scheduler task from the XML template.
# No elevation requested; managed lifecycle (verify/status) is Zara's.
#
# Usage (non-elevated PowerShell):
#   .\install-windows.ps1 -InstallDir "$env:LOCALAPPDATA\MyControlPanel"
param(
  [string]$InstallDir = "$env:LOCALAPPDATA\MyControlPanel",
  [string]$TaskName = "\MyControlPanel\poll-headless"
)
$ErrorActionPreference = 'Stop'
$template = Join-Path $PSScriptRoot 'windows\mcp-poll-task.xml'
$filled = (Get-Content $template -Raw).Replace('INSTALL_DIR', $InstallDir)
$tmp = [IO.Path]::GetTempFileName()
Set-Content -Path $tmp -Value $filled -Encoding Unicode
schtasks /Create /TN $TaskName /XML $tmp /F
Remove-Item $tmp
Write-Host "Installed per-user task $TaskName (runs: $InstallDir\mycontrolpanel.exe --poll-headless)"
