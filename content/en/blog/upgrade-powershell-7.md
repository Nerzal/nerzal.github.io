---
draft: false
title: "Windows 11 Still Defaults to PowerShell 5.1 — And Why That's a Problem"
date: 2026-05-10T00:00:00+00:00
tags: ["tutorial", "windows", "windows11", "powershell", "oh-my-posh", "terminal", "devex"]
seo_title: "Upgrade from PowerShell 5.1 to 7 on Windows 11"
description: "Windows 11 still ships PowerShell 5.1 by default, a 2016-era shell on .NET Framework. Learn why that matters and how to upgrade to PowerShell 7."
images: ["img/powershell-51-vs-70.png"]
featured_image: "img/powershell-51-vs-70.png"
toc: true
---

Windows 11 is a modern operating system. Its terminal, however, defaults to a shell from 2016.

When you open PowerShell on a fresh Windows 11 install, you get **Windows PowerShell 5.1**, a version released in August 2016, built on the old .NET Framework 4.x and permanently frozen in time. When PowerShell Core 6.0 went GA in January 2018, Microsoft [announced](https://devblogs.microsoft.com/powershell/powershell-core-6-0-generally-available-ga-and-supported/) that Windows PowerShell would only receive critical fixes from then on, with no new features. It still gets serviced through the [Windows lifecycle](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle), but nobody develops it anymore.

I ran into this the hard way when setting up [Oh My Posh](https://ohmyposh.dev) on a fresh machine. Oh My Posh is a prompt customization framework that promises beautiful, informative terminal prompts. On PowerShell 5.1, it either threw errors or rendered garbled symbols:

{{< image image="img/oh-my-posh-error-5.1.png" imageAlt="Oh My Posh rendering broken icons on PowerShell 5.1" >}}

Tweaking the Oh My Posh settings did not help. Switching to **PowerShell 7** did.

{{< skip-to anchor="installing-powershell-7" label="Skip to installation" >}}

---

## Windows PowerShell vs. PowerShell: Two Different Products

First a word on the naming, because it is genuinely confusing. Microsoft ships two distinct products:

| | Windows PowerShell | PowerShell |
|---|---|---|
| **Version** | 5.1 (final) | 7.x (actively developed) |
| **Runtime** | .NET Framework 4.x | Modern .NET (7.6 LTS: .NET 10) |
| **Platform** | Windows only | Windows, macOS, Linux |
| **Source** | Closed | [Open source on GitHub](https://github.com/PowerShell/PowerShell) |
| **Status** | Maintenance only | Active development, LTS releases |
| **Location** | `C:\Windows\System32\WindowsPowerShell\v1.0\` | `C:\Program Files\PowerShell\7\` |

**Windows PowerShell** (blue icon, `powershell.exe`) is a Windows system component and will never be updated beyond 5.1. **PowerShell** (black icon, `pwsh.exe`) is the successor: a ground-up rewrite released in 2016 as PowerShell Core 6, renamed to PowerShell 7 when it reached feature parity.

They coexist without conflict. Installing PowerShell 7 does not remove Windows PowerShell 5.1.

---

## What You Actually Get with PowerShell 7

These are the concrete differences you will notice day to day.

### Pipeline chain operators

PowerShell 7.0 introduced `&&` and `||`, the operators every developer expects from a shell:

```powershell
# Run build, then only deploy if it succeeded
npm run build && npm run deploy

# Try the fast path, fall back if it fails
Get-Command pwsh || Write-Host "PowerShell 7 not found"
```

PowerShell 5.1 has no equivalent. You would need verbose `if ($LASTEXITCODE -eq 0)` chains.

### Ternary operator

```powershell
$environment = $isProd ? "production" : "development"
```

In 5.1 you need a full `if/else` block for this.

### Null-conditional and null-coalescing operators

```powershell
# Null-coalescing: use right side if left is null
$config = $userConfig ?? $defaultConfig

# Null-conditional: call method only if object is not null
# The braces matter: `$str?.Length` would read a variable named `str?`
$length = ${str}?.Length
```

The null-coalescing operators `??` and `??=` arrived in PowerShell 7.0, the null-conditional member access operators `?.` and `?[]` became stable in PowerShell 7.1. None of them exist in 5.1.

### Parallel pipeline execution

```powershell
# Process items in parallel — not possible in 5.1
1..20 | ForEach-Object -Parallel {
    Invoke-RestMethod "https://api.example.com/item/$_"
} -ThrottleLimit 5
```

`ForEach-Object -Parallel` ships with PowerShell 7.0 and uses thread-based parallelism without requiring background jobs.

### Better error handling

PowerShell 7.0 added `Get-Error`, which displays full exception detail with a structured view. That is far more useful than the truncated stack traces in 5.1.

### Modern .NET access

PowerShell 7 runs on modern .NET. The current LTS release, PowerShell 7.6, is built on .NET 10. Every API and type of that runtime is directly accessible:

```powershell
# JSON with JsonNode — not available on 5.1's .NET Framework 4.x
[System.Text.Json.Nodes.JsonNode]::Parse('{"key": "value"}')
```

### SSH-based remoting

PowerShell 5.1 remoting requires WinRM (Windows Remote Management), which needs firewall configuration and does not work cross-platform. PowerShell 7 adds SSH-based remoting that works to Linux and macOS hosts out of the box. If you manage Linux servers, [securing the SSH daemon](/blog/secure-ssh-server/) should be your first step before enabling remote access from PowerShell.

### Built-in ANSI color support and `$PSStyle`

PowerShell 7.2 introduced `$PSStyle`, a built-in object that controls all ANSI terminal output. Writing colored output in 5.1 meant manually embedding escape sequences, and since the `` `e `` escape only exists from PowerShell 6 on, you even had to build the escape character yourself with `[char]27`. In PowerShell 7 that is a first-class language feature:

```powershell
# 5.1 — manually constructing ANSI escape sequences
$esc = [char]27
Write-Host "$esc[32mSuccess$esc[0m"   # works only in some terminals

# PowerShell 7 — $PSStyle is always available
Write-Host "$($PSStyle.Foreground.Green)Success$($PSStyle.Reset)"

# Named colors, bold, underline, blink — all built-in
$header = $PSStyle.Bold + $PSStyle.Foreground.Cyan
Write-Host "${header}Deployment complete$($PSStyle.Reset)"
```

`$PSStyle` also controls how PowerShell itself renders output: list views, errors, and file system entries all use it, and you can customize them:

```powershell
# Suppress color entirely for CI pipelines
$PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::PlainText
```

### Cleaner error output

PowerShell 7 ships with `ErrorView = 'ConciseView'` as the default. Compare the same error in both versions:

**5.1 output:**

```text
Get-Item : Cannot find path 'C:\does\not\exist' because it does not exist.
At line:1 char:1
+ Get-Item C:\does\not\exist
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : ObjectNotFound: (C:\does\not\exist:String) [Get-Item], ItemNotFoundException
    + FullyQualifiedErrorId : PathNotFound,Microsoft.PowerShell.Commands.GetItemCommand
```

**PowerShell 7 ConciseView:**

```text
Get-Item: Cannot find path 'C:\does\not\exist' because it does not exist.
```

When you need the full detail, `Get-Error` gives you a structured, navigable view of the last exception (inner exceptions, type information, and the full stack trace) without the noise of 5.1's truncated output.

```powershell
Get-Item C:\does\not\exist
Get-Error   # full structured detail of the last error
```

### `Invoke-RestMethod` and `Invoke-WebRequest` upgrades

The HTTP cmdlets in 5.1 were functional but bare. PowerShell 7 added a series of practical improvements:

```powershell
# Automatic retry with backoff — not available in 5.1
Invoke-RestMethod https://api.example.com/data `
    -MaximumRetryCount 3 `
    -RetryIntervalSec 2

# HTTP/2 support
Invoke-WebRequest https://api.example.com `
    -HttpVersion 2.0

# Response headers keep every value
$response = Invoke-WebRequest https://api.example.com
$response.Headers["Content-Type"]   # string[] in PS 7 — repeated headers stay separate
                                     # a single string in PS 5.1

# Skip certificate check for local dev
Invoke-RestMethod https://localhost:5001/api `
    -SkipCertificateCheck
```

In 5.1, `Invoke-RestMethod` returned a `PSCustomObject` for JSON with no way to get a raw hashtable. In PowerShell 7, `ConvertFrom-Json` gained `-AsHashtable`:

```powershell
# 5.1 — PSCustomObject, accessing nested keys is awkward for dynamic data
$data = '{"status": "ok"}' | ConvertFrom-Json
$data.status   # works, but property names must be known at write time

# PowerShell 7 — true hashtable
$data = '{"status": "ok"}' | ConvertFrom-Json -AsHashtable
$data["status"]   # works for any key, including dynamic ones
```

### `Join-String`: a missing cmdlet that finally exists

PowerShell 5.1 had no built-in way to join pipeline output into a single string. The workaround was `($array -join ", ")` or collecting into a variable first. PowerShell 7 ships `Join-String`:

```powershell
# Clean, pipeline-native joining
Get-Process | Select-Object -ExpandProperty Name | Join-String -Separator ", "

# With a prefix and suffix per element
Get-ChildItem *.ps1 | Join-String -Property Name -Separator "`n" -OutputPrefix "Scripts:`n"

# Quoted output — useful for generating arguments
"alpha", "beta", "gamma" | Join-String -SingleQuote -Separator ", "
# 'alpha', 'beta', 'gamma'
```

### Syntax highlighting and predictive IntelliSense

Both shells color your input as you type. Windows 10 and 11 ship Windows PowerShell 5.1 with [PSReadLine](https://github.com/PowerShell/PSReadLine) 2.0, which already does syntax highlighting. PowerShell 7 bundles a current PSReadLine 2.x, which adds [predictive IntelliSense](https://learn.microsoft.com/en-us/powershell/scripting/learn/shell/using-predictors): suggestions from your history and from plugins, shown inline or as a list:

```powershell
# PSReadLine version — check what you have
Get-Module PSReadLine | Select-Object Version

# Take predictions from history and plugins (the default since PSReadLine 2.2.6)
Set-PSReadLineOption -PredictionSource HistoryAndPlugin

# Show predictions as a list below the prompt instead of inline grey text
Set-PSReadLineOption -PredictionViewStyle ListView
```

You can install a newer PSReadLine into 5.1 as well and get history-based predictions there, but predictor plugins require PowerShell 7.2 or higher. In PowerShell 7 the current version is simply part of the box.

### Startup performance

Startup time depends heavily on your machine, your profile, and the modules you load, so measure it yourself instead of trusting numbers from a blog post:

```powershell
# Compare startup time of both shells without profiles
Measure-Command { pwsh -NoProfile -Command "exit" }
Measure-Command { powershell -NoProfile -Command "exit" }
```

Run each line a few times, because the first (cold) start is usually far slower than the following ones. If your CI pipeline calls `pwsh -File script.ps1` dozens of times, `-NoProfile` is the biggest lever you have.

---

## Installing PowerShell 7

### Option 1: winget (recommended)

```powershell
winget install --id Microsoft.PowerShell --source winget
```

This installs the latest stable release. At the time of writing that is PowerShell 7.6, the current LTS release (March 2026, built on .NET 10). PowerShell 7.4 LTS and 7.5 reached end of support on 10 November 2026, so upgrade if you are still on one of them. The `--id` is stable across 7.x releases, so you can also use:

```powershell
winget upgrade --id Microsoft.PowerShell --source winget
```

to stay current. The installer adds `pwsh` to `PATH` automatically.

### Option 2: Microsoft Store

Search for **PowerShell** in the Microsoft Store. The Store version auto-updates and requires no elevation.

### Option 3: GitHub releases

Download the MSI installer from the [official releases page](https://github.com/PowerShell/PowerShell/releases). Choose `PowerShell-7.x.x-win-x64.msi` for 64-bit systems.

### Verify the installation

```powershell
pwsh --version
# PowerShell 7.x.x
```

---

## Setting Up Oh My Posh

With PowerShell 7 installed, Oh My Posh works correctly. Install it via winget:

```powershell
winget install JanDeDobbeleer.OhMyPosh --source winget
```

Then install a [Nerd Font](https://www.nerdfonts.com/), because Oh My Posh uses font ligatures and icons that require a patched font. [Cascadia Code NF](https://github.com/microsoft/cascadia-code) is a solid choice that Microsoft also ships:

```powershell
winget install Microsoft.CascadiaCode
```

Add the Oh My Posh initialization to your PowerShell 7 profile. The profile for `pwsh` lives at:

```text
$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
```

Open it (creating it if needed) with:

```powershell
New-Item -ItemType File -Path $PROFILE -Force
notepad $PROFILE
```

Add the following line to the profile:

```powershell
oh-my-posh init pwsh | Invoke-Expression
```

If you want a specific theme: Oh My Posh ships over 100 built-in themes, stored in:

```text
$env:POSH_THEMES_PATH
```

```powershell
# List available themes
Get-ChildItem $env:POSH_THEMES_PATH

# Use a theme
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json" | Invoke-Expression
```

Restart your terminal. Oh My Posh now renders correctly with icons and powerline segments:

{{< image image="img/powershell-51-vs-70.png" imageAlt="Oh My Posh working correctly on PowerShell 7" >}}

---

## Setting PowerShell 7 as Your Default

Installing `pwsh` does not change what opens when you press Win+X or click the Terminal taskbar icon. That still opens Windows PowerShell 5.1 by default.

### Windows Terminal

Windows Terminal is the recommended terminal host on Windows 11. Open **Settings** (Ctrl+,) → **Startup** → **Default profile** → select **PowerShell** (the one with the black icon and version 7.x). If you do not see it, click **Add a new profile** → **New empty profile** and point the command line to `pwsh.exe`.

Alternatively, edit `settings.json` directly (Ctrl+Shift+, in Windows Terminal) and set the `defaultProfile` GUID to the PowerShell 7 profile's GUID.

### Visual Studio Code

Open **Settings** → search for `terminal.integrated.defaultProfile.windows` → set it to `PowerShell`. VS Code will then use `pwsh.exe` for all integrated terminal sessions.

Or add it directly to `settings.json`:

```json
{
  "terminal.integrated.defaultProfile.windows": "PowerShell",
  "terminal.integrated.profiles.windows": {
    "PowerShell": {
      "source": "PowerShell",
      "icon": "terminal-powershell"
    }
  }
}
```

### JetBrains IDEs

In **Settings** → **Tools** → **Terminal** → set **Shell path** to `pwsh.exe` (or the full path `C:\Program Files\PowerShell\7\pwsh.exe`).

---

## Migrating Your Profile

If you have customizations in your Windows PowerShell 5.1 profile (`$HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`), most of them will work directly in the PowerShell 7 profile (`$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`).

The main sources of incompatibility:

**Module availability:** some older Windows-specific modules only exist for 5.1. Check if a module works in 7 before copying `Import-Module` lines:

```powershell
pwsh -Command "Import-Module YourModule -ErrorAction Stop"
```

**`#Requires -PSEdition Desktop`:** scripts with this header refuse to run in PowerShell 7, which is the `Core` edition. A plain `#Requires -Version 5` is harmless: it means "5.0 or newer", so PowerShell 7 satisfies it. Remove the edition requirement once the script works in 7.

**Windows-only cmdlets:** modules like `ActiveDirectory`, `Hyper-V`, or `GroupPolicy` may not be available for PowerShell 7. Microsoft has been [adding compatibility shims](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/module-compatibility), but check individually.

**COM objects and WMI:** `[wmiclass]` and some COM automation is Windows Framework-specific. Prefer `Get-CimInstance` over `Get-WmiObject`; CIM works in both versions.

---

## Summary

Windows 11 defaults to PowerShell 5.1 for historical and compatibility reasons, but there is no reason to stay on it for day-to-day work. PowerShell 7 is more capable, cross-platform, and required by modern developer tooling like Oh My Posh.

The migration path is straightforward:

1. `winget install --id Microsoft.PowerShell --source winget`
2. `winget install JanDeDobbeleer.OhMyPosh --source winget`
3. Set PowerShell 7 as the default in Windows Terminal
4. Copy and verify your existing profile

Windows PowerShell 5.1 stays installed as a system component and is not going anywhere. Your terminal sessions, however, do not have to run on a shell that was released in 2016 and has not gained a feature since 2018.

---

## Further Reading

- [PowerShell 7 release notes and changelog](https://learn.microsoft.com/en-us/powershell/scripting/whats-new/what-s-new-in-powershell-7x)
- [PowerShell support lifecycle](https://learn.microsoft.com/en-us/powershell/scripting/install/powershell-support-lifecycle)
- [Oh My Posh documentation](https://ohmyposh.dev/docs)
- [PowerShell on GitHub](https://github.com/PowerShell/PowerShell)
- [Windows Terminal documentation](https://learn.microsoft.com/en-us/windows/terminal/)
