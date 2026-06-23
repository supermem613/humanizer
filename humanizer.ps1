# humanizer.ps1
#
# Drop this file anywhere and dot-source it from your $PROFILE:
#
#   . "$HOME\tools\humanizer.ps1"
#
# Then wrap any CLI executable once:
#
#   New-Humanizer kubectl  "C:\tools\kubectl.exe"
#   New-Humanizer gh       "C:\tools\gh.exe"
#   New-Humanizer agentdoor "C:\path\to\agentdoor.exe"
#
# After that, just run the command normally:
#
#   kubectl get pods -o json      # colorized pretty JSON in the terminal
#   kubectl get pods -o json | jq # raw JSON for agents and pipes
#   kubectl get pods -o json > out.json  # raw JSON written to file

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Maximum size for the validation parse in Test-IsJson.
# Above this threshold the structural check (leading { or [) is sufficient.
# The actual parse cost is deferred to ConvertTo-ColorJson, which runs once.
$script:MaxValidationParseSize = 1MB
$script:HumanizerAnsiReset = "$([char]27)[0m"
$script:HumanizerAnsiStyles = @{
    Border = "$([char]27)[90m"
    Boolean = "$([char]27)[35m"
    Header = "$([char]27)[33m"
    Json = "$([char]27)[36m"
    Key = "$([char]27)[33m"
    Null = "$([char]27)[90m"
    Number = "$([char]27)[36m"
    String = "$([char]27)[32m"
}

function script:ConvertTo-HumanizerStyledText {
    param(
        [string]$Text,
        [string]$Kind
    )

    if ([string]::IsNullOrEmpty($Text) -or -not $script:HumanizerAnsiStyles.ContainsKey($Kind)) {
        return $Text
    }

    return $script:HumanizerAnsiStyles[$Kind] + $Text + $script:HumanizerAnsiReset
}

function script:Remove-HumanizerStyle {
    param([string]$Text)

    $escape = [regex]::Escape([string][char]27)
    $semicolon = [char]59
    return $Text -replace "$escape\[[0-9$semicolon]*m", ''
}

function script:New-HumanizerCell {
    param(
        [AllowNull()]
        [object]$Text,

        [string]$Kind = 'String'
    )

    return [pscustomobject]@{
        Text = [string]$Text
        Kind = $Kind
    }
}

function script:Get-HumanizerCellText {
    param([object]$Cell)

    if ($null -ne $Cell -and $Cell.PSObject.Properties['Text']) {
        return [string]$Cell.Text
    }

    return [string]$Cell
}

function script:Get-HumanizerCellKind {
    param([object]$Cell)

    if ($null -ne $Cell -and $Cell.PSObject.Properties['Kind']) {
        return [string]$Cell.Kind
    }

    return 'String'
}

function script:Get-HumanizerScalarKind {
    param([object]$Value)

    if ($null -eq $Value) {
        return 'Null'
    }

    if ($Value -is [bool]) {
        return 'Boolean'
    }

    if ($Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int] -or
        $Value -is [uint32] -or
        $Value -is [long] -or
        $Value -is [uint64] -or
        $Value -is [single] -or
        $Value -is [double] -or
        $Value -is [decimal]) {
        return 'Number'
    }

    return 'String'
}

function script:Get-HumanizerProperty {
    param(
        [object]$Value,
        [string]$Name
    )

    return $Value.PSObject.Properties | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
}

