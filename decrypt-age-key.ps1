# Decrypt the age key that unlocks mise's encrypted dotfiles. Bootstrap pre-packages hook (Windows).
$ErrorActionPreference = 'Stop'
$key = Join-Path $PSScriptRoot 'age.txt'
if ((Test-Path $key) -and (Get-Item $key).Length -gt 0) { exit 0 }

$tmp = "$key.tmp"
Remove-Item -Force -ErrorAction SilentlyContinue $tmp
Write-Host 'Enter the password for your age key'
mise x age@latest -- age -d -o $tmp (Join-Path $PSScriptRoot 'age.txt.age')
if ($LASTEXITCODE -ne 0) { Remove-Item -Force -ErrorAction SilentlyContinue $tmp; exit $LASTEXITCODE }
icacls $tmp /inheritance:r /grant:r "${env:USERNAME}:F" | Out-Null  # owner-only, like chmod 600
Move-Item -Force $tmp $key
