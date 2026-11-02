#Requires -Version 5.1
# MyControlPanel headless poll — manual per-user uninstall (TM-1, Lina).
# Usage (non-elevated PowerShell):
#   .\uninstall-windows.ps1
param(
  [string]$TaskName = "\MyControlPanel\poll-headless"
)
$ErrorActionPreference = 'Stop'
schtasks /Delete /TN $TaskName /F
Write-Host "Removed task $TaskName"
