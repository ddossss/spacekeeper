param([string]$Executable)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
dotnet run --project windows/Spacekeeper.Tests -c Release -- (Join-Path $root 'codex-work/windows-tests')
if ($LASTEXITCODE -ne 0) { throw 'Core tests failed' }
if (!$Executable) { return }
$Executable = (Resolve-Path $Executable).Path
$state = Join-Path $root ("codex-work/windows-ui-" + [guid]::NewGuid().ToString('N'))
$process = Start-Process $Executable -ArgumentList '--self-test', '--state', "`"$state`"" -PassThru
if (!$process.WaitForExit(120000)) { $process.Kill(); throw 'UI test timed out' }
if ($process.ExitCode -ne 0) { Get-Content "$state/errors.log" -ErrorAction SilentlyContinue; throw 'UI test failed' }
Get-Content "$state/ui-result.txt"
Copy-Item $state (Join-Path $root 'codex-work/windows-ui-results') -Recurse -Force
# Exercise the real Task Scheduler with an empty cache allowlist. Never replace an existing user schedule.
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$task = "Spacekeeper Cache Cleanup-$sid"
if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) { throw 'Existing Spacekeeper schedule: integration test refused' }
$scheduleState = Join-Path $root ("codex-work/windows-schedule-" + [guid]::NewGuid().ToString('N'))
$process = Start-Process $Executable -ArgumentList '--schedule-test', '--state', "`"$scheduleState`"" -PassThru
if (!$process.WaitForExit(120000)) { $process.Kill(); throw 'Schedule test timed out' }
if ($process.ExitCode -ne 0) { Get-Content "$scheduleState/errors.log" -ErrorAction SilentlyContinue; throw 'Schedule registration test failed' }
Get-Content "$scheduleState/schedule-result.txt"
