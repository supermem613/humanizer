# humanizer

A drop-in PowerShell helper that automatically pretty-prints and colorizes JSON output from any CLI — with **zero flags, zero pipes, and zero changes to your tools**.

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

### 3. Wrap the CLIs you care about (once, in your profile)

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

That's it. **Restart your terminal** (or re-source your profile) and every call to those commands is automatically humanized.

---

## Usage

```powershell
# Terminal → colorized, pretty-printed JSON
kubectl get pods -o json

# Pipe → raw JSON (agents / jq / scripts work perfectly)
kubectl get pods -o json | jq '.items[].metadata.name'

# Redirect → raw JSON written to file
kubectl get pods -o json > pods.json
```

No flags. No extra pipes. No changes to the underlying tool.

---

## How it works

| Scenario | What happens |
|---|---|
| Running in a terminal | JSON is detected, re-indented, and colorized with `Write-Host` |
| Output piped to another process | `[Console]::IsOutputRedirected` is `true` → raw `Write-Output` |
| Output redirected to a file | Same as above → raw `Write-Output` |
| Output is not valid JSON | Raw `Write-Output` regardless of destination |

### Color scheme

| Element | Color |
|---|---|
| Keys | DarkYellow |
| String values | Green |
| Numbers / booleans / null | Cyan |
| Structural characters | Gray |

---

## Public API

### `Format-HumanizerJson`

Pretty-prints a JSON string (or passes it through raw) according to the rules above.

```powershell
$raw = & "C:\tools\agentdoor.exe" run
Format-HumanizerJson $raw

# Also accepts pipeline input
& "C:\tools\agentdoor.exe" run | Format-HumanizerJson
```

### `New-Humanizer`

Creates a global wrapper function for any executable.

```powershell
New-Humanizer [-Name] <string> [[-Path] <string>]
```

| Parameter | Required | Description |
|---|---|---|
| `Name` | Yes | Name of the wrapper function to create (e.g. `"kubectl"`) |
| `Path` | No | Full path to the executable. Resolved via `Get-Command` if omitted. |