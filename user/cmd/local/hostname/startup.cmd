@set __SCRIPTPATH=%~f0&@powershell -NoProfile -ExecutionPolicy ByPass -InputFormat None "$s=[scriptblock]::create((gc -enc utf8 -li \"%~f0\"|?{$_.readcount -gt 2})-join\"`n\");&$s" %*
@exit /b %errorlevel%

<#
  .SYNOPSIS
    startup
  .DESCRIPTION
    サインイン時にいろいろ実行する
  .INPUTS
    - mode: "register": タスク登録, "main": 処理実行
    - async: "true": 非同期実行, "false": 同期実行
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change: 2024/11/12 00:58:23.
#>
param([string]$mode = "register", [bool]$async = $false)
$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
$version = "20241112_005823"
# Enable-RunspaceDebug -BreakAll

<#
  .SYNOPSIS
    Main
  .DESCRIPTION
    Execute main
  .INPUTS
    - None
  .OUTPUTS
    - Result - 0 (SUCCESS), 1 (ERROR)
#>
function Start-Main {
  [CmdletBinding()]
  [OutputType([int])]
  param()

  try {

    . "C:\ProgramData\spyrun\core\cfg\common.ps1"

    $app = [PSCustomObject](Start-Init $mode $version)
    log "[Start-Main] Start"

    $xmlStr = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <URI>\spyrun\$($app.userType)\$($app.scope)\$($app.cmdName)</URI>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <GroupId>S-1-5-32-545</GroupId>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <DisallowStartOnRemoteAppSession>false</DisallowStartOnRemoteAppSession>
    <UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>
    <WakeToRun>true</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>3</Count>
    </RestartOnFailure>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>C:\Windows\system32\wscript.exe</Command>
      <Arguments>"$($app.spyrunBase)\core\cfg\launch.js" "$($app.cmdFile)" main</Arguments>
      <WorkingDirectory>$($app.cmdDir)</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

    if ($app.mode -eq "register") {
      Ensure-ScheduledTask $app $xmlStr | Out-Null
      exit $app.cnst.SUCCESS
    }
    if ((Check-ModifiedCmd ([PSCustomObject]@{
            path = $app.cmdFile
            xml = $xmlStr
          })) -ne 0) {
      return $app.cnst.ERROR
    }

    # Execute main.
    log "========== Start AutoHotkey ! =========="
    $cmd = [System.IO.Path]::Combine($env:LOCALAPPDATA, "Programs\AutoHotkey\UX\AutoHotkeyUX.exe")
    $arg = [System.IO.Path]::Combine($env:USERPROFILE, ".dotfiles\win\AutoHotkey\AutoHotkey.ahk")
    $dir = Split-Path -Parent $arg
    $ret = Execute-Process ([PSCustomObject]@{ cmd =  $cmd; arg = $arg; dir = $dir; wait = $false })
    log "code: $($ret.code)"
    log "stdout: $($ret.stdout)"
    log "stderr: $($ret.stderr)"
    log "========== Start clnch ! =========="
    $cmd = [System.IO.Path]::Combine($env:USERPROFILE, "app\clnch\clnch.exe")
    $dir = Split-Path -Parent $cmd
    $ret = Execute-Process ([PSCustomObject]@{ cmd =  $cmd; dir = $dir; wait = $false })
    log "code: $($ret.code)"
    log "stdout: $($ret.stdout)"
    log "stderr: $($ret.stderr)"
    log "========== Start espanso ! =========="
    $cmd = [System.IO.Path]::Combine($env:LOCALAPPDATA, "Programs\Espanso\espansod.exe")
    $arg = "launcher"
    $ret = Execute-Process ([PSCustomObject]@{ cmd =  $cmd; arg = $arg; wait = $false })
    log "code: $($ret.code)"
    log "stdout: $($ret.stdout)"
    log "stderr: $($ret.stderr)"

    return $app.cnst.SUCCESS

  } catch {
    Write-Host "[Start-Main] Error ! $_"
    log "[Start-Main] Error ! $_" "Red"
    # Enable-RunSpaceDebug -BreakAll
    return $app.cnst.ERROR
  } finally {
    if ($null -ne $app -and $app.lock) {
      $app.mutex.ReleaseMutex()
      $app.mutex.Close()
      $app.mutex.Dispose()
    }
    log "[Start-Main] End"
    Stop-Transcript
  }
}

# Call main.
exit Start-Main

# vim: ft=ps1
