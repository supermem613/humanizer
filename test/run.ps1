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
Assert-ParameterDefault -FunctionName 'To-HumanizerView' -ParameterName 'View' -Expected 'Raw'

$raw = $json | Format-HumanizerJson -View Raw
Assert-Equal -Actual ($raw -join "`n") -Expected $json -Name 'Format-HumanizerJson raw view preserves output'

$pipelineRaw = $json | To-HumanizerView Raw
Assert-Equal -Actual ($pipelineRaw -join "`n") -Expected $json -Name 'To-HumanizerView raw view preserves pipeline JSON'

$pipelineDefault = $json | To-HumanizerView
Assert-Equal -Actual ($pipelineDefault -join "`n") -Expected $json -Name 'To-HumanizerView default view preserves raw pipeline JSON'

$pipelineTree = $json | To-HumanizerView -View Tree | ForEach-Object { script:Remove-HumanizerStyle $_ }
foreach ($expected in @('name: demo', 'count: 2')) {
    if (-not (($pipelineTree -join "`n").Contains($expected))) {
        throw "To-HumanizerView tree view failed. Expected output to contain '$expected'."
    }
}

$autoJson = '{"ok":true,"data":[{"kind":"file","path":"README.md","rev":"head"},{"kind":"file","path":"humanizer.ps1","rev":"head"}],"meta":{"owner":"tools"}}'
$autoValue = ConvertFrom-Json -InputObject $autoJson -Depth 100 -NoEnumerate
$autoRows = script:ConvertTo-HumanizerAuto -Value $autoValue -ExpandDepth 2 -MaxWidth 120
$plainAuto = ($autoRows | ForEach-Object { script:Remove-HumanizerStyle $_ }) -join "`n"
foreach ($expected in @('ok: true', 'data:', '┌───┬──────┬───────────────┬──────┐', '│ # │ kind │ path          │ rev  │', '│ 0 │ file │ README.md     │ head │', '│ 1 │ file │ humanizer.ps1 │ head │', 'meta:', '└─ owner: tools')) {
    if (-not $plainAuto.Contains($expected)) {
        throw "Auto view failed. Expected hybrid output to contain '$expected'."
    }
}

$pipelineAuto = ($autoJson | To-HumanizerView Auto | ForEach-Object { script:Remove-HumanizerStyle $_ }) -join "`n"
foreach ($expected in @('data:', '│ # │ kind │ path          │ rev  │')) {
    if (-not $pipelineAuto.Contains($expected)) {
        throw "To-HumanizerView auto view failed. Expected output to contain '$expected'."
    }
}

foreach ($functionName in @('Format-HumanizerJson', 'To-HumanizerView', 'New-Humanizer', 'Set-HumanizerView')) {
    $command = Get-Command $functionName
    $viewParameter = $command.Parameters['View']
    $validateSet = @($viewParameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | Select-Object -First 1)
    if ($validateSet.ValidValues -contains 'Smart') {
        throw "$functionName failed. Smart should not be a public view."
    }
}

$multiLineRaw = @('{', '  "name": "demo"', '}') | To-HumanizerView Raw
Assert-Equal -Actual ($multiLineRaw -join "`n") -Expected "{`n  `"name`": `"demo`"`n}" -Name 'To-HumanizerView raw view preserves multiline pipeline JSON'

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

$typedJson = '[{"name":"api","ok":true,"count":2,"missing":null}]'
$typedRows = script:ConvertTo-HumanizerTable -Value (ConvertFrom-Json -InputObject $typedJson -Depth 100 -NoEnumerate) -MaxWidth 100
$typedTable = $typedRows -join "`n"
foreach ($style in @($script:HumanizerAnsiStyles.String, $script:HumanizerAnsiStyles.Boolean, $script:HumanizerAnsiStyles.Number, $script:HumanizerAnsiStyles.Null)) {
    if (-not $typedTable.Contains($style)) {
        throw "Table view failed. Expected ANSI style '$style'."
    }
}

foreach ($line in $typedRows) {
    $plainLine = script:Remove-HumanizerStyle $line
    if ($plainLine.Length -gt 100) {
        throw "Table view failed. ANSI styling affected visible width: $plainLine"
    }
}

