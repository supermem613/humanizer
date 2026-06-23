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
#   kubectl get pods -o json      # → colorized pretty JSON in the terminal
#   kubectl get pods -o json | jq # → raw JSON, perfect for agents / pipes
#   kubectl get pods -o json > out.json  # → raw JSON written to file

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Maximum size for the validation parse in Test-IsJson.
# Above this threshold the structural check (leading { or [) is sufficient;
# the actual parse cost is deferred to ConvertTo-ColorJson which runs once.
$script:MaxValidationParseSize = 1MB

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
    #   Groups 2-3: internal sub-captures for decimal and exponent parts
    #               (not referenced directly; required by the regex engine).
    # Group 4: optional trailing whitespace before the terminator.
    # Group 5: JSON terminator — comma, closing bracket/brace, or end-of-string.
    $primitivePattern = '^(true|false|null|-?\d+(\.\d+)?([eE][+-]?\d+)?)(\s*)(,|\]|}|$)'

    foreach ($line in $lines) {
        # Key  →  DarkYellow
        # String value  →  Green
        # Number / bool / null  →  Cyan
        # Structural characters  →  Gray

        if ($line -match '^(\s*)"([^"]+)"(\s*:\s*)(.*)$') {
            $indent = $Matches[1]
            $key    = $Matches[2]
            $colon  = $Matches[3]
            $value  = $Matches[4]

            Write-Host -NoNewline $indent
            Write-Host -NoNewline "`"$key`"" -ForegroundColor DarkYellow
            Write-Host -NoNewline $colon

            if ($value -match '^"') {
                Write-Host $value -ForegroundColor Green
            } elseif ($value -match $primitivePattern) {
                Write-Host $value -ForegroundColor Cyan
            } else {
                Write-Host $value -ForegroundColor Gray
            }
        } else {
            Write-Host $line -ForegroundColor Gray
        }
    }
}

function script:Test-IsJson {
    <#
    .SYNOPSIS
        Returns $true when the string (after trimming) starts with { or [.
        Performs a full parse only when the quick check passes and the document
        is small enough that the cost is negligible (parsing is skipped for very
        large strings; the caller will parse once anyway if this returns true).
    #>
    param([string]$Text)

    $trimmed = $Text.Trim()
    if (-not ($trimmed.StartsWith('{') -or $trimmed.StartsWith('['))) {
        return $false
    }

    # For very large payloads skip the validation parse — the structural check
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
        [string]$InputString
    )

    if ((script:Test-IsTerminal) -and (script:Test-IsJson $InputString)) {
        try {
            script:ConvertTo-ColorJson $InputString
            return
        } catch {
            # Parsing failed (e.g. truncated output) – fall through to raw output
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

        [string]$Path
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

    $funcBody = {
        # Only stdout is captured; stderr flows through to the caller's error
        # stream naturally, keeping error messages separate from JSON output.
        $raw = & $resolvedPath @args; $exitCode = $LASTEXITCODE

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

        Format-HumanizerJson $text

        # Propagate the original exit code so callers can detect failures.
        $global:LASTEXITCODE = $exitCode
    }.GetNewClosure()

    # Register the function in the caller's (global) scope
    Set-Item -Path "function:global:$Name" -Value $funcBody
    Write-Verbose "humanizer: '$Name' → '$resolvedPath'"
}