function script:ConvertTo-ColorJson {
    <#
    .SYNOPSIS
        Write pretty-printed, colorized JSON to the host (terminal only).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Json
    )

    # Re-indent with a 2-space indent for readability
    $obj    = $Json | ConvertFrom-Json -Depth 100 -ErrorAction Stop
    $pretty = $obj  | ConvertTo-Json   -Depth 100 -ErrorAction Stop

    $lines = $pretty -split "`n"

    # Regex matching JSON primitive values: booleans, null, and numbers.
    # Group 1: keyword (true|false|null) or full number literal.
    #   Groups 2-3: internal sub-captures for decimal and exponent parts.
    #               The regex engine requires them, but the code does not reference them directly.
    # Group 4: optional trailing whitespace before the terminator.
    # Group 5: JSON terminator, comma, closing bracket or brace, or end-of-string.
    $primitivePattern = '^(true|false|null|-?\d+(\.\d+)?([eE][+-]?\d+)?)(\s*)(,|\]|}|$)'

    foreach ($line in $lines) {
        # Key: DarkYellow
        # String value: Green
        # Number, bool, or null: Cyan
        # Structural characters: Gray

        if ($line -match '^(\s*)"([^"]+)"(\s*:\s*)(.*)$') {
            $indent = $Matches[1]
            $key    = $Matches[2]
            $colon  = $Matches[3]
            $value  = $Matches[4]

            Write-Host -NoNewline $indent
            Write-Host -NoNewline (script:ConvertTo-HumanizerStyledText -Text "`"$key`"" -Kind 'Key')
            Write-Host -NoNewline $colon

            if ($value -match '^"') {
                Write-Host (script:ConvertTo-HumanizerStyledText -Text $value -Kind 'String')
            } elseif ($value -match $primitivePattern) {
                $kind = 'Number'
                if ($value -match '^(true|false)') {
                    $kind = 'Boolean'
                } elseif ($value -match '^null') {
                    $kind = 'Null'
                }

                Write-Host (script:ConvertTo-HumanizerStyledText -Text $value -Kind $kind)
            } else {
                Write-Host (script:ConvertTo-HumanizerStyledText -Text $value -Kind 'Border')
            }
        } else {
            Write-Host (script:ConvertTo-HumanizerStyledText -Text $line -Kind 'Border')
        }
    }
}

function script:Test-HumanizerRecord {
    param([object]$Value)

    if ($null -eq $Value -or $Value -is [System.Array]) {
        return $false
    }

    return ($Value -is [pscustomobject])
}

function script:Test-HumanizerList {
    param([object]$Value)

    if ($null -eq $Value -or $Value -is [string]) {
        return $false
    }

    return ($Value -is [System.Collections.IEnumerable])
}

function script:ConvertTo-HumanizerScalar {
    param([object]$Value)

    if ($null -eq $Value) {
        return 'null'
    }

    if ($Value -is [bool]) {
        return $Value.ToString().ToLowerInvariant()
    }

    if ($Value -is [string]) {
        return $Value
    }

    return [string]$Value
}

function script:Test-HumanizerScalar {
    param([object]$Value)

    return (-not (script:Test-HumanizerRecord $Value) -and -not (script:Test-HumanizerList $Value))
}

function script:ConvertTo-HumanizerCell {
    param(
        [object]$Value,
        [int]$Depth,
        [int]$ExpandDepth
    )

    if ((script:Test-HumanizerRecord $Value) -or (script:Test-HumanizerList $Value)) {
        if ($Depth -ge $ExpandDepth) {
            return script:New-HumanizerCell -Text ($Value | ConvertTo-Json -Depth 100 -Compress) -Kind 'Json'
        }

        $nested = script:ConvertTo-HumanizerTable -Value $Value -Depth ($Depth + 1) -ExpandDepth $ExpandDepth
        $plainNested = $nested | ForEach-Object { script:Remove-HumanizerStyle $_ }
        return script:New-HumanizerCell -Text ($plainNested -join "`n") -Kind 'String'
    }

    return script:New-HumanizerCell -Text (script:ConvertTo-HumanizerScalar $Value) -Kind (script:Get-HumanizerScalarKind $Value)
}

function script:Test-HumanizerEnvelope {
    param([object]$Value)

    if (-not (script:Test-HumanizerRecord $Value)) {
        return $false
    }

    $dataProperty = script:Get-HumanizerProperty -Value $Value -Name 'data'
    if (-not $dataProperty) {
        return $false
    }

    if (script:Test-HumanizerScalar $dataProperty.Value) {
        return $false
    }

    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Name -eq 'data') {
            continue
        }

        if (-not (script:Test-HumanizerScalar $property.Value)) {
            return $false
        }
    }

    return $true
}