$typedPlain = ($typedRows | ForEach-Object { script:Remove-HumanizerStyle $_ }) -join "`n"
if ($typedPlain.Contains('│ 1 │')) {
    throw 'Table view failed. Single-item arrays rendered an extra blank row.'
}

$sparseJson = '[{"name":"api","state":"Running"},{"name":"worker"}]'
$sparseRows = script:ConvertTo-HumanizerTable -Value (ConvertFrom-Json -InputObject $sparseJson -Depth 100 -NoEnumerate) -MaxWidth 100
$sparsePlain = ($sparseRows | ForEach-Object { script:Remove-HumanizerStyle $_ }) -join "`n"
if (-not $sparsePlain.Contains('·')) {
    throw 'Table view failed. Missing record fields did not render with an explicit marker.'
}
if ($sparsePlain.Contains('❎')) {
    throw 'Table view failed. Missing record fields used an emoji marker.'
}
if (-not (($sparseRows -join "`n").Contains($script:HumanizerAnsiStyles.Missing))) {
    throw 'Table view failed. Missing field marker was not styled.'
}

$nestedArrayJson = '{"name":"demo","groups":[{"name":"alpha","items":[{"id":1,"state":"open"},{"id":2}]},{"name":"beta","items":[{"id":3,"state":"done","owner":"me"}]}]}'
$nestedArray = ConvertFrom-Json -InputObject $nestedArrayJson -Depth 100 -NoEnumerate
$nestedTableRows = script:ConvertTo-HumanizerTable -Value $nestedArray -ExpandDepth 3 -MaxWidth 120
$nestedTablePlain = ($nestedTableRows | ForEach-Object { script:Remove-HumanizerStyle $_ }) -join "`n"
foreach ($expected in @('groups', 'items', '│ # │ id │ state │', '·')) {
    if (-not $nestedTablePlain.Contains($expected)) {
        throw "Table view failed. Expected nested sub-table output to contain '$expected'."
    }
}
foreach ($style in @($script:HumanizerAnsiStyles.Border, $script:HumanizerAnsiStyles.Header, $script:HumanizerAnsiStyles.Missing)) {
    if (-not (($nestedTableRows -join "`n").Contains($style))) {
        throw "Table view failed. Expected nested sub-table ANSI style '$style'."
    }
}

$mixedShapeJson = '{"ok":true,"command":"opened","data":[{"kind":"changelist","cl":"default","description":"<created by soda>","fileCount":14},{"kind":"file","cl":"default","path":"src/commands/reconcileShared.ts","rev":"head","action":"edit","type":"text"},{"kind":"file","cl":"default","path":"src/commands/resolve.ts","rev":"head","action":"edit","type":"text"},{"kind":"changelist","cl":"syncdoc","description":"","fileCount":0}]}'
$mixedShape = ConvertFrom-Json -InputObject $mixedShapeJson -Depth 100 -NoEnumerate
$mixedShapeRows = script:ConvertTo-HumanizerAuto -Value $mixedShape -ExpandDepth 3 -MaxWidth 120
$mixedShapePlain = ($mixedShapeRows | ForEach-Object { script:Remove-HumanizerStyle $_ }) -join "`n"
foreach ($expected in @('ok: true', 'command: opened', 'data:', '[0]:', 'kind: changelist', 'description: <created by soda>', '[1..2]:', 'kind │ cl', 'path', 'src/commands/reconcileShared.ts')) {
    if (-not $mixedShapePlain.Contains($expected)) {
        throw "Auto view failed. Expected mixed-shape array to segment dense runs and contain '$expected'."
    }
}
if ($mixedShapePlain.Contains('│ # │ kind       │ cl') -and $mixedShapePlain.Contains('description') -and $mixedShapePlain.Contains('fileCount') -and $mixedShapePlain.Contains('path')) {
    throw 'Auto view failed. Mixed-shape record array rendered as one sparse table.'
}
if ($mixedShapePlain.Contains('❎')) {
    throw 'Auto view failed. Mixed-shape output used emoji missing markers.'
}

