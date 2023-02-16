# Environment Setup

Scripts for setting up a development environment in university's computers.

## Installation

> **Note**\
> Also set an environment variable named `SetupLogFilePath`, containing the path to log file.

### Syntax

<!-- Throw an statement-terminating error when "the setting is overridden by a policy defined at a more specific scope", https://stackoverflow.com/a/60549569 -->
<!-- Redirect all streams to $null, https://stackoverflow.com/a/6461021 -->
<!-- https://stackoverflow.com/a/68777742 -->
<!-- https://stackoverflow.com/a/68777742 -->

```powershell
. { Set-ExecutionPolicy Bypass -Scope Process -Force } *> $null; . ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/mon-jai/environment-setup/main/setup-environment.ps1')))`
  [-InstallPython]
```

### Parameters

#### `-InstallPython`

Install Python and related tooling.

## Cleanup

### Delete Chrome profile data

```powershell
Remove-Item "$Env:LOCALAPPDATA\Google\Chrome\User Data\" -Force -Recurse
```
