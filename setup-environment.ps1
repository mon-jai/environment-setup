Param([string]$lang)

Import-Module BitsTransfer

if ($lang -eq "c++") { $lang = "cpp" }
if ($lang -eq "py") { $lang = "python" }

$clangdPath = "$Env:USERPROFILE\clangd\"
# https://github.com/Azure/azure-iot-protocol-gateway/blob/0c21567/host/ProtocolGateway.Host.Fabric.FrontEnd/PackageRoot/Code/InstallDotNet48.ps1#L69
$Env:SetupLogFilePath = Join-Path $Env:TEMP -ChildPath "setup-log.txt"

# https://stackoverflow.com/a/39191466
# https://stackoverflow.com/a/68882127
$add_custom_cmdlet = {
  function Write-Log {
    [CmdletBinding()]
    Param ([Parameter(ValueFromPipeline)] [string[]]$content)

    # https://social.technet.microsoft.com/Forums/windowsserver/en-US/51ef5275-02f8-423c-b2c9-a822c982ecf0/variable-scope-within-a-startjob-initializationscript#9eea0a0c-6ff8-4c2b-b832-158a55f4f5db-isAnswer
    # https://github.com/PowerShell/PowerShell/issues/4530
    $content | Out-File -Append -LiteralPath $Env:SetupLogFilePath
  }

  function Write-Host-And-Log {
    [CmdletBinding()]
    Param ([Parameter(ValueFromPipeline)] [string[]]$content)

    Write-Host $content;
    Write-Log $content;
  }

  function Merge-Object ($a, $b) {
    $result = New-Object PSObject

    # https://stackoverflow.com/a/45550182/11077662
    $a.psobject.Properties + $b.psobject.Properties | ForEach-Object {
      $result | Add-Member -MemberType $_.MemberType -Name $_.Name -Value $_.Value -Force
    }

    Write-Output $result
  }
}

Start-Job -Name "Enable clipboard" -InitializationScript $add_custom_cmdlet -ScriptBlock {
  try {
    # https://stackoverflow.com/a/41476689
    New-ItemProperty -path "HKCU:\Software\Microsoft\Clipboard" -name EnableClipboardHistory -propertyType DWord -value 1 -force -ErrorAction Stop *>&1 | Write-Log

    Write-Host-And-Log "Enabled clipboard"
  }
  catch {
    Write-Host-And-Log "Enable clipboard skipped"
  }
} | Out-Null # https://stackoverflow.com/a/58809009

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
  (New-Object -ComObject Shell.Application).Windows() | Where-Object { $_.FullName -eq "C:\Windows\explorer.exe" } | ForEach-Object { $_.Quit() }

  # https://stackoverflow.com/a/9701907
  $chromePath = "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
  $chromeProfileDirectory = "mon-jai"
  $chromeShortcutPath = "$Env:TEMP\chrome.lnk"
  $chromeShortcut = (New-Object -comObject WScript.Shell).CreateShortcut($chromeShortcutPath)
  $chromeShortcut.Arguments = "--profile-directory=$chromeProfileDirectory"
  $chromeShortcut.IconLocation = "$Env:LocalAppData\Google\Chrome\User Data\$chromeProfileDirectory\Google Profile.ico"
  $chromeShortcut.TargetPath = $chromePath
  $chromeShortcut.WorkingDirectory = "C:\Program Files (x86)\Google\Chrome\Application"
  $chromeShortcut.Save()

  # Don't run in CI environments
  if (Test-Path $chromePath) { & $chromePath --profile-directory="$chromeProfileDirectory" }

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