$diffLikeJson = '{"ok":true,"command":"diff","data":[{"kind":"file","path":"src/app.ts","format":"unified","diff":"@@ -1,2 +1,2 @@\n-old line\n+new line\n context line"}]}'
$diffLike = ConvertFrom-Json -InputObject $diffLikeJson -Depth 100 -NoEnumerate
$diffLikeRows = script:ConvertTo-HumanizerAuto -Value $diffLike -ExpandDepth 3 -MaxWidth 100
$diffLikePlainRows = @($diffLikeRows | ForEach-Object { script:Remove-HumanizerStyle $_ })
$diffLine = @($diffLikePlainRows | Where-Object { $_.Contains('diff:') })
if ($diffLine.Count -ne 1) {
    throw "Auto view failed. Multiline diff should render as one tree line, got $($diffLine.Count)."
}
if (-not $diffLine[0].Contains('(4 lines)')) {
    throw 'Auto view failed. Multiline diff did not include a compact line-count summary.'
}
foreach ($unexpected in @('-old line', '+new line', 'context line')) {
    if (($diffLikePlainRows | Where-Object { $_ -eq $unexpected }).Count -gt 0) {
        throw "Auto view failed. Multiline diff leaked raw line '$unexpected'."
    }
}

$shallowTable = (script:ConvertTo-HumanizerTable -Value $array -ExpandDepth 0) -join "`n"
if (-not $shallowTable.Contains('"restarts":0')) {
    throw 'Table view failed. ExpandDepth 0 did not compact nested JSON.'
}

$treeJson = '{"name":"demo","count":2,"ok":true,"missing":null,"meta":{"owner":"tools","retries":3},"tags":["cli","json"]}'
$treeValue = ConvertFrom-Json -InputObject $treeJson -Depth 100 -NoEnumerate
$treeRows = script:ConvertTo-HumanizerTree -Value $treeValue -ExpandDepth 2 -MaxWidth 120
$plainTree = ($treeRows | ForEach-Object { script:Remove-HumanizerStyle $_ }) -join "`n"
foreach ($expected in @('name: demo', 'count: 2', 'ok: true', 'missing: null', 'meta:', '├─ owner: tools', '└─ retries: 3', 'tags:', '[0]: cli', '[1]: json')) {
    if (-not $plainTree.Contains($expected)) {
        throw "Tree view failed. Expected rendered tree to contain '$expected'."
    }
}

foreach ($style in @($script:HumanizerAnsiStyles.Key, $script:HumanizerAnsiStyles.String, $script:HumanizerAnsiStyles.Number, $script:HumanizerAnsiStyles.Boolean, $script:HumanizerAnsiStyles.Null, $script:HumanizerAnsiStyles.Border)) {
    if (-not (($treeRows -join "`n").Contains($style))) {
        throw "Tree view failed. Expected ANSI style '$style'."
    }
}

$collapsedTree = (script:ConvertTo-HumanizerTree -Value $treeValue -ExpandDepth 0 | ForEach-Object { script:Remove-HumanizerStyle $_ }) -join "`n"
if (-not ($collapsedTree.Contains('meta: {2 keys}') -and $collapsedTree.Contains('tags: [2 items]'))) {
    throw 'Tree view failed. ExpandDepth 0 did not collapse complex children.'
}

$mixedTreeValue = ConvertFrom-Json -InputObject '["alpha",{"name":"nested"}]' -Depth 100 -NoEnumerate
$mixedTree = (script:ConvertTo-HumanizerTree -Value $mixedTreeValue -ExpandDepth 2 | ForEach-Object { script:Remove-HumanizerStyle $_ }) -join "`n"
foreach ($expected in @('[0]: alpha', '[1]:', '└─ name: nested')) {
    if (-not $mixedTree.Contains($expected)) {
        throw "Tree view failed. Expected mixed array output to contain '$expected'."
    }
}

$wideTreeJson = '{"description":"abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789","nested":{"path":"C:\\very\\wide\\path\\that\\must\\truncate\\for\\the\\terminal"}}'
$wideTreeValue = ConvertFrom-Json -InputObject $wideTreeJson -Depth 100 -NoEnumerate
$narrowTreeRows = script:ConvertTo-HumanizerTree -Value $wideTreeValue -ExpandDepth 2 -MaxWidth 48
foreach ($line in $narrowTreeRows) {
    $plainLine = script:Remove-HumanizerStyle $line
    if ($plainLine.Length -gt 48) {
        throw "Tree view failed. Expected width-limited line, got $($plainLine.Length): $plainLine"
    }
}

