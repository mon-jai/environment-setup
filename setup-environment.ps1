Param([switch]$InstallPython)

# Copyright 2023 Loh Ka Hong | Licensed under MIT

Import-Module BitsTransfer

# https://github.com/Azure/azure-iot-protocol-gateway/blob/0c21567/host/ProtocolGateway.Host.Fabric.FrontEnd/PackageRoot/Code/InstallDotNet48.ps1#L69
$Env:SetupLogFilePath = Join-Path $Env:TEMP -ChildPath "setup-log.txt"

# Redirect stderr to stdout, and drop the output, https://stackoverflow.com/a/11969703
New-Item -Path $Env:SetupLogFilePath -ItemType File -Force | Out-Null

# https://stackoverflow.com/a/39191466
# https://stackoverflow.com/a/68882127
$add_custom_cmdlet = {
  function Write-Log {
    [CmdletBinding()]
    Param ([Parameter(ValueFromPipeline)] [string[]]$content)
    Process {
      # https://social.technet.microsoft.com/Forums/windowsserver/en-US/51ef5275-02f8-423c-b2c9-a822c982ecf0/variable-scope-within-a-startjob-initializationscript#9eea0a0c-6ff8-4c2b-b832-158a55f4f5db-isAnswer
      # https://github.com/PowerShell/PowerShell/issues/4530
      $content | Out-File -Append -LiteralPath $Env:SetupLogFilePath
    }
  }

  function Write-Host-And-Log {
    [CmdletBinding()]
    Param ([Parameter(ValueFromPipeline)] [string[]]$content)
    Process {
      Write-Host $content;
      Write-Log $content;
    }
  }
}

. $add_custom_cmdlet

Start-Job -Name "Enable clipboard" -InitializationScript $add_custom_cmdlet -ScriptBlock {
  try {
    # https://stackoverflow.com/a/41476689
    New-ItemProperty -path "HKCU:\Software\Microsoft\Clipboard" -name EnableClipboardHistory -propertyType DWord -value 1 -force -ErrorAction Stop *>&1 | Write-Log

    Write-Host-And-Log "Enabled clipboard"
  }
  catch {
    Write-Host-And-Log "Enable clipboard skipped"
  }
} | Out-Null # https://stackoverflow.com/a/58809009/11077662

Start-Job -Name "Configure language" -InitializationScript $add_custom_cmdlet -ScriptBlock {
  # https://stackoverflow.com/a/51374938
  Set-Culture en-US
  Set-WinSystemLocale -SystemLocale en-US
  Set-WinUILanguageOverride -Language en-US

  $languageList = New-WinUserLanguageList en-US
  $languageList.Add("zh-Hant-TW")
  $languageList[1].InputMethodTips.Clear()
  $languageList[1].InputMethodTips.Add("0404:{531FDEBF-9B4C-4A43-A2AA-960E8FCDC732}{4BDF9F03-C7D3-11D4-B2AB-0080C882687E}")
  Set-WinUserLanguageList $languageList -Force

  Write-Host-And-Log "Configured language"
} | Out-Null