function script:ConvertTo-HumanizerAutoTable {
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [int]$ExpandDepth = 2,

        [int]$MaxWidth = 0
    )

    if (-not (script:Test-HumanizerEnvelope $Value)) {
        return script:ConvertTo-HumanizerTable -Value $Value -ExpandDepth $ExpandDepth -MaxWidth $MaxWidth
    }

    $lines = @()
    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Name -eq 'data') {
            continue
        }

        $name = script:ConvertTo-HumanizerStyledText -Text $property.Name -Kind 'Key'
        $styledValue = script:ConvertTo-HumanizerStyledText -Text (script:ConvertTo-HumanizerScalar $property.Value) -Kind (script:Get-HumanizerScalarKind $property.Value)
        $lines += "${name}: $styledValue"
    }

    if ($lines.Count -gt 0) {
        $lines += ''
    }

    $dataProperty = script:Get-HumanizerProperty -Value $Value -Name 'data'
    $lines += script:ConvertTo-HumanizerTable -Value $dataProperty.Value -ExpandDepth $ExpandDepth -MaxWidth $MaxWidth
    return $lines
}

function script:Get-HumanizerListItems {
    param([object]$Value)

    return @($Value)
}

function script:Get-HumanizerRecordNames {
    param([object]$Value)

    return @($Value.PSObject.Properties | ForEach-Object { $_.Name })
}

function script:Get-HumanizerValueWidth {
    param([string]$Value)

    $plain = script:Remove-HumanizerStyle $Value
    $lines = $plain -split "`n"
    $width = 0
    foreach ($line in $lines) {
        if ($line.Length -gt $width) {
            $width = $line.Length
        }
    }

    return $width
}

function script:Get-HumanizerTableWidth {
    param([int[]]$Widths)

    $sum = 0
    foreach ($width in $Widths) {
        $sum += $width
    }

    return $sum + (3 * $Widths.Count) + 1
}

function script:Limit-HumanizerTableWidths {
    param(
        [int[]]$Widths,
        [int[]]$MinimumWidths,
        [int]$MaxWidth
    )

    if ($MaxWidth -le 0) {
        return $Widths
    }

    $limited = @($Widths)
    while ((script:Get-HumanizerTableWidth $limited) -gt $MaxWidth) {
        $largestIndex = -1
        $largestWidth = -1
        $index = 0
        while ($index -lt $limited.Count) {
            if ($limited[$index] -gt $MinimumWidths[$index] -and $limited[$index] -gt $largestWidth) {
                $largestIndex = $index
                $largestWidth = $limited[$index]
            }

            $index++
        }

        if ($largestIndex -lt 0) {
            break
        }

        $limited[$largestIndex]--
    }

    return $limited
}

function script:Limit-HumanizerCellLine {
    param(
        [string]$Value,
        [int]$Width
    )

    if ($Value.Length -le $Width) {
        return $Value
    }

    if ($Width -le 3) {
        return $Value.Substring(0, $Width)
    }

    return $Value.Substring(0, $Width - 3) + '...'
}

function script:New-HumanizerBorder {
    param(
        [string]$Left,
        [string]$Middle,
        [string]$Right,
        [int[]]$Widths
    )

    $parts = foreach ($width in $Widths) {
        '─' * ($width + 2)
    }

    return script:ConvertTo-HumanizerStyledText -Text ($Left + ($parts -join $Middle) + $Right) -Kind 'Border'
}