if (-not ((($narrowTreeRows | ForEach-Object { script:Remove-HumanizerStyle $_ }) -join "`n").Contains('...'))) {
    throw 'Tree view failed. Wide tree did not truncate any value.'
}

$manyTreeItems = 1..500 | ForEach-Object {
    [pscustomobject]@{
        id = $_
        name = "item-$_"
        ok = ($_ % 2 -eq 0)
        meta = [pscustomobject]@{
            path = "C:\repos\demo\src\file-$_.ts"
            retries = $_ % 5
        }
    }
}
$treeElapsed = Measure-Command {
    $manyTreeRows = script:ConvertTo-HumanizerTree -Value $manyTreeItems -ExpandDepth 2 -MaxWidth 120
}
if (@($manyTreeRows).Count -ne 3500) {
    throw "Tree view failed. Expected 3500 rows in performance fixture, got $(@($manyTreeRows).Count)."
}
if ($treeElapsed.TotalMilliseconds -gt 2000) {
    throw "Tree view failed. Rendering 500 nested records took $([int]$treeElapsed.TotalMilliseconds)ms."
}

$sdAutoJson = '{"ok":true,"command":"opened","data":[{"kind":"changelist","cl":"default","description":"<created by soda>","fileCount":3},{"kind":"file","cl":"default","path":"README.md","rev":"head","action":"edit","type":"text"}]}'
$sdAutoValue = ConvertFrom-Json -InputObject $sdAutoJson -Depth 100 -NoEnumerate
$sdAutoRows = script:ConvertTo-HumanizerAuto -Value $sdAutoValue -ExpandDepth 2 -MaxWidth 120
$sdAutoPlain = ($sdAutoRows | ForEach-Object { script:Remove-HumanizerStyle $_ }) -join "`n"
foreach ($expected in @('ok: true', 'command: opened', 'data:', 'kind: changelist', 'fileCount: 3', 'path: README.md')) {
    if (-not $sdAutoPlain.Contains($expected)) {
        throw "Auto view failed. Expected sd-like tree output to contain '$expected'."
    }
}
if ($sdAutoPlain.Contains('Property')) {
    throw 'Auto view failed. Mixed-shape array rendered as a raw property table.'
}

$wideDenseJson = '[{"kind":"file","path":"src/very/very/very/long/path/that/exceeds/budget.ts","rev":"head"}]'
$wideDenseValue = ConvertFrom-Json -InputObject $wideDenseJson -Depth 100 -NoEnumerate
$narrowDenseRows = script:ConvertTo-HumanizerAuto -Value $wideDenseValue -ExpandDepth 2 -MaxWidth 50
foreach ($line in $narrowDenseRows) {
    $plainLine = script:Remove-HumanizerStyle $line
    if ($plainLine.Length -gt 50) {
        throw "Auto view failed. Expected width-limited line, got $($plainLine.Length): $plainLine"
    }
}
if (-not (($narrowDenseRows | ForEach-Object { script:Remove-HumanizerStyle $_ }) -join "`n").Contains('...')) {
    throw 'Auto view failed. Wide dense array did not truncate any cell.'
}

