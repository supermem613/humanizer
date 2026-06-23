# humanizer

A drop-in PowerShell helper that automatically pretty-prints and colorizes JSON output from any CLI without flags, pipes, or changes to the wrapped tool.

When stdout is connected to your terminal, JSON is rendered in color.
When you pipe or redirect output, raw JSON passes through untouched so agents and scripts never break.

---

## Quick start

### 1. Download / copy `humanizer.ps1`

Save it anywhere, for example `$HOME\tools\humanizer.ps1`.

### 2. Dot-source it from your `$PROFILE`

```powershell
. "$HOME\tools\humanizer.ps1"
```

### 3. Wrap the CLIs you care about once in your profile

```powershell
New-Humanizer kubectl   "C:\tools\kubectl.exe"
New-Humanizer gh        "C:\Program Files\GitHub CLI\gh.exe"
New-Humanizer agentdoor "C:\path\to\agentdoor.exe"
```

If the executable is already on your `PATH` you can omit the path:

```powershell
New-Humanizer kubectl
New-Humanizer gh
```

Restart your terminal, or re-source your profile. Every call to those commands is automatically humanized.

You can also choose a view per wrapper:

```powershell
New-Humanizer gh
New-Humanizer kubectl
New-Humanizer az -View Table -ExpandDepth 2
```

---

## Usage

```powershell
# Terminal: colorized, pretty-printed JSON
kubectl get pods -o json

# Pipe: raw JSON for agents and scripts
kubectl get pods -o json | other-tool

# Redirect: raw JSON written to file
kubectl get pods -o json > pods.json
```

No flags, extra pipes, or changes to the underlying tool.

---

## Examples

### Default `Auto` view

`Auto` renders structured JSON as tables when stdout is connected to a terminal.

```powershell
sd opened
```

For common CLI envelopes such as `{ "ok": true, "command": "opened", "data": [...] }`, scalar metadata stays compact and `data` becomes the primary table:

```text
ok: true
command: opened

┌───┬────────────┬─────────┬───────────────────┬───────────┬───────────┬──────┬────────┬──────┐
│ # │ kind       │ cl      │ description       │ fileCount │ path      │ rev  │ action │ type │
├───┼────────────┼─────────┼───────────────────┼───────────┼───────────┼──────┼────────┼──────┤
│ 0 │ changelist │ default │ <created by soda> │ 3         │           │      │        │      │
│ 1 │ file       │ default │                   │           │ README.md │ head │ edit   │ text │
└───┴────────────┴─────────┴───────────────────┴───────────┴───────────┴──────┴────────┴──────┘
```

### Nested tables

Nested records and arrays render inside their parent cells until `-ExpandDepth` is reached.

```powershell
New-Humanizer forge -View Auto -ExpandDepth 2
```

Use a lower depth when nested values are too wide for the terminal:

```powershell
New-Humanizer forge -View Auto -ExpandDepth 0
```

### Pretty JSON

Use `PrettyJson` when the original JSON shape matters more than table browsing.

```powershell
New-Humanizer gh -View PrettyJson
```

### Raw output

Use `Raw` when a command should never render terminal output.

```powershell
New-Humanizer rotunda -View Raw
```

Pipes and redirects are always raw, regardless of view:

```powershell
sd opened | other-tool
sd opened > opened.json
```

---

## How it works

| Scenario | What happens |
|---|---|
| Running in a terminal | JSON is detected and rendered with the configured view |
| Output piped to another process | `[Console]::IsOutputRedirected` is `true`, so output stays raw through `Write-Output` |
| Output redirected to a file | Output stays raw through `Write-Output` |
| Output is not valid JSON | Raw `Write-Output` regardless of destination |

### Views

| View | Behavior |
|---|---|
| `Auto` | Default. Uses `Table` for records and arrays, otherwise uses `PrettyJson` |
| `Table` | Renders records and arrays as boxed tables, including nested tables up to `-ExpandDepth`, then truncates wide cells to fit the terminal |
| `PrettyJson` | Re-indents JSON and colorizes keys, strings, numbers, booleans, null, and structural characters |
| `Raw` | Always writes the original output |

`Table`, `Auto`, and `PrettyJson` share the same type-aware colors: keys and headers are yellow, strings are green, numbers are cyan, booleans are magenta, null and borders are gray. Width calculations ignore ANSI escape sequences, so color does not cause table wrapping.

---

## Public API

### `Format-HumanizerJson`

Pretty-prints or table-renders a JSON string according to the rules above.

```powershell
$raw = & "C:\tools\agentdoor.exe" run
Format-HumanizerJson $raw
Format-HumanizerJson $raw -View Auto -ExpandDepth 2

# Also accepts pipeline input
& "C:\tools\agentdoor.exe" run | Format-HumanizerJson -View Table
```

### `New-Humanizer`

Creates a global wrapper function for any executable.

```powershell
New-Humanizer [-Name] <string> [[-Path] <string>] [-View <Raw|PrettyJson|Table|Auto>] [-ExpandDepth <int>]
```

| Parameter | Required | Description |
|---|---|---|
| `Name` | Yes | Name of the wrapper function to create (e.g. `"kubectl"`) |
| `Path` | No | Full path to the executable. Resolved via `Get-Command` if omitted. |
| `View` | No | Rendering mode for terminal output. Defaults to `Auto`. |
| `ExpandDepth` | No | Maximum nested table depth for `Table` and `Auto`. Defaults to `2`. |

---

## Tests

Run the repeatable smoke tests from the repository root:

```powershell
.\test\run.ps1
```

The tests verify raw redirected output, table rendering, wrapper registration, view configuration, and exit-code propagation.

## License

MIT. See `LICENSE`.