function script:New-HumanizerTableRow {
    param(
        [object[]]$Cells,
        [int[]]$Widths
    )

    $splitCells = @()
    $cellKinds = @()
    foreach ($cell in $Cells) {
        $splitCells += ,@((script:Get-HumanizerCellText $cell) -split "`n")
        $cellKinds += script:Get-HumanizerCellKind $cell
    }

    $height = 1
    foreach ($cellLines in $splitCells) {
        if ($cellLines.Count -gt $height) {
            $height = $cellLines.Count
        }
    }

    $rows = @()
    $lineIndex = 0
    while ($lineIndex -lt $height) {
        $parts = @()
        $columnIndex = 0
        while ($columnIndex -lt $Cells.Count) {
            $line = ''
            if ($lineIndex -lt $splitCells[$columnIndex].Count) {
                $line = $splitCells[$columnIndex][$lineIndex]
            }

            $line = script:Limit-HumanizerCellLine -Value $line -Width $Widths[$columnIndex]
            $styledLine = script:ConvertTo-HumanizerStyledText -Text $line -Kind $cellKinds[$columnIndex]
            $parts += ' ' + $styledLine + (' ' * ($Widths[$columnIndex] - $line.Length)) + ' '
            $columnIndex++
        }

        $border = script:ConvertTo-HumanizerStyledText -Text '│' -Kind 'Border'
        $rows += $border + ($parts -join $border) + $border
        $lineIndex++
    }

    return $rows
}

function script:Format-HumanizerBoxTable {
    param(
        [string[]]$Headers,
        [object[]]$Rows,
        [int]$MaxWidth = 0
    )

    $widths = @()
    $minimumWidths = @()
    $columnIndex = 0
    while ($columnIndex -lt $Headers.Count) {
        $minimumWidth = [Math]::Min((script:Get-HumanizerValueWidth $Headers[$columnIndex]), 12)
        $width = script:Get-HumanizerValueWidth $Headers[$columnIndex]
        foreach ($row in $Rows) {
            $cellWidth = script:Get-HumanizerValueWidth (script:Get-HumanizerCellText $row[$columnIndex])
            if ($cellWidth -gt $width) {
                $width = $cellWidth
            }
        }

        $widths += $width
        $minimumWidths += $minimumWidth
        $columnIndex++
    }

    $widths = script:Limit-HumanizerTableWidths -Widths $widths -MinimumWidths $minimumWidths -MaxWidth $MaxWidth

    $output = @()
    $output += script:New-HumanizerBorder '┌' '┬' '┐' $widths
    $headerCells = foreach ($header in $Headers) {
        script:New-HumanizerCell -Text $header -Kind 'Header'
    }
    $output += script:New-HumanizerTableRow $headerCells $widths
    $output += script:New-HumanizerBorder '├' '┼' '┤' $widths
    foreach ($row in $Rows) {
        $output += script:New-HumanizerTableRow ([object[]]$row) $widths
    }

    $output += script:New-HumanizerBorder '└' '┴' '┘' $widths
    return $output
}

function script:ConvertTo-HumanizerRecordTable {
    param(
        [object]$Value,
        [int]$Depth,
        [int]$ExpandDepth,
        [int]$MaxWidth = 0
    )

    $rows = @()
    foreach ($property in $Value.PSObject.Properties) {
        $rows += ,@(
            $property.Name,
            (script:ConvertTo-HumanizerCell -Value $property.Value -Depth $Depth -ExpandDepth $ExpandDepth)
        )
    }

    return script:Format-HumanizerBoxTable -Headers @('Property', 'Value') -Rows $rows -MaxWidth $MaxWidth
}