Start-Job -Name "Configure VS Code" -InitializationScript $add_custom_cmdlet -ScriptBlock {
  $firaCodeArchivePath = "$Env:TEMP\Fira_Code.zip"
  $firaCodePath = "$Env:TEMP\Fira_Code\"
  Start-BitsTransfer "https://github.com/tonsky/FiraCode/releases/download/6.2/Fira_Code_v6.2.zip" $firaCodeArchivePath
  Expand-Archive $firaCodeArchivePath $firaCodePath -Force
  # https://stackoverflow.com/a/67903796
  $signature = "[DllImport(`"gdi32.dll`")]public static extern int AddFontResource(string lpszFilename);"
  $type = Add-Type -MemberDefinition $signature -Name FontUtils -Namespace AddFontResource -Using System.Text -PassThru
  $type::AddFontResource("$firaCodePath\variable_ttf\FiraCode-VF.ttf") | Out-Null

  # https://stackoverflow.com/a/36705460
  # https://stackoverflow.com/a/36751445
  Remove-Item "$Env:USERPROFILE\.vscode\extensions" -Force -Recurse -ErrorAction SilentlyContinue
  code --install-extension formulahendry.code-runner --force *>&1 | Write-Log
  code --install-extension github.github-vscode-theme --force *>&1 | Write-Log

  $vscodeSettings = [pscustomobject]@{
    "editor.cursorBlinking"       = "smooth"
    "editor.fontFamily"           = "Fira Code, Consolas, 'Courier New', monospace"
    "editor.fontLigatures"        = "'ss01', 'ss03', 'cv10'"
    "editor.formatOnPaste"        = $true
    "editor.formatOnType"         = $true
    "editor.guides.bracketPairs"  = $true
    "editor.lineHeight"           = 1.6
    "editor.renderWhitespace"     = "trailing"
    "editor.stickyScroll.enabled" = $true
    "editor.tabSize"              = 4
    "explorer.confirmDelete"      = $false
    "files.associations"          = [pscustomobject]@{
      "*.xml" = "html"
    }
    "workbench.colorTheme"        = "GitHub Light Default"
    "workbench.startupEditor"     = "none"
  }

  if ($Using:lang -eq "python") {
    $vscodeSettings = Merge-Object $vscodeSettings ([pscustomobject]@{
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
        "python.analysis.typeCheckingMode" = "strict"
        "python.formatting.blackArgs"      = @("--preview")
        "python.formatting.provider"       = "black"
        "python.linting.mypyEnabled"       = $true
      })
    code --install-extension ms-python.python --force *>&1 | Write-Log
    code --install-extension ms-pyright.pyright --force *>&1 | Write-Log
  }

  elseif ($Using:lang -eq "cpp") {
    $vscodeSettings = Merge-Object $vscodeSettings ([pscustomobject]@{
        "clangd.path"                                = "$Using:clangdPath\bin\clangd.exe"
        "terminal.integrated.defaultProfile.windows" = "my-pwsh"
        "terminal.integrated.profiles.windows"       = [pscustomobject]@{
          "Ubuntu" = [pscustomobject]@{
            "icon" = "terminal-ubuntu"
            "path" = "ubuntu.exe"
          }
        }
      })
    code --install-extension llvm-vs-code-extensions.vscode-clangd --force *>&1 | Write-Log
  }

  ConvertTo-Json -InputObject $vscodeSettings | Out-File "$Env:APPDATA\Code\User\settings.json" -Encoding "UTF8" -Force

  Write-Host-And-Log "Configured VS Code"
} | Out-Null

if ($lang -eq "python") {
  Start-Job -Name "Install and configure Python" -InitializationScript $add_custom_cmdlet -ScriptBlock {
    $pythonDownloadPath = "$Env:TEMP\python.exe"
    # https://stackoverflow.com/a/76426120
    $latestPythonVersion = (Invoke-RestMethod "https://github.com/python/cpython/releases.atom").title -replace "^v" -notmatch "[a-z]" | Sort-Object { [version] $_ } -Descending | Select-Object -First 1

    # https://stackoverflow.com/a/21423159
    Start-BitsTransfer "https://www.python.org/ftp/python/${latestPythonVersion}/python-${latestPythonVersion}-amd64.exe" $pythonDownloadPath
    # https://stackoverflow.com/a/73665900
    Start-Process $pythonDownloadPath -ArgumentList "/quiet", "PrependPath=1", "InstallLauncherAllUsers=0" -NoNewWindow -Wait
    Remove-Item $pythonDownloadPath

    # Reload PATH to run pip, https://stackoverflow.com/a/31845512
    $Env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    # https://stackoverflow.com/a/67796873
    pip config set global.trusted-host "pypi.org files.pythonhosted.org pypi.python.org" | Write-Log
    pip install pip mypy black ipykernel --upgrade | Write-Log

    Write-Host-And-Log "Installed and configured Python"
  } | Out-Null
}

if ($lang -eq "cpp") {
  Start-Job -Name "Install clangd" -InitializationScript $add_custom_cmdlet -ScriptBlock {
    $clangdArchivePath = "$Env:TEMP\clangd.zip"
    Start-BitsTransfer "https://github.com/clangd/clangd/releases/download/15.0.6/clangd-windows-15.0.6.zip" $clangdArchivePath
    Expand-Archive $clangdArchivePath $Using:clangdPath

    $clangdUnzippedPath = (Get-ChildItem $Using:clangdPath)[0].FullName
    Get-ChildItem $clangdUnzippedPath | ForEach-Object { Move-Item $_.FullName $Using:clangdPath }
    Remove-Item $clangdUnzippedPath

    Write-Host-And-Log "Installed clangd"
  } | Out-Null
}

Get-Job | Receive-Job -Wait -ErrorAction Stop

. $add_custom_cmdlet
Write-Host-And-Log "Done!"
