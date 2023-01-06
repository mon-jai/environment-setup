Param([switch]$InstallPython)

# Copyright 2023 Loh Ka Hong | Licensed under MIT

Import-Module BitsTransfer

$logFilePath = "$Env:TEMP\setup-log.txt"

# Redirect stderr to stdout, and drop the output, https://stackoverflow.com/a/11969703
New-Item -Path $logFilePath -ItemType File | Out-Null

# https://stackoverflow.com/a/39191466/11077662
$add_custom_cmdlet = {
  function Write-Log {
    [CmdletBinding()]
    Param ([Parameter(ValueFromPipeline)] [string[]]$content)
    Process {
      $content | Out-File -Append -LiteralPath $logFilePath
    }
  }
}

Start-Job -Name 'Enable clipboard' -InitializationScript $add_custom_cmdlet -ScriptBlock {
  try {
    # https://stackoverflow.com/a/41476689
    New-ItemProperty -path 'HKCU:\Software\Microsoft\Clipboard' -name EnableClipboardHistory -propertyType DWord -value 1 -force -ErrorAction Stop *>&1 | Write-Log

    Write-Host "Enabled clipboard"
  }
  catch {
    Write-Host "Enable clipboard skipped"
  }
}

Start-Job -Name 'Configure language' -InitializationScript $add_custom_cmdlet -ScriptBlock {
  # https://stackoverflow.com/a/51374938
  Set-Culture en-US
  Set-WinSystemLocale -SystemLocale en-US
  Set-WinUILanguageOverride -Language en-US

  $languageList = New-WinUserLanguageList en-US
  $languageList.Add('zh-Hant-TW')
  $languageList[1].InputMethodTips.Clear()
  $languageList[1].InputMethodTips.Add('0404:{531FDEBF-9B4C-4A43-A2AA-960E8FCDC732}{4BDF9F03-C7D3-11D4-B2AB-0080C882687E}')
  Set-WinUserLanguageList $languageList -Force

  Write-Host "Configured language"
}

Start-Job -Name 'Install Windows Terminal' -InitializationScript $add_custom_cmdlet -ScriptBlock {
  $desktopFrameworkPackageDownloadURL = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
  $desktopFrameworkPackageDownloadPath = "$Env:TEMP/VCLibs.appx"

  $windowsTerminalDownloadURL = "https://github.com/microsoft/terminal/releases/download/v1.15.3465.0/Microsoft.WindowsTerminal_Win10_1.15.3465.0_8wekyb3d8bbwe.msixbundle"
  $windowsTerminalDownloadPath = "$Env:TEMP/WindowsTerminal.msixbundle"

  Start-BitsTransfer $desktopFrameworkPackageDownloadURL $desktopFrameworkPackageDownloadPath
  Start-BitsTransfer $windowsTerminalDownloadURL $windowsTerminalDownloadPath

  try {
    Add-AppxPackage $desktopFrameworkPackageDownloadPath -ErrorAction Stop *>&1 | Write-Log
    Add-AppxPackage $windowsTerminalDownloadPath -ErrorAction Stop *>&1 | Write-Log

    Write-Host "Installed Windows Terminal"
  }
  catch {
    Write-Host "Install Windows Terminal skipped"
  }
}

if ($InstallPython) {
  Start-Job -Name 'Install and configure Python' -InitializationScript $add_custom_cmdlet -ScriptBlock {
    $pythonDownloadPath = "$Env:TEMP/python.exe"

    # https://stackoverflow.com/a/73534796
    if (
      (Invoke-RestMethod 'https://www.python.org/downloads/') -notmatch
      '\bhref="(?<url>.+?\.exe)"\s*>\s*Download Python (?<version>\d+\.\d+\.\d+)'
    ) { throw "Could not determine latest Python version and download URL" }

    # https://stackoverflow.com/a/21423159
    Start-BitsTransfer $Matches.url $pythonDownloadPath

    # https://stackoverflow.com/a/73665900
    Start-Process $pythonDownloadPath -ArgumentList "/quiet", "PrependPath=1", "InstallLauncherAllUsers=0" -NoNewWindow -Wait
    Remove-Item $pythonDownloadPath

    # Reload PATH to run python and pip, https://stackoverflow.com/a/31845512
    $Env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # https://stackoverflow.com/a/67796873
    pip config set global.trusted-host "pypi.org files.pythonhosted.org pypi.python.org" | Write-Log
    python -m pip install --upgrade pip | Write-Log
    pip install -U autopep8 | Write-Log

    Write-Host "Installed and configured Python"
  }
}

Start-Job -Name 'Configure VSCode' -InitializationScript $add_custom_cmdlet -ScriptBlock {
  # https://stackoverflow.com/a/36705460
  # https://stackoverflow.com/a/36751445
  Remove-Item "$Env:USERPROFILE/.vscode/extensions" -Force -Recurse -ErrorAction SilentlyContinue

  $vscodeSettingsDir = "$Env:APPDATA\Code\User\"
  $vscodeSettings = [pscustomobject]@{
    "[python]"                         = [pscustomobject]@{
      "editor.tabSize" = 4
    }
    "code-runner.clearPreviousOutput"  = $true
    "code-runner.executorMap"          = [pscustomobject]@{
      # https://stackoverflow.com/a/53961913
      "python" = "clear; & `"`$env:LocalAppData\Programs\Python\Python311\python`" -u"
    }
    "code-runner.ignoreSelection"      = $true
    "code-runner.runInTerminal"        = $true
    "code-runner.saveFileBeforeRun"    = $true
    "editor.tabSize"                   = 2
    "explorer.confirmDelete"           = $false
    "files.associations"               = [pscustomobject]@{
      "*.xml" = "html"
    }
    "http.proxyStrictSSL"              = $false
    "python.analysis.typeCheckingMode" = "strict"
    "workbench.colorTheme"             = "GitHub Light Default"
    "workbench.startupEditor"          = "none"
  }

  # Throw an error if the directory already exists
  New-Item $vscodeSettingsDir -ItemType Directory -ErrorAction SilentlyContinue *>&1 | Write-Log
  ConvertTo-Json -InputObject $vscodeSettings | Out-File -Encoding "UTF8" "$vscodeSettingsDir\settings.json"

  code --install-extension formulahendry.code-runner --force *>&1 | Write-Log
  code --install-extension github.github-vscode-theme --force *>&1 | Write-Log

  if ($InstallPython) {
    code --install-extension ms-python.python --force *>&1 | Write-Log
  }

  Write-Host "Configured VSCode"
}

Get-Job | Receive-Job -Wait -ErrorAction Stop
Write-Host "Done!"