function script:ConvertTo-HumanizerListTable {
    param(
        [object]$Value,
        [int]$Depth,
        [int]$ExpandDepth,
        [int]$MaxWidth = 0
    )

    $items = @(script:Get-HumanizerListItems $Value)
    if ($items.Count -eq 0) {
        return script:Format-HumanizerBoxTable -Headers @('#', 'Value') -Rows @() -MaxWidth $MaxWidth
    }

    $allRecords = $true
    foreach ($item in $items) {
        if (-not (script:Test-HumanizerRecord $item)) {
            $allRecords = $false
            break
        }
    }

    if (-not $allRecords) {
        $rows = @()
        $index = 0
        while ($index -lt $items.Count) {
            $rows += ,@(
                [string]$index,
                (script:ConvertTo-HumanizerCell -Value $items[$index] -Depth $Depth -ExpandDepth $ExpandDepth)
            )
            $index++
        }

        return script:Format-HumanizerBoxTable -Headers @('#', 'Value') -Rows $rows -MaxWidth $MaxWidth
    }

    $columns = @()
    foreach ($item in $items) {
        foreach ($name in (script:Get-HumanizerRecordNames $item)) {
            if ($columns -notcontains $name) {
                $columns += $name
            }
        }
    }

    $headers = @('#') + $columns
    $rows = @()
    $index = 0
    while ($index -lt $items.Count) {
        $row = @([string]$index)
        foreach ($column in $columns) {
            $property = $items[$index].PSObject.Properties[$column]
            if ($property) {
                $row += script:ConvertTo-HumanizerCell -Value $property.Value -Depth $Depth -ExpandDepth $ExpandDepth
            } else {
                $row += ''
            }
        }

        $rows += ,$row
        $index++
    }

    return script:Format-HumanizerBoxTable -Headers $headers -Rows $rows -MaxWidth $MaxWidth
}

function script:ConvertTo-HumanizerTable {
    param(
        [Parameter(Mandatory)]
        [object]$Value,

        [int]$Depth = 0,

        [int]$ExpandDepth = 2,

        [int]$MaxWidth = 0
    )

    if (script:Test-HumanizerRecord $Value) {
        return script:ConvertTo-HumanizerRecordTable -Value $Value -Depth $Depth -ExpandDepth $ExpandDepth -MaxWidth $MaxWidth
    }

    if (script:Test-HumanizerList $Value) {
        return script:ConvertTo-HumanizerListTable -Value $Value -Depth $Depth -ExpandDepth $ExpandDepth -MaxWidth $MaxWidth
    }

    return @(script:ConvertTo-HumanizerScalar $Value)
}

