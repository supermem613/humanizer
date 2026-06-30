# humanizer

A drop-in PowerShell helper that automatically renders JSON output from any CLI without flags, pipes, or changes to the wrapped tool.

When stdout is connected to your terminal, JSON is rendered with the colorized Auto view by default.
When you pipe or redirect output, raw JSON passes through untouched so agents and scripts never break.

## Output contract

Humanizer formats stdout only. Stderr passes through untouched, so progress and effects remain under the producer's control. Pipes and redirects stay raw for stdout; live stdout streaming is not supported because Humanizer captures stdout before rendering. For CLIs such as soda, emit JSON on stdout and progress/effects on stderr; on a TTY, stderr may use a CR-redrawn single line, while non-TTY stderr should use plain newline-delimited phase-transition lines.

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

You can change a wrapper later without recreating it:

```powershell
Set-HumanizerView az -View Raw
Set-HumanizerView az -View PrettyJson
Set-HumanizerView az -View Auto -ExpandDepth 2
Set-HumanizerView az -View Tree -ExpandDepth 1
Get-HumanizerView az
```

---

## Usage

```powershell
# Terminal: colorized Auto-rendered JSON
kubectl get pods -o json

# Pipe: raw JSON for agents and scripts
kubectl get pods -o json | other-tool

# Pipe through Humanizer explicitly
kubectl get pods -o json | To-HumanizerView Auto

# Redirect: raw JSON written to file
kubectl get pods -o json > pods.json
```

No flags, extra pipes, or changes to the underlying tool.

---

## Examples

### Default `Auto` view

`Auto` keeps nested JSON hierarchy visible and renders arrays of records as compact tables under their tree node.

```powershell
New-Humanizer forge
forge config
```

```text
name: forge
ok: true
settings:
├─ retries: 3
├─ timeout: 30
└─ tags:
   ├─ [0]: cli
   └─ [1]: json
```

For record arrays, Auto preserves the parent path and switches the repeated rows into a table:

```powershell
sd opened
```

```text
ok: true
command: opened
data:
   ┌───┬────────────┬─────────┬─────────────┬──────┬────────┐
   │ # │ kind       │ cl      │ path        │ rev  │ action │
   ├───┼────────────┼─────────┼─────────────┼──────┼────────┤
   │ 0 │ changelist │ default │ ·          │ ·   │ ·     │
   │ 1 │ file       │ default │ README.md   │ head │ edit   │
   │ 2 │ file       │ default │ src/app.ps1 │ head │ edit   │
   └───┴────────────┴─────────┴─────────────┴──────┴────────┘
```

Auto uses the same type-aware colors as the other rendered views. Keys are yellow, strings are green, numbers are cyan, booleans are magenta, and connectors, null values, and missing-field markers are gray.

### Auto and table views

`Auto` is the default intelligent view: plain object hierarchy is tree-like, while arrays of records render as tables at the node where they appear.

For common CLI envelopes such as `{ "ok": true, "command": "opened", "data": [...] }`, scalar metadata stays compact and `data` becomes the primary table:

```powershell
New-Humanizer sd -View Auto
sd opened
```

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

Nested records and arrays render inside table cells until `-ExpandDepth` is reached. Use a lower depth when nested values are too wide for the terminal:

```powershell
New-Humanizer forge -View Auto -ExpandDepth 0
```

When a short record array (up to five rows) has rows that carry their own nested array or object, `Auto` expands those rows into tree nodes instead of one squeezed table, so the nested value keeps full terminal width:

```text
data:
└─ changelists:
   └─ [0]:
      ├─ cl: default
      ├─ description: <created by soda; use 'sd change' to add description>
      └─ files:
         ┌───┬─────────────────────────────────────┬──────┬────────┬──────┐
         │ # │ path                                │ rev  │ action │ type │
         ├───┼─────────────────────────────────────┼──────┼────────┼──────┤
         │ 0 │ extensions/oh-my-posh/sd-status.ps1 │ head │ edit   │ text │
         └───┴─────────────────────────────────────┴──────┴────────┴──────┘
```

Scalar-only record arrays and longer lists stay compact as tables. A single-row record array is the exception: when its table would not fit the terminal, `Auto` expands it into a tree node so wide values such as full paths and hashes stay visible instead of being truncated to fit. A single row that fits at full width stays a compact table. The `Table` view always renders full boxed tables, including nested sub-tables inside cells.

### Pretty JSON

Use `PrettyJson` when the original JSON shape matters more than table browsing.

```powershell
New-Humanizer gh -View PrettyJson
```

