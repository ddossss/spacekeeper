param([ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$destination = Join-Path $root "codex-work/dist/Spacekeeper-$Runtime"
dotnet publish windows/Spacekeeper.Windows/Spacekeeper.Windows.csproj -c Release -r $Runtime --self-contained true -p:DebugType=None -p:DebugSymbols=false -o $destination
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed' }
Copy-Item windows/README.md (Join-Path $destination 'README.md')
$zip = Join-Path $root "codex-work/dist/Spacekeeper-$Runtime.zip"
Compress-Archive -Path "$destination/*" -DestinationPath $zip -Force
Get-FileHash $zip -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLower())  Spacekeeper-$Runtime.zip" } | Set-Content "$zip.sha256" -Encoding ascii
Write-Host "Built $zip"