function script:Test-IsJson {
    <#
    .SYNOPSIS
        Returns $true when the string (after trimming) starts with { or [.
        Performs a full parse only when the quick check passes and the document
        is small enough that the cost is negligible. Parsing is skipped for very
        large strings because the caller will parse once anyway if this returns true.
    #>
    param([string]$Text)

    $trimmed = $Text.Trim()
    if (-not ($trimmed.StartsWith('{') -or $trimmed.StartsWith('['))) {
        return $false
    }

    # For very large payloads skip the validation parse. The structural check
    # above is sufficient, and ConvertTo-ColorJson will parse the document once
    # anyway. Real JSON errors will be caught in the caller's try/catch.
    if ($trimmed.Length -gt $script:MaxValidationParseSize) {
        return $true
    }

    try {
        $null = $trimmed | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function script:Test-IsTerminal {
    <#
    .SYNOPSIS
        Returns $true when stdout is connected to an interactive terminal
        (i.e. not redirected to a file or another process via a pipe).
    #>
    # [Console]::IsOutputRedirected is $true when stdout is a pipe or file.
    return (-not [Console]::IsOutputRedirected)
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

function Format-HumanizerJson {
    <#
    .SYNOPSIS
        Pretty-print and colorize $InputString if it looks like JSON and
        stdout is a terminal.  Falls back to raw output for pipes/files.

    .EXAMPLE
        $raw = & kubectl get pods -o json
        Format-HumanizerJson $raw
    #>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$InputString,

        [ValidateSet('Raw', 'PrettyJson', 'Table', 'Auto')]
        [string]$View = 'Auto',

        [ValidateRange(0, 10)]
        [int]$ExpandDepth = 2
    )

    if ($View -eq 'Raw') {
        Write-Output $InputString
        return
    }

    if ((script:Test-IsTerminal) -and (script:Test-IsJson $InputString)) {
        try {
            $obj = ConvertFrom-Json -InputObject $InputString -Depth 100 -NoEnumerate -ErrorAction Stop
            $resolvedView = $View
            if ($View -eq 'Auto') {
                if ((script:Test-HumanizerRecord $obj) -or (script:Test-HumanizerList $obj)) {
                    $resolvedView = 'Table'
                } else {
                    $resolvedView = 'PrettyJson'
                }
            }

            $maxWidth = [Math]::Max(40, [Console]::WindowWidth - 1)
            if ($View -eq 'Auto' -and $resolvedView -eq 'Table') {
                foreach ($line in (script:ConvertTo-HumanizerAutoTable -Value $obj -ExpandDepth $ExpandDepth -MaxWidth $maxWidth)) {
                    Write-Host $line
                }
            } elseif ($resolvedView -eq 'Table') {
                foreach ($line in (script:ConvertTo-HumanizerTable -Value $obj -ExpandDepth $ExpandDepth -MaxWidth $maxWidth)) {
                    Write-Host $line
                }
            } else {
                script:ConvertTo-ColorJson $InputString
            }

            return
        } catch {
            # Parsing failed, so the original output remains the safest result.
        }
    }

    # Machine-readable path: raw output, no decoration
    Write-Output $InputString
}

function New-Humanizer {
    <#
    .SYNOPSIS
        Create a wrapper function for an executable that automatically
        pretty-prints JSON output when running in a terminal.

    .PARAMETER Name
        The function name you want to use (e.g. "kubectl").

    .PARAMETER Path
        Full path to the executable (e.g. "C:\tools\kubectl.exe").
        Defaults to the result of Get-Command $Name if omitted.

    .EXAMPLE
        New-Humanizer kubectl  "C:\tools\kubectl.exe"
        New-Humanizer gh       "C:\Program Files\GitHub CLI\gh.exe"
        New-Humanizer agentdoor "$HOME\bin\agentdoor.exe"
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Path,

        [ValidateSet('Raw', 'PrettyJson', 'Table', 'Auto')]
        [string]$View = 'Auto',

        [ValidateRange(0, 10)]
        [int]$ExpandDepth = 2
    )

    if (-not $Path) {
        $cmd = Get-Command $Name -ErrorAction SilentlyContinue
        if (-not $cmd) {
            throw "Cannot resolve '$Name'. Provide the -Path argument explicitly."
        }
        $Path = $cmd.Source
    }

    # Capture the resolved path in a local variable so the scriptblock closes
    # over it correctly even when New-Humanizer is called multiple times.
    $resolvedPath = $Path
    $formatter = ${function:Format-HumanizerJson}
    $viewName = $View
    $viewExpandDepth = $ExpandDepth

    $funcBody = {
        # Only stdout is captured. stderr flows through to the caller's error
        # stream naturally, keeping error messages separate from JSON output.
        $raw = & $resolvedPath @args
        $exitCode = $LASTEXITCODE

        # Guard against null / empty output (e.g. command produced no stdout).
        # The array check is needed because PowerShell may return an empty
        # array rather than $null when an executable emits no output at all.
        if (-not $raw -or ($raw -is [array] -and $raw.Count -eq 0)) {
            $global:LASTEXITCODE = $exitCode
            return
        }

        # Join all output lines, normalize line endings to LF, and trim trailing
        # whitespace. The pattern `r`n?` matches CR optionally followed by LF,
        # handling both CRLF (Windows) and bare CR (classic Mac) in one pass.
        $joined     = [string]::Join("`n", @($raw))
        $normalized = $joined -replace "`r`n?", "`n"
        $text      = $normalized.TrimEnd()

        & $formatter $text -View $viewName -ExpandDepth $viewExpandDepth

        # Propagate the original exit code so callers can detect failures.
        $global:LASTEXITCODE = $exitCode
    }.GetNewClosure()

    # Register the function in the caller's (global) scope
    Set-Item -Path "function:global:$Name" -Value $funcBody
    Write-Verbose "humanizer: '$Name' -> '$resolvedPath'"
}
