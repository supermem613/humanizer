$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'humanizer.ps1')

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        [object]$Actual,

        [Parameter(Mandatory)]
        [object]$Expected,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($Actual -ne $Expected) {
        throw "$Name failed. Expected '$Expected', got '$Actual'."
    }
}

$json = '{"name":"demo","count":2}'
$formatted = $json | Format-HumanizerJson
Assert-Equal -Actual ($formatted -join "`n") -Expected $json -Name 'Format-HumanizerJson preserves redirected output'

New-Humanizer __humanizer_test__ (Get-Command pwsh).Source

& __humanizer_test__ -NoProfile -Command "'{`"ok`":true}'" | Out-Null
Assert-Equal -Actual $global:LASTEXITCODE -Expected 0 -Name 'New-Humanizer preserves success exit code'

& __humanizer_test__ -NoProfile -Command 'exit 7' | Out-Null
Assert-Equal -Actual $global:LASTEXITCODE -Expected 7 -Name 'New-Humanizer preserves failure exit code'
$global:LASTEXITCODE = 0

Remove-Item function:global:__humanizer_test__ -ErrorAction SilentlyContinue

Write-Host 'humanizer tests passed'