$promptJson = '{"ok":true,"command":"prompt","data":[{"schemaVersion":1,"kind":"p4","branch":"main","stream":"default","head":"f00ba4","upstream":"origin/main","ahead":177,"behind":0,"clean":true,"changelists":0,"defaultOpened":0,"opened":0,"added":0,"changed":0,"deleted":0,"conflicts":0,"shelves":0,"cache":"hit"}]}'
$promptValue = ConvertFrom-Json -InputObject $promptJson -Depth 100 -NoEnumerate
$promptRows = script:ConvertTo-HumanizerAuto -Value $promptValue -ExpandDepth 2 -MaxWidth 80
$promptPlain = ($promptRows | ForEach-Object { script:Remove-HumanizerStyle $_ }) -join "`n"
foreach ($expected in @('data:', '[0]:', 'schemaVersion: 1', 'cache: hit')) {
    if (-not $promptPlain.Contains($expected)) {
        throw "Auto view failed. Expected narrow prompt output to contain '$expected'."
    }
}
foreach ($line in $promptRows) {
    $plainLine = script:Remove-HumanizerStyle $line
    if ($plainLine.Length -gt 80) {
        throw "Auto view failed. Expected prompt line within width, got $($plainLine.Length): $plainLine"
    }
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

Set-HumanizerView -Name __humanizer_auto_test__ -View Raw -ExpandDepth 0 | Out-Null
$rawChanged = & __humanizer_auto_test__ -NoProfile -Command "'{`"ok`":true}'"
Assert-Equal -Actual ($rawChanged -join "`n") -Expected '{"ok":true}' -Name 'Set-HumanizerView changes wrapper view to Raw'

Set-HumanizerView -Name __humanizer_auto_test__ -View Auto -ExpandDepth 2 | Out-Null
$pipelineChanged = & __humanizer_auto_test__ -NoProfile -Command "'{`"ok`":true}'" | To-HumanizerView Raw
Assert-Equal -Actual ($pipelineChanged -join "`n") -Expected '{"ok":true}' -Name 'Wrapped command piped to To-HumanizerView Raw preserves raw JSON'

New-Humanizer __humanizer_raw_native_test__ (Get-Command pwsh).Source -View Raw
$rawNativeFile = Join-Path $repo '.humanizer-raw-native-output.tmp'
try {
    $nativeBytesScript = '$bytes = [System.Text.Encoding]::UTF8.GetBytes("plain"); [Console]::OpenStandardOutput().Write($bytes, 0, $bytes.Length)'
    & __humanizer_raw_native_test__ -NoProfile -Command $nativeBytesScript > $rawNativeFile
    $rawNativeBytes = [System.IO.File]::ReadAllBytes($rawNativeFile)
    $expectedNativeBytes = [System.Text.Encoding]::UTF8.GetBytes('plain')
    Assert-Equal -Actual ($rawNativeBytes -join ',') -Expected ($expectedNativeBytes -join ',') -Name 'New-Humanizer Raw view preserves native stdout bytes'
} finally {
    Remove-Item $rawNativeFile -ErrorAction SilentlyContinue
    Remove-Item Alias:\__humanizer_raw_native_test__ -Force -ErrorAction SilentlyContinue
    Remove-Item function:global:__humanizer_raw_native_test__ -ErrorAction SilentlyContinue
}

$oldConsoleOutputEncoding = [Console]::OutputEncoding
$utf8RawFile = Join-Path $repo '.humanizer-utf8-raw-output.tmp'
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(437)
    New-Humanizer __humanizer_utf8_test__ (Get-Command pwsh).Source -View Raw
    $utf8BytesScript = '$bytes = [System.Text.Encoding]::UTF8.GetBytes("┌─ ◉ │ └"); [Console]::OpenStandardOutput().Write($bytes, 0, $bytes.Length)'
    & __humanizer_utf8_test__ -NoProfile -Command $utf8BytesScript > $utf8RawFile
    $unicodeRawBytes = [System.IO.File]::ReadAllBytes($utf8RawFile)
    $expectedUnicodeRawBytes = [System.Text.Encoding]::UTF8.GetBytes('┌─ ◉ │ └')
    Assert-Equal -Actual ($unicodeRawBytes -join ',') -Expected ($expectedUnicodeRawBytes -join ',') -Name 'New-Humanizer Raw view preserves UTF-8 native stdout bytes'
} finally {
    [Console]::OutputEncoding = $oldConsoleOutputEncoding
    Remove-Item $utf8RawFile -ErrorAction SilentlyContinue
    Remove-Item Alias:\__humanizer_utf8_test__ -Force -ErrorAction SilentlyContinue
    Remove-Item function:global:__humanizer_utf8_test__ -ErrorAction SilentlyContinue
}

$viewConfig = Get-HumanizerView -Name __humanizer_auto_test__
Assert-Equal -Actual $viewConfig.View -Expected 'Auto' -Name 'Get-HumanizerView returns updated view'
Assert-Equal -Actual $viewConfig.ExpandDepth -Expected 2 -Name 'Get-HumanizerView returns updated ExpandDepth'

Remove-Item function:global:__humanizer_test__ -ErrorAction SilentlyContinue
Remove-Item function:global:__humanizer_auto_test__ -ErrorAction SilentlyContinue

Write-Host 'humanizer tests passed'
