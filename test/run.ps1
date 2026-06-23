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

function Assert-ParameterDefault {
    param(
        [Parameter(Mandatory)]
        [string]$FunctionName,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [Parameter(Mandatory)]
        [string]$Expected
    )

    $tokens = $null
    $errors = $null
    $scriptPath = Join-Path $repo 'humanizer.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw "Failed to parse $scriptPath."
    }

    $functions = $ast.FindAll({
        param($node)
        return ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $FunctionName)
    }, $true)

    if ($functions.Count -ne 1) {
        throw "Expected exactly one function named '$FunctionName'."
    }

    $parameters = $functions[0].Body.ParamBlock.Parameters | Where-Object {
        $_.Name.VariablePath.UserPath -eq $ParameterName
    }

    if ($parameters.Count -ne 1) {
        throw "Expected exactly one parameter named '$ParameterName' on '$FunctionName'."
    }

    Assert-Equal -Actual $parameters[0].DefaultValue.Extent.Text -Expected "'$Expected'" -Name "$FunctionName $ParameterName default"
}

$json = '{"name":"demo","count":2}'
$formatted = $json | Format-HumanizerJson
Assert-Equal -Actual ($formatted -join "`n") -Expected $json -Name 'Format-HumanizerJson preserves redirected output'

Assert-ParameterDefault -FunctionName 'Format-HumanizerJson' -ParameterName 'View' -Expected 'Auto'

$raw = $json | Format-HumanizerJson -View Raw
Assert-Equal -Actual ($raw -join "`n") -Expected $json -Name 'Format-HumanizerJson raw view preserves output'

$tableView = $json | Format-HumanizerJson -View Table
Assert-Equal -Actual ($tableView -join "`n") -Expected $json -Name 'Format-HumanizerJson table view preserves redirected output'

$arrayJson = '[{"name":"api","state":"Running","meta":{"restarts":0}},{"name":"worker","state":"Pending","meta":{"restarts":2}}]'
$array = ConvertFrom-Json -InputObject $arrayJson -Depth 100 -NoEnumerate
$table = (script:ConvertTo-HumanizerTable -Value $array -ExpandDepth 2) -join "`n"

foreach ($expected in @('name', 'state', 'worker', 'restarts')) {
    if (-not $table.Contains($expected)) {
        throw "Table view failed. Expected rendered table to contain '$expected'."
    }
}

if ($table.Contains('Length')) {
    throw 'Table view failed. Top-level JSON array rendered array metadata instead of rows.'
}

$shallowTable = (script:ConvertTo-HumanizerTable -Value $array -ExpandDepth 0) -join "`n"
if (-not $shallowTable.Contains('"restarts":0')) {
    throw 'Table view failed. ExpandDepth 0 did not compact nested JSON.'
}

$sdJson = '{"ok":true,"command":"opened","data":[{"kind":"changelist","cl":"default","description":"<created by soda>","fileCount":3},{"kind":"file","cl":"default","path":"README.md","rev":"head","action":"edit","type":"text"}]}'
$sdEnvelope = ConvertFrom-Json -InputObject $sdJson -Depth 100 -NoEnumerate
$autoTable = (script:ConvertTo-HumanizerAutoTable -Value $sdEnvelope -ExpandDepth 2) -join "`n"
foreach ($expected in @('ok: true', 'command: opened', 'kind', 'fileCount', 'README.md')) {
    if (-not $autoTable.Contains($expected)) {
        throw "Auto view failed. Expected unwrapped envelope output to contain '$expected'."
    }
}

if ($autoTable.Contains('Property') -or $autoTable.Contains('data')) {
    throw 'Auto view failed. Envelope data rendered as a nested property table.'
}

$wideSdJson = '{"ok":true,"command":"opened","data":[{"kind":"changelist","cl":"default","description":"<created by soda. use sd change to add description>","fileCount":16},{"kind":"file","cl":"default","path":"test/e2e/scenarios/config.test.ts","rev":"head","action":"edit","type":"text"},{"kind":"file","cl":"default","path":"src/config/resolver.ts","rev":"head","action":"edit","type":"text"}]}'
$wideSdEnvelope = ConvertFrom-Json -InputObject $wideSdJson -Depth 100 -NoEnumerate
$narrowAutoTable = script:ConvertTo-HumanizerAutoTable -Value $wideSdEnvelope -ExpandDepth 2 -MaxWidth 100
foreach ($line in $narrowAutoTable) {
    if ($line.Length -gt 100) {
        throw "Auto view failed. Expected width-limited line, got $($line.Length): $line"
    }
}

if (-not (($narrowAutoTable -join "`n").Contains('...'))) {
    throw 'Auto view failed. Wide table did not truncate any cell.'
}

New-Humanizer __humanizer_test__ (Get-Command pwsh).Source

Assert-ParameterDefault -FunctionName 'New-Humanizer' -ParameterName 'View' -Expected 'Auto'

& __humanizer_test__ -NoProfile -Command "'{`"ok`":true}'" | Out-Null
Assert-Equal -Actual $global:LASTEXITCODE -Expected 0 -Name 'New-Humanizer preserves success exit code'

& __humanizer_test__ -NoProfile -Command 'exit 7' | Out-Null
Assert-Equal -Actual $global:LASTEXITCODE -Expected 7 -Name 'New-Humanizer preserves failure exit code'
$global:LASTEXITCODE = 0

New-Humanizer __humanizer_auto_test__ (Get-Command pwsh).Source -View Auto -ExpandDepth 1
& __humanizer_auto_test__ -NoProfile -Command "'{`"ok`":true}'" | Out-Null
Assert-Equal -Actual $global:LASTEXITCODE -Expected 0 -Name 'New-Humanizer preserves Auto view configuration'

Remove-Item function:global:__humanizer_test__ -ErrorAction SilentlyContinue
Remove-Item function:global:__humanizer_auto_test__ -ErrorAction SilentlyContinue

Write-Host 'humanizer tests passed'