### Raw output

Use `Raw` for non-JSON CLIs that should keep native terminal behavior.
Raw wrappers are registered as direct aliases to the native executable, so
Humanizer does not capture or re-emit stdout.

```powershell
New-Humanizer rotunda -View Raw
```

Pipes and redirects are always raw, regardless of view:

```powershell
sd opened | other-tool
sd opened > opened.json
```

Use `To-HumanizerView` when you want to choose the format inside a pipeline:

```powershell
sd opened | To-HumanizerView Raw
sd opened | To-HumanizerView Auto
sd opened | To-HumanizerView Tree
sd opened | To-HumanizerView Table
sd opened | To-HumanizerView PrettyJson
```

---

## How it works

| Scenario | What happens |
|---|---|
| Running in a terminal | JSON is detected and rendered with the configured view |
| Wrapper configured with `Raw` | The wrapper is a native alias, so output is not captured or rendered |
| Output piped to another process | `[Console]::IsOutputRedirected` is `true`, so output stays raw through `Write-Output` |
| Output redirected to a file | Output stays raw through `Write-Output` |
| Output is not valid JSON | Raw `Write-Output` regardless of destination |

### Views

| View | Behavior |
|---|---|
| `Auto` | Default. Renders object hierarchy as a compact tree and turns arrays of records into embedded tables |
| `Tree` | Renders records and arrays as a compact Unicode tree, collapsing complex children at `-ExpandDepth` |
| `Table` | Renders records and arrays as boxed tables, including nested tables and explicit `·` markers for missing fields up to `-ExpandDepth`, then truncates wide cells to fit the terminal |
| `PrettyJson` | Re-indents JSON and colorizes keys, strings, numbers, booleans, null, and structural characters |
| `Raw` | Always writes the original output |

`Auto`, `Tree`, `Table`, and `PrettyJson` share the same type-aware colors: keys and headers are yellow, strings are green, numbers are cyan, booleans are magenta, null, missing-field markers, and borders are gray. Width calculations ignore ANSI escape sequences, so color does not cause table wrapping.

---

## Public API

### `Format-HumanizerJson`

Renders a JSON string according to the rules above.

```powershell
$raw = & "C:\tools\agentdoor.exe" run
Format-HumanizerJson $raw
Format-HumanizerJson $raw -View Auto -ExpandDepth 2
Format-HumanizerJson $raw -View Tree -ExpandDepth 2

# Also accepts pipeline input
& "C:\tools\agentdoor.exe" run | Format-HumanizerJson -View Table
```

### `To-HumanizerView`

Renders piped JSON with an explicit view. Defaults to `Raw`, so adding it to a pipeline never decorates output unless you ask for a rendered view.

```powershell
sd opened | To-HumanizerView
sd opened | To-HumanizerView Raw
sd opened | To-HumanizerView Auto
sd opened | To-HumanizerView Tree -ExpandDepth 1
sd opened | To-HumanizerView Table
sd opened | To-HumanizerView PrettyJson
```

### `New-Humanizer`

Creates a global wrapper function for any executable.

```powershell
New-Humanizer [-Name] <string> [[-Path] <string>] [-View <Raw|PrettyJson|Table|Tree|Auto>] [-ExpandDepth <int>]
```

| Parameter | Required | Description |
|---|---|---|
| `Name` | Yes | Name of the wrapper function to create (e.g. `"kubectl"`) |
| `Path` | No | Full path to the executable. Resolved via `Get-Command` if omitted. |
| `View` | No | Rendering mode for terminal output. Defaults to `Auto`. |
| `ExpandDepth` | No | Maximum nested render depth for `Auto`, `Tree`, and `Table`. Defaults to `2`. |

### `Set-HumanizerView`

Changes the view for an existing wrapper without recreating it.

```powershell
Set-HumanizerView [-Name] <string> -View <Raw|PrettyJson|Table|Tree|Auto> [-ExpandDepth <int>]
```

```powershell
Set-HumanizerView sd -View Raw
Set-HumanizerView sd -View Auto -ExpandDepth 2
Set-HumanizerView sd -View Tree -ExpandDepth 1
```

### `Get-HumanizerView`

Returns the current wrapper configuration.

```powershell
Get-HumanizerView [-Name] <string>
```

---

## Tests

Run the repeatable smoke tests from the repository root:

```powershell
.\test\run.ps1
```

The tests verify raw redirected output, Auto rendering, tree rendering, table rendering, wrapper registration, mutable view configuration, and exit-code propagation.

## License

MIT. See `LICENSE`.