Start-Job -Name "Configure taskbar" -InitializationScript $add_custom_cmdlet -ScriptBlock {
  Remove-Item "$Env:AppData\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\" -Force -Recurse -ErrorAction SilentlyContinue
  Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband" -Force -Recurse

  Stop-Process -Name explorer
  # Wait for Windows Explorer to start by launching a Explorer window and wait for return
  Start-Process explorer -Wait
  # https://stackoverflow.com/a/60214941
  (New-Object -ComObject Shell.Application).Windows() | Where-Object{ $_.FullName -eq "C:\Windows\explorer.exe" } | ForEach-Object{ $_.Quit() }

  # https://stackoverflow.com/a/9701907/11077662
  $chromeShortcutPath = "$Env:TEMP\chrome.lnk"
  $chromeShortcut = (New-Object -comObject WScript.Shell).CreateShortcut($chromeShortcutPath)
  $chromeShortcut.TargetPath = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
  $chromeShortcut.Arguments = "--profile-directory=`"Profile 1`""
  $chromeShortcut.WorkingDirectory = "C:\Program Files (x86)\Google\Chrome\Application"
  $chromeShortcut.Save()

  $pttbPath = "$Env:TEMP\pttb.exe"
  Start-BitsTransfer "https://github.com/0x546F6D/pttb_-_Pin_To_TaskBar/raw/1c48814/pttb.exe" $pttbPath
  & $pttbPath "C:\Windows\explorer.exe"
  & $pttbPath $chromeShortcutPath
  & $pttbPath "$Env:LocalAppData\Programs\Microsoft VS Code\Code.exe"
  & $pttbPath "$Env:windir\system32\SnippingTool.exe"

  Write-Host-And-Log "Configured taskbar"
} | Out-Null

Start-Job -Name "Install Windows Terminal" -InitializationScript $add_custom_cmdlet -ScriptBlock {
  try {
    # https://stackoverflow.com/a/7330368
    # https://github.com/microsoft/terminal#installing-and-running-windows-terminal
    if ([System.Environment]::OSVersion.Version.build -lt 19041) {
      throw "PC does not meet minimum system requirements"
    }

    $desktopFrameworkPackageDownloadURL = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
    $desktopFrameworkPackageDownloadPath = "$Env:TEMP\VCLibs.appx"

    $windowsTerminalDownloadURL = "https://github.com/microsoft/terminal/releases/download/v1.15.3465.0/Microsoft.WindowsTerminal_Win10_1.15.3465.0_8wekyb3d8bbwe.msixbundle"
    $windowsTerminalDownloadPath = "$Env:TEMP\WindowsTerminal.msixbundle"

    Start-BitsTransfer $desktopFrameworkPackageDownloadURL $desktopFrameworkPackageDownloadPath
    Start-BitsTransfer $windowsTerminalDownloadURL $windowsTerminalDownloadPath

    Add-AppxPackage $desktopFrameworkPackageDownloadPath -ErrorAction Stop *>&1 | Write-Log
    Add-AppxPackage $windowsTerminalDownloadPath -ErrorAction Stop *>&1 | Write-Log

    Write-Host-And-Log "Installed Windows Terminal"
  }
  catch {
    Write-Host-And-Log "Install Windows Terminal skipped"
  }
} | Out-Null

Start-Job -Name "Configure VSCode" -InitializationScript $add_custom_cmdlet -ScriptBlock {
  # https://stackoverflow.com/a/36705460
  # https://stackoverflow.com/a/36751445
  Remove-Item "$Env:USERPROFILE\.vscode\extensions" -Force -Recurse -ErrorAction SilentlyContinue

  $vscodeSettingsDir = "$Env:APPDATA\Code\User\"
  $vscodeSettings = [pscustomobject]@{
    "[python]"                         = [pscustomobject]@{
      "editor.tabSize" = 4
    }
    "code-runner.clearPreviousOutput"  = $true
    "code-runner.executorMap"          = [pscustomobject]@{
      # https://stackoverflow.com/a/53961913
      "python" = "clear; & `"`$Env:LocalAppData\Programs\Python\Python311\python`" -u"
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

  $firaCodeArchivePath = "$Env:TEMP\Fira_Code.zip"
  $firaCodePath = "$Env:TEMP\Fira_Code/"
  $firaCodeFilename = "FiraCode-VF.ttf"

  Start-BitsTransfer "https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip" $firaCodeArchivePath
  Expand-Archive $firaCodeArchivePath $firaCodePath
  Copy-Item -Path "$firaCodePath/variable_ttf/FiraCode-VF.ttf" -Destination "$Env:windir\Fonts\" -Force

  code --install-extension formulahendry.code-runner --force *>&1 | Write-Log
  code --install-extension github.github-vscode-theme --force *>&1 | Write-Log

  if ($Using:InstallPython) {
    code --install-extension ms-python.python --force *>&1 | Write-Log
  }

  Write-Host-And-Log "Configured VSCode"
} | Out-Null

if ($InstallPython) {
  Start-Job -Name "Install and configure Python" -InitializationScript $add_custom_cmdlet -ScriptBlock {
    $pythonDownloadPath = "$Env:TEMP\python.exe"

    # https://stackoverflow.com/a/73534796
    if (
      (Invoke-RestMethod "https://www.python.org/downloads/") -notmatch
      "\bhref=`"(?<url>.+?\.exe)`"\s*>\s*Download Python (?<version>\d+\.\d+\.\d+)"
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

    Write-Host-And-Log "Installed and configured Python"
  } | Out-Null
}

Get-Job | Receive-Job -Wait -ErrorAction Stop

Write-Host "Done!"
