# mcpoll headless poll — manual per-user install for Windows (Lisa, TM-1 follow-up).
# Registers a per-user scheduled task (logon + 15 min repeat). No elevation,
# no stored password. Run from an elevated prompt only if the policy requires
# it for task registration itself — the task runs at LeastPrivilege.
#
# Prerequisites: build the binary once and write a servers file, e.g.
#   dart compile exe bin/mcpoll.dart -o $env:LOCALAPPDATA\MyControlPanel\mcpoll.exe
#   Set-Content $env:LOCALAPPDATA\MyControlPanel\servers.json '[{"id":"web","name":"web","host":"192.168.1.10"}]'
#
# Usage:
#   .\install-windows.ps1 [-InstallDir $env:LOCALAPPDATA\MyControlPanel]
param(
  [string]$InstallDir = "$env:LOCALAPPDATA\MyControlPanel",
  # User scope for the LogonTrigger (see template): an unscoped logon
  # trigger makes schtasks /Create demand elevation.
  [string]$InstallUser = ("$env:USERDOMAIN\$env:USERNAME")
)
$ErrorActionPreference = 'Stop'
$xml = Get-Content "$PSScriptRoot\windows\mcp-poll-task.xml" -Raw
$xml = ($xml -replace 'INSTALL_DIR', $InstallDir) -replace 'INSTALL_USER', $InstallUser
$tmp = Join-Path $env:TEMP 'mcp-mcpoll-task.xml'
Set-Content -Path $tmp -Value $xml -Encoding Unicode
schtasks /Create /TN '\MyControlPanel\mcpoll' /XML $tmp /F
Remove-Item $tmp
Write-Host "Installed task \MyControlPanel\mcpoll (runs: $InstallDir\mcpoll.exe --consent --servers $InstallDir\servers.json)"
