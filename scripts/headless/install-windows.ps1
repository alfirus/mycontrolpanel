#Requires -Version 5.1
# MyControlPanel headless poll — manual per-user install (TM-1, Lina).
# Registers the per-user Task Scheduler task from the XML template.
# No elevation requested; managed lifecycle (verify/status) is Zara's.
#
# Usage (non-elevated PowerShell):
#   .\install-windows.ps1 -InstallDir "$env:LOCALAPPDATA\MyControlPanel"
param(
  [string]$InstallDir = "$env:LOCALAPPDATA\MyControlPanel",
  [string]$TaskName = "\MyControlPanel\poll-headless",
  # User scope for the LogonTrigger: an unscoped logon trigger fires at
  # any logon, so schtasks /Create demands elevation and a standard-user
  # install fails with "Access is denied". Scoping to the installing
  # user keeps the install per-user with no elevation.
  [string]$InstallUser = ("$env:USERDOMAIN\$env:USERNAME")
)
$ErrorActionPreference = 'Stop'
$template = Join-Path $PSScriptRoot 'windows\mcp-poll-task.xml'
$filled = (Get-Content $template -Raw).Replace('INSTALL_DIR', $InstallDir).Replace('INSTALL_USER', $InstallUser)
$tmp = [IO.Path]::GetTempFileName()
Set-Content -Path $tmp -Value $filled -Encoding Unicode
schtasks /Create /TN $TaskName /XML $tmp /F
Remove-Item $tmp
Write-Host "Installed per-user task $TaskName (runs: $InstallDir\mycontrolpanel.exe --poll-headless)"
